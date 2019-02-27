import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:simple_permissions/simple_permissions.dart';
import 'package:tflite/tflite.dart';

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
  String loadedModel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Photoducer'),
      ),

      body: Container( 
        decoration: new BoxDecoration(color: Colors.blueGrey[50]),
        child: Column(
          children: <Widget>[
            Spacer(),
            PhotoducerCanvas(canvasKey),
            Spacer(),
        
            Container(
              height: 100,
              decoration: new BoxDecoration(color: Colors.blueGrey[100]),
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
        
                  FlatButton(
                    child: Icon(Icons.toys),
                    onPressed: () {
                      setState(() {
                         renderedImage = canvasKey.currentState.rendered;
                      });
                      generateImage(context);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
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
    var image = await renderedImage;
    var pngBytes = await image.toByteData(format: ui.ImageByteFormat.png);
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
  
  Future<Null> generateImage(BuildContext context) async {
    await loadModel("edges2shoes");
    var image = await renderedImage;
    var rgbaBytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    var recognitions = await Tflite.runModelOnBinary(
      binary: rgbaBytes.buffer.asUint8List(),
      numResults: 1,
    );
  }

  Future loadModel(name) async {
    if (loadedModel == name) return;
    try {
      String res;
      res = await Tflite.loadModel(model: "assets/" + name + ".tflite");
      loadedModel = name;
      debugPrint(res);
    } on PlatformException {
      debugPrint('Failed to load model.');
    }
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
      points = <Offset>[];
      backgroundImage = null;
    });
  }

  void setBackgroundImage(ui.Image image) {
    setState(() {
      points = <Offset>[];
      backgroundImage = image;
    });
  }

  Future<ui.Image> get rendered async {
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
      width: 256,
      height: 256,

      child: GestureDetector(
        onPanUpdate: (DragUpdateDetails details) {
          setState(() {
            RenderBox box = context.findRenderObject();
            Offset point = box.globalToLocal(details.globalPosition);
            if (point.dx >=0 && point.dy >= 0 && point.dx < box.size.width && point.dy < box.size.height)
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
          color: Colors.white,
          child: CustomPaint(
            painter: PhotoducerCanvasPainter(backgroundImage, points),
          ),
        ),
      ),
    );
  }
}

class PhotoducerCanvasPainter extends CustomPainter {
  ui.Image backgroundImage;
  List<Offset> points;

  PhotoducerCanvasPainter(this.backgroundImage, this.points);

  @override
  bool shouldRepaint(PhotoducerCanvasPainter oldDelegate) {
    return oldDelegate.points != points;
  }

  void paint(Canvas canvas, Size size) {
    Paint paint = Paint()
      ..color = Colors.black
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.0;

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
