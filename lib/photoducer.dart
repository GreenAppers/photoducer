import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:busy_model/busy_model.dart';
import 'package:image/image.dart' as img;
import 'package:path_drawing/path_drawing.dart';
import 'package:persistent_canvas/persistent_canvas.dart';
import 'package:persistent_canvas/photograph_transducer.dart';
import 'package:persistent_canvas/pixel_buffer.dart';
import 'package:photo_view/photo_view.dart';
import 'package:potrace/potrace.dart';
import 'package:scoped_model/scoped_model.dart';

typedef OffsetCallback = void Function(Offset);

enum PhotoducerTool { none, draw, selectBox, selectFlood, fillFlood, colorSample }

class PhotoducerModel extends Model {
  PhotoducerTool tool = PhotoducerTool.draw;
  Rect selectBox;
  Path selectFlood;
  List objectRecognition;
  int layerIndex;

  bool get haveSelection => selectFlood != null || selectBox != null;

  void setState(VoidCallback stateChangeCb) {
    stateChangeCb();
    notifyListeners();
  }

  void reset() {
    setState((){
      selectBox = null;
      selectFlood = null;
      objectRecognition = null;
    });
  }

  void setTool(PhotoducerTool x) {
    setState((){
      tool = x;
      switch(tool) {
        case PhotoducerTool.selectBox:
        case PhotoducerTool.selectFlood:
          selectBox = null;
          selectFlood = null;
          break;
      }
    });
  }

  void setSelectBox(Rect x) {
    setState((){ selectBox = x; });
  }

  void setSelectFlood(Path x) {
    setState((){ selectFlood = x; });
  }

  void setObjectRecognition(List x) {
    setState((){ objectRecognition = x; });
  }

  Path getSelection() {
    if (selectFlood != null) return selectFlood;
    if (selectBox == null) return null;
    Path ret = Path();
    ret.moveTo(selectBox.left, selectBox.top);
    ret.lineTo(selectBox.left + selectBox.width, selectBox.top);
    ret.lineTo(selectBox.left + selectBox.width, selectBox.top + selectBox.height);
    ret.lineTo(selectBox.left, selectBox.top + selectBox.height);
    ret.lineTo(selectBox.left, selectBox.top);
    return ret;
  }

  static Icon getToolIcon(PhotoducerTool tool) => Icon(getToolIconData(tool));

  static IconData getToolIconData(PhotoducerTool tool) {
    switch(tool) {
      case PhotoducerTool.none:
        return Icons.pan_tool;
      case PhotoducerTool.draw:
        return Icons.edit;
      case PhotoducerTool.selectBox:
        return Icons.crop_free;
      case PhotoducerTool.selectFlood:
        return Icons.highlight;
      case PhotoducerTool.colorSample:
        return Icons.colorize;
      case PhotoducerTool.fillFlood:
        return Icons.format_color_fill;
    }
  }
}

class PhotoducerScope extends StatelessWidget {
  final PhotoducerModel state;
  final Widget child;

  PhotoducerScope({this.state, this.child});

  @override
  Widget build(BuildContext context) {
    return ScopedModel<PhotoducerModel>(
      model: state,
      child: child,
    );
  }
}

class LayersView extends StatelessWidget {
  final PhotoducerModel state;
  final PersistentCanvasLayers layers;

  LayersView(this.state, this.layers);

  @override
  Widget build(BuildContext context) {
    List<Widget> list = <Widget>[];
    for (var layer in layers.layer)
      list.add(
        Card(
          child: Image(
            image: PixelBufferImageProvider(layer.model.state),
          ),
        ),
      );

    return Container(
      height: 100,
      decoration: BoxDecoration(color: Colors.blueGrey[140]),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(10.0),
        scrollDirection: Axis.horizontal,
        children: list
      ),
    );
  }
}

class PaintView extends StatelessWidget {
  final PhotoducerModel state;
  final PersistentCanvasLayers layers;

  PaintView(this.state, this.layers);

