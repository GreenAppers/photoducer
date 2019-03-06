import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:scoped_model/scoped_model.dart';

import 'package:photoducer/pixel_buffer.dart';

enum Input { reset, nop, color, strokeCap, strokeWidth, lines }

class PhotographTransducer extends Model {
  PixelBuffer state;
  VoidCallback updateState;
  List<MapEntry<Input, Object>> input;

  PhotographTransducer() {
    updateState = updateStatePaintDelta;
    reset();
  }

  int get version { return input.length; }

  void reset([ui.Image image]) {
    input = <MapEntry<Input, Object>>[];
    if (image != null) {
      input.add(MapEntry<Input, Object>(Input.reset, image));
      state = PixelBuffer.fromImage(image, version);
      notifyListeners();
    } else {
      state = PixelBuffer(Size(256, 256));
    }
    state.addListener(updatedState);
  }

  void addNop() {
    input.add(MapEntry<Input, Object>(Input.nop, null));
  }

  void addLines(Offset point) {
    input.add(MapEntry<Input, Object>(Input.lines, point));
    updateState();
  }

  int transduce(Canvas canvas, Size size, {int startVersion=0, int endVersion=-1}) {
    Paint penState = Paint();
    penState.color = Colors.black;
    penState.strokeCap = StrokeCap.round;
    penState.strokeWidth = 1.0;

    int i = startVersion;
    endVersion = endVersion < 0 ? version : min(endVersion, version);
    for (/**/; i < endVersion; i++) {
      var x = input[i];

      switch (input[i].key) {
        case Input.reset:
          canvas.drawImage(x.value, Offset(0, 0), penState);
          break;

        case Input.color:
          penState.color = x.value;
          break;
      
        case Input.strokeCap:
          penState.strokeCap = x.value;
          break;
      
        case Input.strokeWidth:
          penState.strokeWidth = x.value;
          break;
      
        case Input.lines:
          for (/**/; i < endVersion-1 && input[i+1].key == Input.lines; i++) {
            Offset p1 = input[i].value, p2 = input[i+1].value;
            canvas.drawLine(p1, p2, penState);
          }
          break;
      
        default:
          break;
      }
    }
    return endVersion;
  }
 
  void updatedState(ImageInfo image, bool synchronousCall) {
    notifyListeners();
    if (state.paintedUserVersion != version) updateState();
  }

  void updateStateRepaint() {
    if (state.paintingUserVersion != 0) return;
    state.paintUploaded(
      userVersion: version,
      painter: PhotographTransducerPainter(this),
    );
  }

  void updateStatePaintDelta() {
    if (state.paintingUserVersion != 0) return;
    state.paintUploaded(
      userVersion: version,
      painter: PhotographTransducerPainter(
        this,
        startVersion: max(0, state.paintedUserVersion-1)
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
  int startVersion;

  PhotographTransducerPainter(this.transducer, {this.startVersion=0});

  @override
  bool shouldRepaint(PhotographTransducerPainter oldDelegate) {
    return true;
  }

  void paint(Canvas canvas, Size size) {
    transducer.transduce(canvas, size, startVersion: startVersion);
  }
}
