import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

typedef ImgCallback = void Function(img.Image);
typedef ImageCallback = void Function(ui.Image);

class PixelBuffer extends ImageStreamCompleter {
  Size size;
  ui.Image uploaded;
  img.Image downloaded;
  bool autoUpload = true, autoDownload = false;
  int uploadedVersion = 0, uploadingVersion = 0;
  int downloadedVersion = 0, downloadingVersion = 0;
  int paintedUserVersion = 0, paintingUserVersion = 0;

  PixelBuffer(this.size) {
    paintUploaded();
  }

  PixelBuffer.fromImage(this.uploaded, [this.paintedUserVersion=1]) :
    size = Size(uploaded.width.toDouble(), uploaded.height.toDouble()) {
    setUploadedState((ui.Image x) {});
  }

  PixelBuffer.fromImg(this.downloaded) :
    size = Size(downloaded.width.toDouble(), downloaded.height.toDouble()) {
    setDownloadedState((img.Image x) {});
  }

  void paintUploaded({CustomPainter painter, ui.Image startingImage, int userVersion=1}) {
    paintingUserVersion = userVersion;
    ui.PictureRecorder recorder = ui.PictureRecorder();
    Canvas canvas = Canvas(recorder);
    canvas.drawColor(Colors.white, BlendMode.src);
    if (startingImage != null) canvas.drawImage(startingImage, Offset(0, 0), Paint());
    if (painter != null) painter.paint(canvas, size);
    recorder.endRecording().toImage(size.width.floor(), size.height.floor()).then(paintUploadedComplete);
  }

  void paintUploadedComplete(ui.Image nextFrame) {
    paintedUserVersion = paintingUserVersion;
    paintingUserVersion = 0;
    setUploadedState((ui.Image x) { uploaded = nextFrame; });
  }

  void setUploadedState(ImageCallback cb) {
    cb(uploaded);
    uploadedVersion++;
    broadcastUploaded();
    if (autoDownload && downloadingVersion == 0) {
      downloadUploaded(downloadUploadedComplete);
    }
  }

  void setDownloadedState(ImgCallback cb) {
    cb(downloaded);
    downloadedVersion++;
    if (autoUpload && uploadingVersion == 0) {
      uploadDownloaded(uploadDownloadedComplete);
    }
  }

  void downloadUploadedComplete(img.Image nextFrame) {
    downloaded = nextFrame;
    downloadedVersion = downloadingVersion;
    downloadingVersion = 0;
    if (autoDownload && uploadedVersion > downloadedVersion) {
      downloadUploaded(downloadUploadedComplete);
    }
  }

  void uploadDownloadedComplete(ui.Image nextFrame) {
    uploaded = nextFrame;
    uploadedVersion = uploadingVersion;
    uploadingVersion = 0;
    broadcastUploaded();
    if (downloadedVersion != uploadedVersion) {
      uploadDownloaded(uploadDownloadedComplete);
    }
  }

  void broadcastUploaded() {
    setImage(ImageInfo(image: uploaded));
  }

  void downloadUploaded(ImgCallback cb) {
    downloadingVersion = uploadedVersion;
    imgFromImage(uploaded).then(cb);
  }

  void uploadDownloaded(ImageCallback cb) {
    uploadingVersion = downloadedVersion;
    imageFromImg(downloaded).then(cb);
  }
}

class PixelBufferImageProvider extends ImageProvider<PixelBufferImageProvider> {
  PixelBuffer pixelBuffer;
  PixelBufferImageProvider(this.pixelBuffer);

  @override
  Future<PixelBufferImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<PixelBufferImageProvider>(this);
  }

  @override
  ImageStreamCompleter load(PixelBufferImageProvider key) {
    if (key.pixelBuffer.uploaded != null) key.pixelBuffer.broadcastUploaded();
    return key.pixelBuffer;
  }
}

class PixelBufferPainter extends CustomPainter {
  ui.Image pixelBuffer;

  PixelBufferPainter(PixelBuffer pb) : pixelBuffer = pb.uploaded;

  @override
  bool shouldRepaint(PixelBufferPainter oldDelegate) {
    return pixelBuffer != oldDelegate.pixelBuffer;
  }

  void paint(Canvas canvas, Size size) {
    if (pixelBuffer == null) return;
    canvas.drawImage(pixelBuffer, Offset(0, 0), Paint());
  }
}

Future<img.Image> imgFromImage(ui.Image input) async {
  var rgbaBytes = await input.toByteData(format: ui.ImageByteFormat.rawRgba);
  return img.Image.fromBytes(input.width, input.height, rgbaBytes.buffer.asUint8List());
}

Future<ui.Image> imageFromImg(img.Image input) async {
  Completer<ui.Image> completer = Completer(); 
  ui.decodeImageFromPixels(input.getBytes(), input.width, input.height, ui.PixelFormat.rgba8888,
                           (ui.Image result) { completer.complete(result); });
  return completer.future;
}

Future<String> stashImagePath(String name) async {
  Directory directory = await getApplicationDocumentsDirectory();
  return directory.path + Platform.pathSeparator + name + ".png";
}

Future<String> stashImage(ui.Image image, String name) async {
  var pngBytes = await image.toByteData(format: ui.ImageByteFormat.png);
  String path = await stashImagePath(name);
  File(path).writeAsBytesSync(pngBytes.buffer.asInt8List());
  return path;
}

Float32List imgToFloat32List(img.Image image, int inputSize, double mean, double std) {
  var convertedBytes = Float32List(1 * inputSize * inputSize * 3);
  var buffer = Float32List.view(convertedBytes.buffer);
  int pixelIndex = 0;
  for (var i = 0; i < inputSize; i++) {
    for (var j = 0; j < inputSize; j++) {
      var pixel = image.getPixel(j, i);
      buffer[pixelIndex++] = (img.getRed  (pixel) - mean) / std;
      buffer[pixelIndex++] = (img.getGreen(pixel) - mean) / std;
      buffer[pixelIndex++] = (img.getBlue (pixel) - mean) / std;
    }
  }
  return convertedBytes;
}

img.Image imgFromFloat32List(Float32List image, int inputSize, double mean, double std) {
  img.Image ret = img.Image(inputSize, inputSize);
  var buffer = Float32List.view(image.buffer);
  int pixelIndex = 0;
  for (var i = 0; i < inputSize; i++) {
    for (var j = 0; j < inputSize; j++) {
      var x = buffer[pixelIndex+0] * std - mean;
      var y = buffer[pixelIndex+1] * std - mean;
      var z = buffer[pixelIndex+2] * std - mean;

      ret.setPixel(j, i, img.getColor(
        (buffer[pixelIndex+0] * std - mean).round(),
        (buffer[pixelIndex+1] * std - mean).round(),
        (buffer[pixelIndex+2] * std - mean).round()));
      pixelIndex += 3;
    }
  }
  return ret;
}