  @override
  Widget build(BuildContext context) {
    BusyModel busy = ScopedModel.of<BusyModel>(context, rebuildOnChange: true);
    return PhotoView.customChild(
      child: _PaintView(state, layers),
      childSize: layers.canvas.model.state.size,
      maxScale: PhotoViewComputedScale.covered * 2.0,
      minScale: PhotoViewComputedScale.contained * 0.8,
      initialScale: PhotoViewComputedScale.covered,
      backgroundDecoration: BoxDecoration(color: Colors.blueGrey[50]),
    );
  }
}

class _PaintView extends StatefulWidget {
  final PhotoducerModel state;
  final PersistentCanvasLayers layers;

  _PaintView(this.state, this.layers);

  @override
  _PaintViewState createState() => _PaintViewState();
}

class _PaintViewState extends State<_PaintView> {
  int dragCount = 0;

  PhotographTransducer get model => widget.layers.canvas.model;

  @override
  Widget build(BuildContext context) {
    ScopedModel.of<PhotoducerModel>(context, rebuildOnChange: true);
    BusyModel busy = ScopedModel.of<BusyModel>(context);
    List<Widget> stack = <Widget>[];
    if (widget.state.layerIndex == null) {
      stack.add(buildGestureDetector(context, PersistentCanvasLayersWidget(widget.layers)));
    } else {
      stack.add(buildGestureDetector(context, PersistentCanvasWidget(widget.layers.layer[widget.state.layerIndex])));
    }
    stack.add(Stack(children: buildObjectRecognitionBoxes(context)));
    if (widget.state.haveSelection)
      stack.add(buildSelectPath(widget.state.getSelection()));

    return BusyModalBarrier(
      model: busy,
      progressIndicator: Center(
        child: Container(
          height: 200,
          child: Column(
            children: <Widget>[
              CircularProgressIndicator(),
              Text(busy.reason != null ? busy.reason : ''),
            ],
          ),
        ),
      ),
      child: Stack(
        children: stack,
      ),
    );
  }

  Widget buildGestureDetector(BuildContext context, Widget child) {
    switch (widget.state.tool) {
      case PhotoducerTool.draw:
        return buildDragRecognizer(child, (Offset position) { return dragCount > 0 ? null : _DrawDragHandler(this, context); });

      case PhotoducerTool.selectBox:
        return buildDragRecognizer(child, (Offset position) { return dragCount > 0 ? null : _SelectBoxDragHandler(this, context); });

      case PhotoducerTool.selectFlood:
        return _TapHandler(context, child,
          onTapped: (Offset point) async {
            model.busy.setBusy('Selecting');
            img.Image downloaded = await model.state.getDownloadedState();
            Uint8List mask = img.maskFlood(downloaded, point.dx.round(), point.dy.round(),
                                           threshold: 20, compareAlpha: true, fillValue: 1);
            Path path = potraceMask(mask, downloaded.width, downloaded.height);
            model.busy.reset();
            widget.state.setSelectFlood(path);
          },
        );

      case PhotoducerTool.fillFlood:
        return _TapHandler(context, child,
          onTapped: (Offset point) async {
            model.busy.setBusy('Filling');
            img.Image downloaded = await model.state.getDownloadedState();
            Uint8List mask = img.maskFlood(downloaded, point.dx.round(), point.dy.round(),
                                           threshold: 20, compareAlpha: true, fillValue: 1);
            Path path = potraceMask(mask, downloaded.width, downloaded.height);
            widget.layers.canvas.drawPath(path, model.orthogonalState.paint);
            model.busy.reset();
          },
        );

      case PhotoducerTool.colorSample:
        return _TapHandler(context, child,
          onTapped: (Offset point) async {
            model.busy.setBusy('Sampling');
            img.Image downloaded = await model.state.getDownloadedState();
            int pixel = downloaded.getPixel(point.dx.round(), point.dy.round());
            Color color = colorFromImgColor(pixel);
            model.changeColor(color);
            model.busy.reset();
          },
        );
        
      default:
        return child;
    }
  }

