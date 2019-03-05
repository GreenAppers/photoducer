import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker_saver/image_picker_saver.dart';
import 'package:photo_view/photo_view.dart';
import 'package:tflite/tflite.dart';
import 'package:photoducer/pixel_buffer.dart';
import 'package:photoducer/photograph_transducer.dart';

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
  final PhotographTransducer transducer = PhotographTransducer();

  @override
  _PhotoducerState createState() => _PhotoducerState();
}

class _PhotoducerState extends State<Photoducer> {
  GlobalKey<_PhotoducerCanvasState> canvasKey = GlobalKey();
  bool loadingImage = false;
  String loadedModel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Photoducer'),
      ),

      body: Container( 
        decoration: BoxDecoration(color: Colors.blueGrey[50]),
        child: IgnorePointer(
          ignoring: loadingImage,
          child: Column(
            children: <Widget>[
              Expanded(
                child: ClipRect(
                  child: (loadingImage ?
                    Center(
                      child: Container(
                        width: 20.0,
                        height: 20.0,
                        child: const CircularProgressIndicator(),
                      ),
                    ) :
                    PhotoView.customChild(
                      child: PhotoducerCanvas(canvasKey, widget.transducer),
                      childSize: widget.transducer.state.size,
                      maxScale: PhotoViewComputedScale.covered * 2.0,
                      minScale: PhotoViewComputedScale.contained * 0.8,
                      initialScale: PhotoViewComputedScale.covered,
                      backgroundDecoration: BoxDecoration(color: Colors.blueGrey[50]),
                    )
                  ),
                ),
              ),
          
              Container(
                height: 100,
                decoration: BoxDecoration(color: Colors.blueGrey[100]),
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: <Widget>[
                    FlatButton(
                      child: Icon(Icons.save),
                      onPressed: () { saveImage(context); },
                    ),
          
                    FlatButton(
                      child: Icon(Icons.open_in_browser),
                      onPressed: () { loadImage(context); },
                    ),
          
                    FlatButton(
                      child: Icon(Icons.refresh),
                      onPressed: () {
                        canvasKey.currentState.reset();
                      },
                    ),
          
                    FlatButton(
                      child: Icon(Icons.toys),
                      onPressed: () { generateImage(context); },
                    ),
          
                    FlatButton(
                      child: Icon(Icons.art_track),
                      onPressed: () { recognizeImage(context); },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<Null> loadImageFileNamed(String filename) async {
    List<int> bytes = await File(filename).readAsBytes();
    return loadImageFileBytes(bytes);
  }

  Future<Null> loadImageFileBytes(List<int> bytes) async {
    ui.Codec codec = await ui.instantiateImageCodec(bytes);
    ui.FrameInfo frame = await codec.getNextFrame();
    canvasKey.currentState.reset(frame.image);
    setState((){ loadingImage = false; });
  }

  Future<String> saveImage(BuildContext context) async {
    ui.Image image = await widget.transducer.renderImage();
    var pngBytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return ImagePickerSaver.saveFile(fileData: pngBytes.buffer.asUint8List());
  }

  Future<Null> loadImage(BuildContext context) async {
    //return loadAssetImage(context, 'dogandhorse.jpg');
    String filePath = await FilePicker.getFilePath(type: FileType.ANY);
    if (filePath == '') return;
    setState((){ loadingImage = true; });
    return loadImageFileNamed(filePath);
  }

  Future<Null> loadAssetImage(BuildContext context, String name) async {
    setState((){ loadingImage = true; });
    ByteData bytes = await rootBundle.load("assets/" + name);
    return loadImageFileBytes(bytes.buffer.asUint8List());
  }
  
  Future<String> stashRenderedImage(BuildContext context, String name) async {
    ui.Image image = await widget.transducer.renderImage();
    return stashImage(image, name);
  }

  Future<Null> unstashImage(BuildContext context, String name) async {
    String filePath = await stashImagePath(name);
    return loadImageFileNamed(filePath);
  }

  Future<Null> generateImage(BuildContext context) async {
    var loaded = await loadModel("edges2shoes");
    if (!loaded) return;

    ui.Image input = await widget.transducer.renderImage();
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

    ui.Image input = await widget.transducer.renderImage();
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
    ui.Image input = await widget.transducer.renderImage();
    img.Image oriImage = await imgFromImage(input);
    img.Image resizedImage = img.copyResize(oriImage, 416, 416);
    var recognitions = await Tflite.detectObjectOnBinary(
      binary: imgToFloat32List(resizedImage, 416, 0.0, 255.0).buffer.asUint8List(),
      model: "YOLO",
      threshold: 0.3,
      numResultsPerClass: 1,
    );
    */

    canvasKey.currentState.setObjectRecognition(recognitions);
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

enum PhotoducerCanvasTool { none, draw }

class PhotoducerCanvas extends StatefulWidget {
  final PhotographTransducer transducer;
  PhotoducerCanvas(Key key, this.transducer): super(key: key);

  @override
  State<StatefulWidget> createState() {
    return _PhotoducerCanvasState();
  }
}

class _PhotoducerCanvasState extends State<PhotoducerCanvas> {
  PhotoducerCanvasTool tool = PhotoducerCanvasTool.draw;
  List objectRecognition;

  void reset([ui.Image image]) {
    setState(() {
      widget.transducer.reset(image);
      objectRecognition = null;
    });
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
              child: CustomPaint(
                painter: PhotographTransducerPainter(widget.transducer),
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
              setState(() {
                widget.transducer.addLines(point);
              });
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
