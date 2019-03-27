import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:scoped_model/scoped_model.dart';

import 'package:photoducer/pixel_buffer.dart';

enum StateRepresentation { none, uploaded, downloaded, backendTexture }

enum InputType { reset, nop, color, strokeCap, strokeWidth, lines, blur }

class Input {
  StateRepresentation scope;
  InputType key;
  Object value; 

  Input(this.scope, this.key, this.value);
}

class OrthogonalState {
  Paint paint = Paint();

  OrthogonalState() {
    paint.color = Colors.black;
    paint.strokeCap = StrokeCap.round;
    paint.strokeWidth = 1.0;
  }
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

  void reset([ui.Image image]) {
    version = 0;
    input = <Input>[];
    if (image != null) {
      addInput(Input(StateRepresentation.uploaded, InputType.reset, image));
      state = PixelBuffer.fromImage(image, version);
      notifyListeners();
    } else {
      state = PixelBuffer(Size(256, 256));
    }
    state.addListener(updatedState);
    orthogonalState = OrthogonalState();
  }

  void addInput(Input x) {
    if (version < input.length) input.removeRange(version, input.length);
    input.add(x);
    version++;
  }

  void addNop() {
    addInput(Input(StateRepresentation.none, InputType.nop, null));
  }

  void addLines(Offset point) {
    if (input.length > 0 && input.last.key == InputType.lines && input.last.value == point) return;
    addInput(Input(StateRepresentation.uploaded, InputType.lines, point));
    updateState();
  }

  void changeColor(Color color) {
    addInput(Input(StateRepresentation.none, InputType.color, color));
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

      switch (input[i].key) {
        case InputType.blur:
          if (!x.value) {
            return i;
          }
          continue;

        case InputType.reset:
          canvas.drawImage(x.value, Offset(0, 0), o.paint);
          break;

        case InputType.color:
          o.paint.color = x.value;
          break;
      
        case InputType.strokeCap:
          o.paint.strokeCap = x.value;
          break;
      
        case InputType.strokeWidth:
          o.paint.strokeWidth = x.value;
          break;
      
        case InputType.lines:
          for (/**/; i < endVersion-1 && input[i+1].key == InputType.lines; i++) {
            Offset p1 = input[i].value, p2 = input[i+1].value;
            canvas.drawLine(p1, p2, o.paint);
          }
          break;
      
        default:
          break;
      }
    }
    return endVersion;
  }

  void updateState() {
    if (version == state.paintedUserVersion) return;
    if (version < state.paintedUserVersion) return updateStateRepaint();
    else updateStateMethod();
  }
 
  void updatedState(ImageInfo image, bool synchronousCall) {
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

  Future<ui.Image> renderImage() async {
    return state.uploaded;
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
