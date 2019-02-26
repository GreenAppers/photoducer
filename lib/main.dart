import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:simple_permissions/simple_permissions.dart';

const directoryName = 'Photoducer';

void main() => runApp(PhotoducerApp());

class PhotoducerApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Photoducer',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: Photoducer(),
    );
  }
}

class Photoducer extends StatefulWidget {
  @override
  _PhotoducerState createState() => _PhotoducerState();
}

class _PhotoducerState extends State<Photoducer> {
  GlobalKey<_PhotoducerCanvasState> canvasKey = GlobalKey();
  Permission readPermission = Permission.ReadExternalStorage;
  Permission writePermission = Permission.WriteExternalStorage;
  var renderedImage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Photoducer'),
      ),

      body: Column(
        children: <Widget>[
          Expanded(
            child: PhotoducerCanvas(canvasKey),
          ),
          Container(
            height: 100,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: <Widget>[
                FlatButton(
                  child: Icon(Icons.save),
                  onPressed: () { 
                    setState(() {
                       renderedImage = canvasKey.currentState.rendered;
                    });
                    saveImage(context);
                  },
                ),

                FlatButton(
                  child: Icon(Icons.open_in_browser),
                  onPressed: () { 
                    loadImage(context);
                  },
                ),

                FlatButton(
                  child: Icon(Icons.refresh),
                  onPressed: () {
                    canvasKey.currentState.clear();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<Null> loadImage(BuildContext context) async {
    if(!(await checkPermission(readPermission))) await requestPermission(readPermission);
    Directory directory = await getExternalStorageDirectory();
    String path = directory.path;
    ui.Codec codec = await ui.instantiateImageCodec(File('$path/$directoryName/photo.png').readAsBytesSync());
    ui.FrameInfo frame = await codec.getNextFrame();
    canvasKey.currentState.setBackgroundImage(frame.image);
  }

  Future<Null> saveImage(BuildContext context) async {
    var pngBytes = await renderedImage.toByteData(format: ui.ImageByteFormat.png);
    if(!(await checkPermission(writePermission))) await requestPermission(writePermission);
    Directory directory = await getExternalStorageDirectory();
    String path = directory.path;
    debugPrint('Creating ' + path + '/' + directoryName);
    await Directory('$path/$directoryName').create(recursive: true);
    File('$path/$directoryName/photo.png').writeAsBytesSync(pngBytes.buffer.asInt8List());
  }

  requestPermission(permission) async {
    PermissionStatus status = await SimplePermissions.requestPermission(permission);
    return status == PermissionStatus.authorized;
  }

  checkPermission(permission) async {
    bool result = await SimplePermissions.checkPermission(permission);
    return result;
  }
}

class PhotoducerCanvas extends StatefulWidget {
  PhotoducerCanvas(Key key): super(key: key);

  @override
  State<StatefulWidget> createState() {
    return _PhotoducerCanvasState();
  }
}

class _PhotoducerCanvasState extends State<PhotoducerCanvas> {
  ui.Image backgroundImage;
  List<Offset> points = <Offset>[];

  void clear() {
    setState(() {
      points.clear();
      backgroundImage = null;
    });
  }

  void setBackgroundImage(ui.Image image) {
    setState(() {
      points.clear();
      backgroundImage = image;
    });
  }

  ui.Image get rendered {
    ui.PictureRecorder recorder = ui.PictureRecorder();
    Canvas canvas = Canvas(recorder);
    PhotoducerCanvasPainter painter = PhotoducerCanvasPainter(backgroundImage, points);
    var size = context.size;
    painter.paint(canvas, size);
    return recorder.endRecording().toImage(size.width.floor(), size.height.floor());
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.all(1.0),
      child: GestureDetector(
        onPanUpdate: (DragUpdateDetails details) {
          setState(() {
            RenderBox box = context.findRenderObject();
            Offset point = box.globalToLocal(details.globalPosition);
            if (point.dy < box.size.height)
              points = List.from(points)..add(point);
          });
        },

        onPanEnd: (DragEndDetails details) {
          setState(() {
            points.add(null);
          });
        },

        child: Container(
          alignment: Alignment.topLeft,
          color: Colors.blueGrey[50],
          child: CustomPaint(
            painter: PhotoducerCanvasPainter(backgroundImage, points),
          ),
        ),
      ),
    );
  }
}

class PhotoducerCanvasPainter extends CustomPainter {
  final ui.Image backgroundImage;
  final List<Offset> points;

  PhotoducerCanvasPainter(this.backgroundImage, this.points);

  @override
  bool shouldRepaint(PhotoducerCanvasPainter oldDelegate) {
    return oldDelegate.points != points;
  }

  void paint(Canvas canvas, Size size) {
    Paint paint = Paint()
      ..color = Colors.black
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4.0;

    if (backgroundImage != null) {
      canvas.drawImage(backgroundImage, Offset(0, 0), paint);
    }

    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != null && points[i + 1] != null) {
        canvas.drawLine(points[i], points[i + 1], paint);
      }
    }
  }
}
