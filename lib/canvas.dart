import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:scoped_model/scoped_model.dart';

import 'package:photoducer/pixel_buffer.dart';
import 'package:photoducer/photograph_transducer.dart';

enum PhotoducerCanvasTool { none, draw }

class PhotoducerCanvas extends StatefulWidget {
  final PhotographTransducer transducer;
  PhotoducerCanvas(Key key, this.transducer): super(key: key);

  @override
  State<StatefulWidget> createState() {
    return PhotoducerCanvasState();
  }
}

class PhotoducerCanvasState extends State<PhotoducerCanvas> {
  PhotoducerCanvasTool tool = PhotoducerCanvasTool.draw;
  List objectRecognition;

  void reset([ui.Image image]) {
    setState(() {
      widget.transducer.reset(image);
      objectRecognition = null;
    });
  }

  void setTool(PhotoducerCanvasTool x) {
    setState(() { tool = x; });
  }

  void setObjectRecognition(List x) {
    setState(() { objectRecognition = x; });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        buildGestureDetector(
          Container(
            width: widget.transducer.state.size.width,
            height: widget.transducer.state.size.height,
            alignment: Alignment.topLeft,
            color: Colors.white,
            child: RepaintBoundary(
              child: ScopedModel<PhotographTransducer>(
                model: widget.transducer,
                child: ScopedModelDescendant<PhotographTransducer>(
                  builder: (context, child, cart) => CustomPaint(
                    painter: PixelBufferPainter(widget.transducer.state)
                  ),
                ),
              ),
            ),
          ),
        ),
      
        Stack(children: buildObjectRecognitionBoxes(context)),
      ],
    );
  }

  Widget buildGestureDetector(Widget child) {
    switch (tool) {
      case PhotoducerCanvasTool.none:
        return child;

      case PhotoducerCanvasTool.draw:
        return GestureDetector(
          onPanUpdate: (DragUpdateDetails details) {
            RenderBox box = context.findRenderObject();
            Offset point = box.globalToLocal(details.globalPosition);
            if (point.dx >=0 && point.dy >= 0 && point.dx < box.size.width && point.dy < box.size.height) {
              widget.transducer.addLines(point);
            }
          },

          onPanEnd: (DragEndDetails details) {
            widget.transducer.addNop();
          },

          child: child
        );

      default:
        return null;
    }
  }

  List<Widget> buildObjectRecognitionBoxes(BuildContext context) {
    if (objectRecognition == null) return [];
    RenderBox box = context.findRenderObject();
    Color blue = Color.fromRGBO(37, 213, 253, 1.0);
    return objectRecognition.map((re) {
      return Positioned(
        left:   re["rect"]["x"] * box.size.width,
        top:    re["rect"]["y"] * box.size.height,
        width:  re["rect"]["w"] * box.size.width,
        height: re["rect"]["h"] * box.size.height,
        child:  Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: blue,
              width: 2,
            ),
          ),
          child: Text(
            "${re["detectedClass"]} ${(re["confidenceInClass"] * 100).toStringAsFixed(0)}%",
            style: TextStyle(
              background: Paint()..color = blue,
              color: Colors.white,
              fontSize: 12.0,
            ),
          ),
        ),
      );
    }).toList();
  }
}