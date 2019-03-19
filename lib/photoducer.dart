import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker_saver/image_picker_saver.dart';
import 'package:photo_view/photo_view.dart';
import 'package:tflite/tflite.dart';

import 'package:photoducer/canvas.dart';
import 'package:photoducer/pixel_buffer.dart';
import 'package:photoducer/photograph_transducer.dart';

class Photoducer extends StatefulWidget {
  final PhotographTransducer transducer = PhotographTransducer();

  @override
  PhotoducerState createState() => PhotoducerState();
}

class PhotoducerState extends State<Photoducer> {
  GlobalKey<PhotoducerCanvasState> canvasKey = GlobalKey();
  bool loadingImage = false;
  String loadedImage, loadedModel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(loadedImage != null ? loadedImage : 'Photoducer'),
        actions: <Widget>[
          IconButton(
            icon: new Icon(Icons.undo),
            tooltip: 'Undo',
            onPressed: () { widget.transducer.walkVersion(-1); }
          ),

          IconButton(
            icon: new Icon(Icons.redo),
            tooltip: 'Redo',
            onPressed: () { widget.transducer.walkVersion(1); }
          ),
        ],
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

              buildToolbar(context), 
            ],
          ),
        ),
      ),
    );
  }

  Widget buildToolbar(BuildContext context) {
    return Container(
      height: 100,
      decoration: BoxDecoration(color: Colors.blueGrey[100]),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: <Widget>[
          PopupMenuButton(
            icon: Icon(Icons.save),
            itemBuilder: (_) => <PopupMenuItem<String>>[
              PopupMenuItem<String>(child: const Text('New'), value: 'new'), // Icons.refresh
              PopupMenuItem<String>(child: const Text('Save'), value: 'save'), // Icons.save
              PopupMenuItem<String>(child: const Text('Load'), value: 'load'), // Icons.open_in_browser
              PopupMenuItem<String>(child: const Text('Stock'), value: 'stock'),
            ],
            onSelected: (String v) {
              if (v == 'new') setState((){
                loadedImage = null;
                widget.transducer.reset();
                //canvasKey.currentState.objectRecognition = null;
              });
              if (v == 'save') saveImage(context);
              if (v == 'load') loadImage(context);
              if (v == 'stock') loadAssetImage(context, 'dogandhorse.jpg');
            }
          ),
    
          PopupMenuButton(
            icon: Icon(Icons.build),
            itemBuilder: (_) => <PopupMenuItem<String>>[
              PopupMenuItem<String>(child: const Text('Hand'), value: 'hand'),
              PopupMenuItem<String>(child: const Text('Draw'), value: 'draw'), // Icons.brush
            ],
            onSelected: (String v) {
              if (v == 'hand') canvasKey.currentState.setTool(PhotoducerCanvasTool.none);
              if (v == 'draw') canvasKey.currentState.setTool(PhotoducerCanvasTool.draw);
            }
          ),
    
          PopupMenuButton(
            icon: Icon(Icons.category),
            itemBuilder: (_) => <PopupMenuItem<String>>[
              PopupMenuItem<String>(child: const Text('Color'), value: 'color'),
              PopupMenuItem<String>(child: const Text('Font'), value: 'font'),
              PopupMenuItem<String>(child: const Text('Brush'), value: 'brush'),
            ],
            onSelected: (String v) {
              if (v == 'color') {
                Color pickerColor = widget.transducer.orthogonalState.paint.color;
                showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Pick a color!'),
                    content: SingleChildScrollView(
                      child: ColorPicker(
                        pickerColor: pickerColor,
                        onColorChanged: (Color x) { pickerColor = x; },
                        enableLabel: true,
                        pickerAreaHeightPercent: 0.8,
                      ),
                    ),
                    actions: <Widget>[
                      FlatButton(
                        child: const Text('Got it'),
                        onPressed: () {
                          setState(() => widget.transducer.changeColor(pickerColor));
                          Navigator.of(context).pop();
                        },
                      ),
                    ],
                  ),
                );
              }
            }
          ),
    
          PopupMenuButton(
            icon: Icon(Icons.art_track),
            itemBuilder: (_) => <PopupMenuItem<String>>[
              PopupMenuItem<String>(child: const Text('Recognize'), value: 'recognize'), // Icons.art_track
              PopupMenuItem<String>(child: const Text('Generate'),  value: 'generate'), // Icons.toys
            ],
            onSelected: (String v) {
              if (v == 'recognize') recognizeImage(context);
              if (v == 'generate') generateImage(context);
            }
          ),

          PopupMenuButton(
            icon: Icon(Icons.border_clear),
            itemBuilder: (_) => <PopupMenuItem<String>>[
              PopupMenuItem<String>(child: const Text('Blur'),        value: 'blur'),
              PopupMenuItem<String>(child: const Text('Edge detect'), value: 'edgeDetect'),
            ],
            onSelected: (String v) {
            }
          ),

          PopupMenuButton(
            icon: Icon(Icons.settings),
            itemBuilder: (_) => <PopupMenuItem<String>>[
              PopupMenuItem<String>(child: const Text('repaint'),    value: 'repaint'),
              PopupMenuItem<String>(child: const Text('paintDelta'), value: 'paintDelta'),
            ],
            onSelected: (String v) {
              if (v == 'repaint')    widget.transducer.updateStateMethod = widget.transducer.updateStateRepaint;
              if (v == 'paintDelta') widget.transducer.updateStateMethod = widget.transducer.updateStatePaintDelta;
            }
          ),

          PopupMenuButton(
            icon: Icon(Icons.share),
            itemBuilder: (_) => <PopupMenuItem<String>>[
              PopupMenuItem<String>(child: const Text('Twitter'),  value: 'twitter'),
              PopupMenuItem<String>(child: const Text('Facebook'), value: 'facebook'),
            ],
            onSelected: (String v) {
            }
          ),
        ],
      ),
    );
  }

  Future<void> voidResult() async {}

  Future<void> loadImageFileNamed(String filename) async {
    List<int> bytes = await File(filename).readAsBytes();
    return loadImageFileBytes(bytes);
  }

  Future<void> loadImageFileBytes(List<int> bytes) async {
    ui.Codec codec = await ui.instantiateImageCodec(bytes);
    ui.FrameInfo frame = await codec.getNextFrame();
    return loadUiImage(frame.image);
  }

  void loadUiImage(ui.Image image) {
    setState((){
      loadingImage = false;
      widget.transducer.reset(image);
      //canvasKey.currentState.objectRecognition = null;
    });
  }

  Future<String> saveImage(BuildContext context) async {
    ui.Image image = await widget.transducer.renderImage();
    var pngBytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return ImagePickerSaver.saveFile(fileData: pngBytes.buffer.asUint8List());
  }

  Future<void> loadImage(BuildContext context) async {
    String filePath = await FilePicker.getFilePath(type: FileType.ANY);
    if (filePath == '') return voidResult();
    setState((){
      loadingImage = true;
      loadedImage = filePath.split(Platform.pathSeparator).last;
    });
    return loadImageFileNamed(filePath);
  }

  Future<void> loadAssetImage(BuildContext context, String name) async {
    setState((){ loadingImage = true; });
    ByteData bytes = await rootBundle.load("assets" + Platform.pathSeparator + name);
    return loadImageFileBytes(bytes.buffer.asUint8List());
  }
  
  Future<String> stashRenderedImage(BuildContext context, String name) async {
    ui.Image image = await widget.transducer.renderImage();
    return stashImage(image, name);
  }

  Future<void> unstashImage(BuildContext context, String name) async {
    String filePath = await stashImagePath(name);
    return loadImageFileNamed(filePath);
  }

  void generateImage(BuildContext context) async {
    var loaded = await loadModel("edges2shoes");
    if (!loaded) return;

    ui.Image input = await widget.transducer.renderImage();
    debugPrint("Running model on frame");

    String filePath = await stashImage(input, "recognize");
    var results = await Tflite.runPix2PixOnImage(
      path: filePath,
      imageMean: 0.0,
      imageStd: 255.0,
    );
    debugPrint("Generated response: " + results[0]['filename']);
    await loadImageFileNamed(results[0]['filename']);

    /*
    img.Image oriImage = await imgFromImage(input);
    img.Image resizedImage = oriImage;
    if (oriImage.width != 256 || oriImage.height != 256)
      resizedImage = img.copyResize(oriImage, 256, 256);

    Float32List floats = imgToFloat32List(resizedImage, 256, 0.0, 255.0);
    var results = await Tflite.runPix2PixOnBinary(
      binary: floats.buffer.asUint8List(),
    );
    Uint8List binary = results[0]['binary'];
    // Otherwise bug where x.asUint8List() == y.asUint8List() but x.asFloat32List() != y.asFloat32List()
    binary = Uint8List.fromList(binary); 

    img.Image genImage = imgFromFloat32List(binary.buffer.asFloat32List(), 256, 0.0, 255.0);
    ui.Image uploadedImage = await imageFromImg(genImage);
    loadUiImage(uploadedImage);
    */
  }

  Future<void> recognizeImage(BuildContext context) async {
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
        model:  "assets" + Platform.pathSeparator + name + ".tflite",
        labels: "assets" + Platform.pathSeparator + name + ".txt",
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
