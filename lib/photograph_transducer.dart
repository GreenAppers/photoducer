import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:image/image.dart' as img;
import 'package:scoped_model/scoped_model.dart';

import 'package:photoducer/pixel_buffer.dart';

class OrthogonalState {
  Paint paint = Paint();

  OrthogonalState() {
    paint.color = Colors.black;
    paint.strokeCap = StrokeCap.round;
    paint.strokeWidth = 1.0;
  }
}

typedef UploadedStateTransform = void Function(Canvas, Size, OrthogonalState, Object);
typedef DownloadedStateTransform = img.Image Function(img.Image);
typedef BackendTextureStateTransform = void Function(int);

class Input {
  Object transform;
  Object value;

  Input(this.transform, this.value);
}

class PhotographTransducer extends Model {
  int version;
  PixelBuffer state;
  VoidCallback updateStateMethod;
  OrthogonalState orthogonalState;
  List<Input> input;

  PhotographTransducer() {
    updateStateMethod = updateStatePaintDelta;
    reset();
  }

  bool isProcessing() {
    return input.length > 0 && input.last.value == null &&
      (input.last.transform is DownloadedStateTransform || input.last.transform is BackendTextureStateTransform);
  }

  void reset([ui.Image image]) {
    version = 0;
    input = <Input>[];
    if (image != null) {
      addRedraw(image);
      state = PixelBuffer.fromImage(image, version);
      notifyListeners();
    } else {
      state = PixelBuffer(Size(256, 256));
    }
    state.addListener(updatedState);
    orthogonalState = OrthogonalState();
  }

  void addInput(Input x) {
    assert(!isProcessing());
    if (version < input.length) input.removeRange(version, input.length);
    input.add(x);
    version++;
  }

  void addRedraw(ui.Image image) {
    addInput(Input((Canvas canvas, Size size, OrthogonalState o, Object x) => canvas.drawImage(x, Offset(0, 0), o.paint), image));
  }

  void addChangeColor(Color color) {
    addInput(Input((Canvas canvas, Size size, OrthogonalState o, Object x) => o.paint.color = x, color));
  }

  void addDownloadedTransform(ImgFilter filter) {
    addInput(Input(filter, null));
    if (state.paintingUserVersion == 0)
      startProcessing();
  }

  void startProcessing() {
    assert(state.paintedUserVersion == version-1);
    state.transformDownloaded(input.last.transform, userVersion: version);
  }

  void walkVersion(int n) {
    version += n;
    version = version.clamp(0, input.length);
    updateState();
  }

  int transduce(Canvas canvas, Size size, {int startVersion=0, int endVersion}) {
    if (startVersion == 0) orthogonalState = OrthogonalState();
    var o = orthogonalState;
    int i = startVersion;
    endVersion = endVersion == null ? version : min(endVersion, version);
    for (/**/; i < endVersion; i++) {
      var x = input[i];
      if (x.value == null) return i;
      if (x.transform is UploadedStateTransform) {
        (x.transform as UploadedStateTransform)(canvas, size, orthogonalState, x.value);
      } else {
        canvas.drawImage(x.value, Offset(0, 0), orthogonalState.paint);
      }
    }
    return endVersion;
  }

  void updateState() {
    if (version == state.paintedUserVersion || isProcessing()) return;
    if (version < state.paintedUserVersion) return updateStateRepaint();
    else updateStateMethod();
  }
 
  void updatedState(ImageInfo image, bool synchronousCall) {
    if (isProcessing()) {
      if (state.transformedUserVersion == version)
        input.last.value = state.uploaded;
      else
        startProcessing();
    }
    notifyListeners();
    updateState();
  }

  void updateStateRepaint() {
    if (state.paintingUserVersion != 0) return;
    state.paintUploaded(
      userVersion: version,
      painter: PhotographTransducerPainter(this,
        endVersion: version,
      ),
    );
  }

  void updateStatePaintDelta() {
    if (state.paintingUserVersion != 0) return;
    state.paintUploaded(
      userVersion: version,
      painter: PhotographTransducerPainter(this,
        startVersion: max(0, state.paintedUserVersion-1),
        endVersion: version,
      ),
      startingImage: state.uploaded,
    );
  }
}

class PhotographTransducerPainter extends CustomPainter {
  PhotographTransducer transducer;
  int startVersion, endVersion;

  PhotographTransducerPainter(
    this.transducer, {this.startVersion=0, this.endVersion}
  );

  @override
  bool shouldRepaint(PhotographTransducerPainter oldDelegate) {
    return true;
  }

  void paint(Canvas canvas, Size size) {
    transducer.transduce(canvas, size,
      startVersion: startVersion,
      endVersion: endVersion,
    );
  }
}
