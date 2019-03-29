import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:persistent_canvas/persistent_canvas.dart';
import 'package:persistent_canvas/photograph_transducer.dart';
import 'package:photo_view/photo_view.dart';
import 'package:scoped_model/scoped_model.dart';

enum PhotoducerTool { none, draw }

class PhotoducerModel extends Model {
  PhotoducerTool tool = PhotoducerTool.draw;
  List objectRecognition;

  void setState(VoidCallback stateChangeCb) {
    stateChangeCb();
    notifyListeners();
  }

  void reset() {
    setState((){ objectRecognition = null; });
  }

  void setTool(PhotoducerTool x) {
    setState((){ tool = x; });
  }

  void setObjectRecognition(List x) {
    setState((){ objectRecognition = x; });
  }
}

class Photoducer extends StatelessWidget {
  final PhotoducerModel state;
  final PersistentCanvas persistentCanvas;

  Photoducer(this.state, this.persistentCanvas);

  @override
  Widget build(BuildContext context) {
    return PhotoView.customChild(
      child: ScopedModel<PhotoducerModel>(
        model: state,
        child: ScopedModelDescendant<PhotoducerModel>(
          builder: (context, child, cart) => _Photoducer(state, persistentCanvas),
        ),
      ),
      childSize: persistentCanvas.model.state.size,
      maxScale: PhotoViewComputedScale.covered * 2.0,
      minScale: PhotoViewComputedScale.contained * 0.8,
      initialScale: PhotoViewComputedScale.covered,
      backgroundDecoration: BoxDecoration(color: Colors.blueGrey[50]),
    );
  }
}

class _Photoducer extends StatefulWidget {
  final PhotoducerModel state;
  final PersistentCanvas persistentCanvas;

  _Photoducer(this.state, this.persistentCanvas);

  @override
  _PhotoducerState createState() => _PhotoducerState();
}

class _PhotoducerState extends State<_Photoducer> {
  int dragCount = 0;

  PhotographTransducer model() { return widget.persistentCanvas.model; }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        buildGestureDetector(context, PersistentCanvasWidget(widget.persistentCanvas)),
        Stack(children: buildObjectRecognitionBoxes(context)),
      ],
    );
  }

  Widget buildGestureDetector(BuildContext context, Widget child) {
    switch (widget.state.tool) {
      case PhotoducerTool.draw:
        return RawGestureDetector(
          child: child,
          behavior: HitTestBehavior.opaque,
          gestures: <Type, GestureRecognizerFactory>{
            ImmediateMultiDragGestureRecognizer: GestureRecognizerFactoryWithHandlers<ImmediateMultiDragGestureRecognizer>(
              () => ImmediateMultiDragGestureRecognizer(),
              (ImmediateMultiDragGestureRecognizer instance) {
                instance..onStart = (Offset position) { return dragCount > 0 ? null : _DrawDragHandler(this, context); };
              }
            )
          }
        );

      default:
        return child;
    }
  }

  List<Widget> buildObjectRecognitionBoxes(BuildContext context) {
    if (widget.state.objectRecognition == null) return [];
    RenderBox box = context.findRenderObject();
    Color blue = Color.fromRGBO(37, 213, 253, 1.0);
    return widget.state.objectRecognition.map((re) {
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

class _DrawDragHandler extends Drag {
  final _PhotoducerState parent;
  final BuildContext context;
  Offset lastPoint;

  _DrawDragHandler(this.parent, this.context) {
    parent.dragCount++;
  }

  @override
  void update(DragUpdateDetails update) {
    RenderBox box = context.findRenderObject();
    Offset point = box.globalToLocal(update.globalPosition);
    if (point.dx >=0 && point.dy >= 0 && point.dx < box.size.width && point.dy < box.size.height) {
      if (lastPoint == null) lastPoint = point;
      if (lastPoint != point) {
        parent.widget.persistentCanvas.drawLine(lastPoint, point, null);
        lastPoint = point;
      }
    }
  }

  @override
  void end(DragEndDetails details) {
    parent.dragCount--;
  }

  @override
  void cancel(){}
}
