import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker_saver/image_picker_saver.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tflite/tflite.dart';
import 'package:tuple/tuple.dart';

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
                      canvasKey.currentState.reset();
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
  
  Future<String> saveImage(BuildContext context) async {
    var image = await renderedImage;
    var pngBytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return ImagePickerSaver.saveFile(fileData: pngBytes.buffer.asUint8List());
  }

  Future<Null> loadImage(BuildContext context) async {
    String filePath = await FilePicker.getFilePath(type: FileType.ANY);
    ui.Codec codec = await ui.instantiateImageCodec(File(filePath).readAsBytesSync());
    ui.FrameInfo frame = await codec.getNextFrame();
    canvasKey.currentState.reset(frame.image);
  }

  Future<Null> stashImage(BuildContext context, String name) async {
    var image = await renderedImage;
    var pngBytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory directory = await getApplicationDocumentsDirectory();
    String path = directory.path;
    File('$path/$name.png').writeAsBytesSync(pngBytes.buffer.asInt8List());
  }

  Future<Null> unstashImage(BuildContext context, String name) async {
    Directory directory = await getApplicationDocumentsDirectory();
    String path = directory.path;
    ui.Codec codec = await ui.instantiateImageCodec(File('$path/$name.png').readAsBytesSync());
    ui.FrameInfo frame = await codec.getNextFrame();
    canvasKey.currentState.reset(frame.image);
  }

  Future<Null> generateImage(BuildContext context) async {
    var loaded = await loadModel("edges2shoes");
    if (!loaded) return;
    var input = await renderedImage;
    var rgbaBytes = await input.toByteData(format: ui.ImageByteFormat.rawRgba);
    List<Uint8List> planes = [
      new Uint8List(input.width * input.height),
      new Uint8List(input.width * input.height),
      new Uint8List(input.width * input.height),
      new Uint8List(input.width * input.height),
    ];
    rgbaBytes.buffer.asUint8List().asMap().forEach((i, v) => { planes[i%4][i~/4] = v });
    planes.removeAt(0);

    debugPrint("Running model on frame");
    var recognitions = await Tflite.runModelOnFrame(
      bytesList: planes,
      imageHeight: input.height,
      imageWidth: input.width,
      numResults: 1,
    );
  }

  Future<bool> loadModel(name) async {
    if (loadedModel == name) return true;
    try {
      String res;
      res = await Tflite.loadModel(
        model:  "assets/" + name + ".tflite",
        labels: "assets/" + name + ".txt",
      );
      loadedModel = name;
      debugPrint('loadModel: ' + res);
      return true;
    } on PlatformException {
      debugPrint('Failed to load model.');
      return false;
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

enum Input { reset, nop, color, strokeCap, strokeWidth, lines }

class PhotographTransducer {
  List<MapEntry<Input, Object>> input = <MapEntry<Input, Object>>[];
  int version = 1;

  void reset(ui.Image image) {
    version = 1;
    input = <MapEntry<Input, Object>>[];
    if (image != null) input.add(MapEntry<Input, Object>(Input.reset, image));
  }

  void addOrUpdateLastInput(Input type) {
    if (input.length == 0 || input.last.key != type) {
      switch (type) {
        case Input.nop:
          input.add(MapEntry<Input, Object>(type, null));
          break;

        case Input.lines:
          input.add(MapEntry<Input, Object>(type, List<Offset>()));
          break;

        default:
          assert(false, "addOrUpdateLastInput(" + type.toString() + "): unsupported");
      }
      version++;
    }
  }

  void addLines(Offset point) {
    addOrUpdateLastInput(Input.lines);
    List<Offset> points = input.last.value;
    points.add(point);
    version++;
  }

  int transduce(Canvas canvas, Size size) {
    Paint paint = Paint()
      ..color = Colors.black
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.0;

    for (MapEntry<Input, Object> x in input) {
      switch (x.key) {
        case Input.reset:
          canvas.drawImage(x.value, Offset(0, 0), paint);
          break;

        case Input.color:
          paint.color = x.value;
          break;

        case Input.strokeCap:
          paint.strokeCap = x.value;
          break;

        case Input.strokeWidth:
          paint.strokeWidth = x.value;
          break;

        case Input.lines:
          List<Offset> points = x.value;
          for (int i = 0; i < points.length - 1; i++) {
            canvas.drawLine(points[i], points[i + 1], paint);
          }
          break;

        default:
          break;
      }
    }
    return version;
  }
}

class _PhotoducerCanvasState extends State<PhotoducerCanvas> {
  PhotographTransducer transducer = new PhotographTransducer();

  void reset([ui.Image image]) {
    setState(() { transducer.reset(image); });
  }

  Future<ui.Image> get rendered async {
    ui.PictureRecorder recorder = ui.PictureRecorder();
    Canvas canvas = Canvas(recorder);
    PhotoducerCanvasPainter painter = PhotoducerCanvasPainter(transducer);
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
          RenderBox box = context.findRenderObject();
          Offset point = box.globalToLocal(details.globalPosition);
          if (point.dx >=0 && point.dy >= 0 && point.dx < box.size.width && point.dy < box.size.height) {
            setState(() {
              transducer.addLines(point);
            });
          }
        },

        onPanEnd: (DragEndDetails details) {
          setState(() {
            transducer.addOrUpdateLastInput(Input.nop);
          });
        },

        child: Container(
          alignment: Alignment.topLeft,
          color: Colors.white,
          child: CustomPaint(
            painter: PhotoducerCanvasPainter(transducer),
          ),
        ),
      ),
    );
  }
}

class PhotoducerCanvasPainter extends CustomPainter {
  PhotographTransducer transducer;
  int transducerVersion = 0;

  PhotoducerCanvasPainter(this.transducer);

  @override
  bool shouldRepaint(PhotoducerCanvasPainter oldDelegate) {
    return transducerVersion != oldDelegate.transducerVersion;
  }

  void paint(Canvas canvas, Size size) {
    transducerVersion = transducer.transduce(canvas, size);
  }
}

