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
  img.Image data;
  ui.Image uploaded;
  int dataVersion = 0, uploadedVersion = 0, uploadingVersion = 0;

  PixelBuffer(this.data);

  void upload(ImageCallback cb) {
    uploadingVersion = dataVersion;
    imageFromImg(data).then(cb);
  }

  void setState(ImgCallback cb) {
    cb(data);
    dataVersion++;
    if (uploadingVersion == 0) {
      upload(setStateComplete);
    }
  }

  void setStateComplete(ui.Image nextFrame) {
    uploaded = nextFrame;
    uploadedVersion = uploadingVersion;
    uploadingVersion = 0;
    setUploadedImage();
    if (dataVersion != uploadedVersion) {
      upload(setStateComplete);
    }
  }

  void setUploadedImage() {
    setImage(ImageInfo(image: uploaded));
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
    if (key.pixelBuffer.uploaded != null) key.pixelBuffer.setUploadedImage();
    return key.pixelBuffer;
  }
}

class PixelBufferPainter extends CustomPainter {
  PixelBuffer pixelBuffer;
  int paintedVersion = 0;

  PixelBufferPainter(this.pixelBuffer);

  @override
  bool shouldRepaint(PixelBufferPainter oldDelegate) {
    return paintedVersion != pixelBuffer.uploadedVersion;
  }

  void paint(Canvas canvas, Size size) {
    if (pixelBuffer.uploaded == null) return;
    paintedVersion = pixelBuffer.uploadedVersion;
    canvas.drawImage(pixelBuffer.uploaded, Offset(0, 0), Paint());
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
