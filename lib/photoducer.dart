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

enum Corner { topLeft, topRight, bottomRight, bottomLeft }

enum PhotoducerTool { none, draw, colorSample, fillFlood, selectBox, selectFlood, selectMove, selectScale }

class PhotoducerModel extends Model {
  PhotoducerTool tool = PhotoducerTool.draw;
  int layerIndex;
  Path selection;
  ui.Image pasteBuffer;
  List objectRecognition;

  void setState(VoidCallback stateChangeCb) {
    stateChangeCb();
    notifyListeners();
  }

  void reset() {
    objectRecognition = null;
    resetSelection();
  }

  void resetSelection() {
    setState((){
      selection = null;
      switch(tool) {
        case PhotoducerTool.selectMove:
        case PhotoducerTool.selectScale:
          tool = PhotoducerTool.selectBox;
          break;
      }
    });
  }

  void setTool(PhotoducerTool x) {
    setState((){
      switch(x) {
        case PhotoducerTool.selectBox:
        case PhotoducerTool.selectFlood:
          selection = null;
          break;
        case PhotoducerTool.selectMove:
        case PhotoducerTool.selectScale:
          if (selection == null) return;
          break;
      }
      tool = x;
    });
  }

  void setObjectRecognition(List x) {
    setState((){ objectRecognition = x; });
  }

  void setSelection(Path x) {
    setState((){ selection = x; });
  }

  void setSelectBox(Rect selectBox) {
    setState((){ 
      selection = Path();
      selection.moveTo(selectBox.left, selectBox.top);
      selection.lineTo(selectBox.left + selectBox.width, selectBox.top);
      selection.lineTo(selectBox.left + selectBox.width, selectBox.top + selectBox.height);
      selection.lineTo(selectBox.left, selectBox.top + selectBox.height);
      selection.lineTo(selectBox.left, selectBox.top);
    });
  }

  void copySelection(PersistentCanvas canvas, {bool cut = false}) {
    Rect bounds = selection.getBounds();
    canvas.model.getUploadedState().then((ui.Image unused){
      canvas.model.state.cropUploaded(bounds,
        userVersion: 0,
        clipPath: selection,
        done: (ui.Image x) {
          pasteBuffer = x;
          if (cut) canvas.drawPath(selection, Paint()..color = canvas.model.orthogonalState.backgroundColor);
        }
      );
    });
  }
  
