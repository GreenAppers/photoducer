import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:scoped_model/scoped_model.dart';
import 'package:photoducer/pixel_buffer.dart';

enum Input { reset, nop, color, strokeCap, strokeWidth, lines }

class PhotographTransducer extends Model {
  int version;
  PixelBuffer state;
  List<MapEntry<Input, Object>> input;
  List<MapEntry<int, ui.Image>> cache;

  PhotographTransducer() {
    reset();
  }

  void reset([ui.Image image]) {
    version = 0;
    input = <MapEntry<Input, Object>>[];
    cache = <MapEntry<int, ui.Image>>[];
    if (image != null) {
      input.add(MapEntry<Input, Object>(Input.reset, image));
      version++;
      state = PixelBuffer.fromImage(image, version);
      notifyListeners();
    } else {
      state = PixelBuffer(Size(256, 256));
    }
    state.addListener(updatedState);
  }

  void addNop() {
    input.add(MapEntry<Input, Object>(Input.nop, null));
    version++;
  }

  void addLines(Offset point) {
    input.add(MapEntry<Input, Object>(Input.lines, point));
    version++;
    updateState();
  }

  int transduce(Canvas canvas, Size size) {
    Paint penState = Paint();
    penState.color = Colors.black;
    penState.strokeCap = StrokeCap.round;
    penState.strokeWidth = 1.0;

    for (int i = 0; i < input.length; i++) {
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
          for (/**/; i < input.length-1 && input[i+1].key == Input.lines; i++) {
            Offset p1 = input[i].value, p2 = input[i+1].value;
            canvas.drawLine(p1, p2, penState);
          }
          break;
      
        default:
          break;
      }
    }
    return version;
  }

  void updateState() {
    if (state.paintingUserVersion != 0) return;
    state.paintUploaded(
      userVersion: version,
      painter: PhotographTransducerPainter(this),
    );
  }

  void updatedState(ImageInfo image, bool synchronousCall) {
    notifyListeners();
    if (state.paintedUserVersion != version) updateState();
  }

  Future<ui.Image> renderImage() async {
    return state.uploaded;
  }
}

class PhotographTransducerPainter extends CustomPainter {
  PhotographTransducer transducer;
  int paintedVersion = 0;

  PhotographTransducerPainter(this.transducer);

  @override
  bool shouldRepaint(PhotographTransducerPainter oldDelegate) {
    return true;
  }

  void paint(Canvas canvas, Size size) {
    paintedVersion = transducer.transduce(canvas, size);
  }
}
