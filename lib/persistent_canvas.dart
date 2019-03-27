import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:scoped_model/scoped_model.dart';

import 'package:photoducer/pixel_buffer.dart';
import 'package:photoducer/photograph_transducer.dart';

class PersistentCanvas implements Canvas {
  final PhotographTransducer model = PhotographTransducer();

  @override
  void clipPath(Path path, { bool doAntiAlias = true }) {
  }

  @override
  void clipRRect(RRect rrect, { bool doAntiAlias = true }) {
  }

  @override
  void clipRect(Rect rect, { ui.ClipOp clipOp = ui.ClipOp.intersect, bool doAntiAlias = true }) {
  }

  @override
  void drawArc(Rect rect, double startAngle, double sweepAngle, bool useCenter, Paint paint) {
  }

  @override
  void drawAtlas(ui.Image atlas, List<RSTransform> transforms, List<Rect> rects, List<Color> colors, BlendMode blendMode, Rect cullRect, Paint paint) {
  }

  @override
  void drawCircle(Offset c, double radius, Paint paint) {
  }

  @override
  void drawColor(Color color, BlendMode blendMode) {
  }

  @override
  void drawDRRect(RRect outer, RRect inner, Paint paint) {
  }

  @override
  void drawImage(ui.Image image, Offset p, Paint paint) {
  }

  @override
  void drawImageNine(ui.Image image, Rect center, Rect dst, Paint paint) {
  }

  @override
  void drawImageRect(ui.Image image, Rect src, Rect dst, Paint paint) {
  }

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) {
  }

  @override
  void drawOval(Rect rect, Paint paint) {
  }

  @override
  void drawPaint(Paint paint) {
  }

  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) {
  }

  @override
  void drawPath(Path path, Paint paint) {
  }

  @override
  void drawPicture(ui.Picture picture) {
  }

  @override
  void drawPoints(ui.PointMode pointMode, List<Offset> points, Paint paint) {
  }

  @override
  void drawRRect(RRect rrect, Paint paint) {
  }

  @override
  void drawRawAtlas(ui.Image atlas, Float32List rstTransforms, Float32List rects, Int32List colors, BlendMode blendMode, Rect cullRect, Paint paint) {
  }

  @override
  void drawRawPoints(ui.PointMode pointMode, Float32List points, Paint paint) {
  }

  @override
  void drawRect(Rect rect, Paint paint) {
  }

  @override
  void drawShadow(Path path, Color color, double elevation, bool transparentOccluder) {
  }

  @override
  void drawVertices(ui.Vertices vertices, BlendMode blendMode, Paint paint) {
  }

  @override
  int getSaveCount() {
		return 0;
  }

  @override
  void restore() {
  }

  @override
  void rotate(double radians) {
  }

  @override
  void save() {
  }

  @override
  void saveLayer(Rect bounds, Paint paint) {
  }

  @override
  void scale(double sx, [ double sy ]) {
  }

  @override
  void skew(double sx, double sy) {
  }

  @override
  void transform(Float64List matrix4) {
  }

  @override
  void translate(double dx, double dy) {
  }
}

class PersistentCanvasWidget extends StatelessWidget {
  final PersistentCanvas canvas;

  PersistentCanvasWidget(this.canvas);

  PhotographTransducer model() { return canvas.model; }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: canvas.model.state.size.width,
      height: canvas.model.state.size.height,
      alignment: Alignment.topLeft,
      color: Colors.white,
      child: RepaintBoundary(
        child: ScopedModel<PhotographTransducer>(
          model: canvas.model,
          child: ScopedModelDescendant<PhotographTransducer>(
            builder: (context, child, cart) => CustomPaint(
              painter: PixelBufferPainter(canvas.model.state)
            ),
          ),
        ),
      ),
    );
  }
}