  Widget buildDragRecognizer(Widget child, GestureMultiDragStartCallback onStart) {
    return RawGestureDetector(
      child: child,
      behavior: HitTestBehavior.opaque,
      gestures: <Type, GestureRecognizerFactory>{
        ImmediateMultiDragGestureRecognizer: GestureRecognizerFactoryWithHandlers<ImmediateMultiDragGestureRecognizer>(
          () => ImmediateMultiDragGestureRecognizer(),
          (ImmediateMultiDragGestureRecognizer instance) {
            instance..onStart = onStart;
          }
        )
      }
    );
  }

  Widget buildSelectRect(Rect box) {
    return Positioned(
      left:   box.left,
      top:    box.top,
      width:  box.width,
      height: box.height,
      child:  Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: Color.fromRGBO(37, 213, 253, 1.0),
            width: 2,
          ),
        ),
      ),
    );
  }

  Widget buildSelectPath(Path path) {
    return CustomPaint(
      painter: _DashedPathPainter(path, Paint()
        ..color = Color.fromRGBO(37, 213, 253, 1.0)
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke
      ),
    );
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

class _DashedPathPainter extends CustomPainter {
  Path path;
  Paint style;
  _DashedPathPainter(this.path, this.style);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      dashPath(
        path,
        dashArray: CircularIntervalList<double>(<double>[3, 6]),
      ),
      style
    );
  }

  @override
  bool shouldRepaint(_DashedPathPainter oldDelegate) =>
    path != oldDelegate.path || style != oldDelegate.style;
}

class _TapHandler extends GestureDetector {
  BuildContext context;
  OffsetCallback onTapped;
  _TapHandler(this.context, Widget child, {@required this.onTapped}) :
    super(
      child: child,
      onTapDown: (TapDownDetails update) {
        RenderBox box = context.findRenderObject();
        Offset point = box.globalToLocal(update.globalPosition);
        if (point.dx >=0 && point.dy >= 0 && point.dx < box.size.width && point.dy < box.size.height)  
          onTapped(point);
      }
    );
}

abstract class _DragHandler extends Drag {
  final _PaintViewState parent;
  final BuildContext context;

  _DragHandler(this.parent, this.context) {
    parent.dragCount++;
  }

  void dragUpdate(Offset point);

  @override
  void end(DragEndDetails details) {
    parent.dragCount--;
  }

  @override
  void update(DragUpdateDetails update) {
    RenderBox box = context.findRenderObject();
    Offset point = box.globalToLocal(update.globalPosition);
    if (point.dx >=0 && point.dy >= 0 && point.dx < box.size.width && point.dy < box.size.height) 
      dragUpdate(point);
  }

  @override
  void cancel(){}
}

class _DrawDragHandler extends _DragHandler {
  Offset lastPoint;

  _DrawDragHandler(_PaintViewState parent, BuildContext context) : super(parent, context);

  @override
  void dragUpdate(Offset point) {
    if (lastPoint == null) lastPoint = point;
    if (lastPoint != point) {
      parent.widget.layers.canvas.drawLine(lastPoint, point, null);
      lastPoint = point;
    }
  }
}

class _SelectBoxDragHandler extends _DragHandler {
  Offset startPoint;

  _SelectBoxDragHandler(_PaintViewState parent, BuildContext context) : super(parent, context);

  @override
  void dragUpdate(Offset point) {
    if (startPoint == null) startPoint = point;
    parent.widget.state.setSelectBox(Rect.fromLTRB(min(point.dx, startPoint.dx), min(point.dy, startPoint.dy),
                                                   max(point.dx, startPoint.dx), max(point.dy, startPoint.dy)));
  }
}

String assetPath(String name) => 'assets' + Platform.pathSeparator + name;

Future<ui.Image> loadAssetFile(String name) async {
  ByteData bytes = await rootBundle.load(assetPath(name));
  return loadImageFileBytes(bytes.buffer.asUint8List());
}

Future<ui.Image> loadImageFile(File file) async {
  List<int> bytes = await file.readAsBytes();
  return loadImageFileBytes(bytes);
}

Future<ui.Image> loadImageFileBytes(List<int> bytes) async {
  ui.Codec codec = await ui.instantiateImageCodec(bytes);
  ui.FrameInfo frame = await codec.getNextFrame();
  return frame.image;
}