  void pasteToSelection(PersistentCanvas canvas) {
    Rect bounds = selection.getBounds();
    canvas.drawImageRect(pasteBuffer, Rect.fromLTWH(0, 0, pasteBuffer.width.toDouble(), pasteBuffer.height.toDouble()), bounds, Paint());
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
      case PhotoducerTool.selectMove:
        return Icons.open_with;
      case PhotoducerTool.selectScale:
        return Icons.filter_center_focus;
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

/// [LayersView] provides a [ListView] of thumbnails for each layer in [PersistentCanvasLayers]
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

/// [PaintView] wraps [_PaintView] in a zoomable [PhotoView]
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

/// [_PaintView] overlays the [PersistentCanvasLayers] image data
class _PaintView extends StatefulWidget {
  final PhotoducerModel state;
  final PersistentCanvasLayers layers;

  _PaintView(this.state, this.layers);

  @override
  _PaintViewState createState() => _PaintViewState();
}

/// Image overlay layer
class _PaintViewState extends State<_PaintView> {
  Color selectColor = Color.fromRGBO(37, 213, 253, 1.0);
  Color handleColor = Color.fromRGBO(117, 255, 255, 1.0);
  Color pressedColor = Color.fromRGBO(0, 163, 202, 1.0);
  Rect handleRect = Rect.fromLTWH(0, 0, 20, 20); 
  Corner scalingCorner;
  int dragCount = 0;

  PhotographTransducer get model => widget.layers.canvas.model;

  @override
  Widget build(BuildContext context) {
    ScopedModel.of<PhotoducerModel>(context, rebuildOnChange: true);
    BusyModel busy = ScopedModel.of<BusyModel>(context);
    Path selection = widget.state.selection;
    Rect selectionBounds = selection != null ? selection.getBounds() : null;
    List<Widget> stack = <Widget>[];

    if (widget.state.layerIndex == null) {
      stack.add(buildGestureDetector(context, selectionBounds, PersistentCanvasLayersWidget(widget.layers)));
    } else {
      stack.add(buildGestureDetector(context, selectionBounds, PersistentCanvasWidget(widget.layers.layer[widget.state.layerIndex])));
    }
    stack.add(Stack(children: buildObjectRecognitionBoxes(context)));
    if (selection != null) {
      stack.add(buildSelectPath(selection));
      switch (widget.state.tool) {
        case PhotoducerTool.selectMove:
          stack.add(buildMoveHandle(selectionBounds));
          break;
        case PhotoducerTool.selectScale:
          stack.add(
            IgnorePointer(
              ignoring: true,
              child: Stack(
                children: buildScaleHandles(selectionBounds)
              )
            )
          );
          break;
      }
    }

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

  Widget buildGestureDetector(BuildContext context, Rect selection, Widget child) {
    switch (widget.state.tool) {
      case PhotoducerTool.draw:
        return buildDragRecognizer(child, (Offset position) => dragCount > 0 ? null : _DrawDragHandler(this, context));

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
            widget.state.setSelection(path);
          },
        );

      case PhotoducerTool.selectMove:
        assert(selection != null);
        return buildDragRecognizer(child,
          (Offset p) => (dragCount == 0 && centerRect(handleRect, selection.center).contains(localCoordinates(context, p))) ?
            _SelectMoveDragHandler(this, context) : null,
          onTap: (){ widget.state.resetSelection(); },
        );

      case PhotoducerTool.selectScale:
        assert(selection != null);
        return buildDragRecognizer(child,
          (Offset p) {
            if (dragCount > 0) return null;
            p = localCoordinates(context, p);

            if (centerRect(handleRect, selection.topLeft).contains(p))
              return _SelectScaleDragHandler(this, context, Corner.topLeft);
            else if (centerRect(handleRect, selection.topRight).contains(p))
              return _SelectScaleDragHandler(this, context, Corner.topRight);
            else if (centerRect(handleRect, selection.bottomLeft).contains(p))
              return _SelectScaleDragHandler(this, context, Corner.bottomLeft);
            else if (centerRect(handleRect, selection.bottomRight).contains(p))
              return _SelectScaleDragHandler(this, context, Corner.bottomRight);
            else
              return null;
          },
          onTap: (){ widget.state.resetSelection(); },
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

  Widget buildDragRecognizer(Widget child, GestureMultiDragStartCallback onStart, {VoidCallback onTap}) {
    var gestures = <Type, GestureRecognizerFactory> {
      ImmediateMultiDragGestureRecognizer: GestureRecognizerFactoryWithHandlers<ImmediateMultiDragGestureRecognizer>(
        () => ImmediateMultiDragGestureRecognizer(),
        (ImmediateMultiDragGestureRecognizer instance) {
          instance..onStart = onStart;
        }
      )
    };
    if (onTap != null) {
      gestures[TapGestureRecognizer] = GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
        () => TapGestureRecognizer(),
        (TapGestureRecognizer instance) {
          instance..onTap = onTap;
        }
      );
    }
    return RawGestureDetector(
      child: child,
      behavior: HitTestBehavior.opaque,
      gestures: gestures,
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
            color: selectColor,
            width: 2,
          ),
        ),
      ),
    );
  }

  Widget buildSelectPath(Path path) {
    return CustomPaint(
      painter: _DashedPathPainter(path, Paint()
        ..color = selectColor
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke
      ),
    );
  }
  
  Widget buildMoveHandle(Rect selection) {
    return Positioned.fromRect(
      rect: centerRect(handleRect, selection.center),
      child: IgnorePointer(
        ignoring: true,
        child: Icon(Icons.open_with,
          color: dragCount > 0 ? pressedColor : selectColor,
        ),
      ),
    );
  }

