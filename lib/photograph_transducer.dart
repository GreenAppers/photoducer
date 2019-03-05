import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:photoducer/pixel_buffer.dart';

enum Input { reset, nop, color, strokeCap, strokeWidth, lines }

class PhotographTransducerState {
  Size size = Size(256, 256);
  bool uploaded = true;
  PixelBuffer downloaded;
}

class PhotographTransducer {
  int version = 0;
  PhotographTransducerState state = PhotographTransducerState();
  List<MapEntry<Input, Object>> input = <MapEntry<Input, Object>>[];
  List<MapEntry<int, ui.Image>> cache = <MapEntry<int, ui.Image>>[];

  void reset(ui.Image image) {
    version = 0;
    input = <MapEntry<Input, Object>>[];
    cache = <MapEntry<int, ui.Image>>[];
    if (image != null) {
      state.size = Size(image.width.toDouble(), image.height.toDouble());
      input.add(MapEntry<Input, Object>(Input.reset, image));
      version++;
    } else {
      state.size = Size(256, 256);
    }
  }

  void addNop() {
    input.add(MapEntry<Input, Object>(Input.nop, null));
    version++;
  }

  void addLines(Offset point) {
    input.add(MapEntry<Input, Object>(Input.lines, point));
    version++;
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

  Future<ui.Image> renderImage() async {
    ui.PictureRecorder recorder = ui.PictureRecorder();
    Canvas canvas = Canvas(recorder);
    transduce(canvas, state.size);
    return recorder.endRecording().toImage(state.size.width.floor(), state.size.height.floor());
  }
}

class PhotographTransducerPainter extends CustomPainter {
  PhotographTransducer transducer;
  List transducerInput;
  int paintedVersion = 0;

  PhotographTransducerPainter(this.transducer) {
    transducerInput = transducer.input;
  }

  @override
  bool shouldRepaint(PhotographTransducerPainter oldDelegate) {
    return paintedVersion != transducer.version || transducerInput != oldDelegate.transducerInput;
  }

  void paint(Canvas canvas, Size size) {
    paintedVersion = transducer.transduce(canvas, size);
  }
}

