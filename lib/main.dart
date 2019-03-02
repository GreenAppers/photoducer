import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
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
  List objectRecognition;

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
            Stack(children: <Widget>[
              PhotoducerCanvas(canvasKey),
              Container(
                width: 256,
                height: 256,
                child: Stack(children: objectBoxes(Size(256, 256))),
              ),
            ]),
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

                  FlatButton(
                    child: Icon(Icons.art_track),
                    onPressed: () {
                      setState(() {
                         renderedImage = canvasKey.currentState.rendered;
                      });
                      recognizeImage(context);
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

  Future<ui.Image> imageFromImg(img.Image input) async {
    ui.Codec codec = await ui.instantiateImageCodec(img.encodePng(input));
    ui.FrameInfo frame = await codec.getNextFrame();
    return frame.image;
  }

  Future<img.Image> imgFromImage(ui.Image input) async {
    var pngBytes = await input.toByteData(format: ui.ImageByteFormat.png);
    return img.decodeImage(pngBytes.buffer.asUint8List());
  }

  Future<Null> loadImg(img.Image input) async {
    img.Image resized = img.copyResize(input, 256, 256);
    ui.Image image = await imageFromImg(resized);
    canvasKey.currentState.reset(image);
  }

  Future<String> stashImagePath(String name) async {
    Directory directory = await getApplicationDocumentsDirectory();
    return directory.path + Platform.pathSeparator + name + ".png";
  }

  Future<String> stashImage(ui.Image image, String name) async {
    var pngBytes = await image.toByteData(format: ui.ImageByteFormat.png);
    String path = await stashImagePath(name);
    File(path).writeAsBytesSync(pngBytes.buffer.asInt8List());
    return path;
  }

  Future<String> saveImage(BuildContext context) async {
    var image = await renderedImage;
    var pngBytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return ImagePickerSaver.saveFile(fileData: pngBytes.buffer.asUint8List());
  }

  Future<Null> loadImage(BuildContext context) async {
    //return loadAssetImage(context, 'dogandhorse.jpg');
    String filePath = await FilePicker.getFilePath(type: FileType.ANY);
    return loadImg(img.decodeImage(File(filePath).readAsBytesSync()));
  }

  Future<Null> loadAssetImage(BuildContext context, String name) async {
    ByteData bytes = await rootBundle.load("assets/" + name);
    return loadImg(img.decodeImage(bytes.buffer.asUint8List()));
  }
  
  Future<String> stashRenderedImage(BuildContext context, String name) async {
    var image = await renderedImage;
    return stashImage(image, name);
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
    debugPrint("Running model on frame");

    String filePath = await stashImage(input, "recognize");
    var recognitions = await Tflite.runModelOnImage(
      path: filePath,
      imageMean: 0.0,
      imageStd: 255.0,
      numResults: 1,
    );

    /*
    img.Image resizedImage = await imgFromImage(input);
    var recognitions = await Tflite.runModelOnBinary(
      binary: imgToFloat32List(resizedImage, 256, 0.0, 255.0).buffer.asUint8List(),
      numResults: 1,
    );
    */
  }

  Future<Null> recognizeImage(BuildContext context) async {
    var loaded = await loadModel("yolov2_tiny");
    if (!loaded) return;

    var input = await renderedImage;
    String filePath = await stashImage(input, "recognize");
    var recognitions = await Tflite.detectObjectOnImage(
      path: filePath,
      model: "YOLO",
      threshold: 0.3,
      imageMean: 0.0,
      imageStd: 255.0,
      numResultsPerClass: 1,
    );

    /*
    var input = await renderedImage;
    img.Image oriImage = await imgFromImage(input);
    img.Image resizedImage = img.copyResize(oriImage, 416, 416);
    var recognitions = await Tflite.detectObjectOnBinary(
      binary: imgToFloat32List(resizedImage, 416, 0.0, 255.0).buffer.asUint8List(),
      model: "YOLO",
      threshold: 0.3,
      numResultsPerClass: 1,
    );
    */

    setState(() {
      objectRecognition = recognitions;
    });
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

  Float32List imgToFloat32List(img.Image image, int inputSize, double mean, double std) {
    var convertedBytes = Float32List(1 * inputSize * inputSize * 3);
    var buffer = Float32List.view(convertedBytes.buffer);
    int pixelIndex = 0;
    for (var i = 0; i < inputSize; i++) {
      for (var j = 0; j < inputSize; j++) {
        var pixel = image.getPixel(j, i);
        buffer[pixelIndex++] = (img.getRed  (pixel) - mean) / std;
        buffer[pixelIndex++] = (img.getGreen(pixel) - mean) / std;
        buffer[pixelIndex++] = (img.getBlue (pixel) - mean) / std;
      }
    }
    return convertedBytes;
    
  }

  List<Widget> objectBoxes(Size size) {
    if (objectRecognition == null) return [];
    Color blue = Color.fromRGBO(37, 213, 253, 1.0);
    return objectRecognition.map((re) {
      return Positioned(
        left:   re["rect"]["x"] * size.width,
        top:    re["rect"]["y"] * size.height,
        width:  re["rect"]["w"] * size.width,
        height: re["rect"]["h"] * size.height,
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

class PhotoducerCanvas extends StatefulWidget {
  PhotoducerCanvas(Key key): super(key: key);

  @override
  State<StatefulWidget> createState() {
    return _PhotoducerCanvasState();
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