  List<Widget> buildScaleHandles(Rect selection) {
    return <Widget> [
      Positioned.fromRect(
        rect: centerRect(handleRect, selection.topLeft),
        child: Icon(Icons.filter_center_focus,
          color: dragCount > 0 ? pressedColor : handleColor,
        ),
      ),

      Positioned.fromRect(
        rect: centerRect(handleRect, selection.topRight),
        child: Icon(Icons.filter_center_focus,
          color: dragCount > 0 ? pressedColor : handleColor,
        ),
      ),

      Positioned.fromRect(
        rect: centerRect(handleRect, selection.bottomRight),
        child: Icon(Icons.filter_center_focus,
          color: dragCount > 0 ? pressedColor : handleColor,
        ),
      ),

      Positioned.fromRect(
        rect: centerRect(handleRect, selection.bottomLeft),
        child: Icon(Icons.filter_center_focus,
          color: dragCount > 0 ? pressedColor : handleColor,
        ),
      ),
    ];
  }

  List<Widget> buildObjectRecognitionBoxes(BuildContext context) {
    if (widget.state.objectRecognition == null) return [];
    RenderBox box = context.findRenderObject();
    Color blue = selectColor;
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
    if (--parent.dragCount == 0)
      parent.setState((){});
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

class _SelectMoveDragHandler extends _DragHandler {
  Path orig;
  Offset firstPoint;

  _SelectMoveDragHandler(_PaintViewState parent, BuildContext context) :
    orig=parent.widget.state.selection, super(parent, context);

  @override
  void dragUpdate(Offset point) {
    if (firstPoint == null) firstPoint = point;
    parent.widget.state.setSelection(orig.shift(point - firstPoint));
  }
}

class _SelectScaleDragHandler extends _DragHandler {
  Path orig;
  Rect origRect;
  Corner corner;
  Offset firstPoint;

  _SelectScaleDragHandler(_PaintViewState parent, BuildContext context, this.corner) :
    orig=parent.widget.state.selection, super(parent, context) {
    origRect = orig.getBounds();
    parent.scalingCorner = corner;
  }

  @override
  void dragUpdate(Offset point) {
    if (firstPoint == null) firstPoint = point;
    Offset offset = Offset(0, 0), delta = point - firstPoint;
    bool scaleDirX=false, scaleDirY=false;

    switch(corner) {
      case Corner.topLeft:
        offset = delta;
        break;
      case Corner.topRight:
        scaleDirX = true;
        offset = Offset(0, delta.dy);
        break;
      case Corner.bottomRight:
        scaleDirX = true;
        scaleDirY = true;
        break;
      case Corner.bottomLeft:
        scaleDirY = true;
        offset = Offset(delta.dx, 0);
        break;
    }

    Offset scale = Offset(1.0 + delta.dx / origRect.width  * (scaleDirX ? 1 : -1),
                          1.0 + delta.dy / origRect.height * (scaleDirY ? 1 : -1));
    Matrix4 matrix = Matrix4.identity();

    matrix.translate((origRect.left + offset.dx),
                     (origRect.top  + offset.dy));
    matrix.scale(scale.dx,
                 scale.dy);
    matrix.translate((-origRect.left),
                     (-origRect.top ));

    parent.widget.state.setSelection(orig.transform(matrix.storage));
  }
}

String assetPath(String name) => 'assets' + Platform.pathSeparator + name;

String enumName(var x) {
  String ret = x.toString().split('.')[1];
  return ret.length > 0 ? ret[0].toUpperCase() + ret.substring(1) : ret;
}

Rect centerRect(Rect x, Offset c) =>
  Rect.fromLTWH(c.dx - x.width / 2.0, c.dy - x.height / 2.0, x.width, x.height);

Offset localCoordinates(BuildContext context, Offset p) {
  RenderBox box = context.findRenderObject();
  return box.globalToLocal(p);
}

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
