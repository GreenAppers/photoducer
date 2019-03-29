import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_crashlytics/flutter_crashlytics.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:image/src/filter/emboss.dart';
import 'package:image/src/filter/gaussian_blur.dart';
import 'package:image/src/filter/grayscale.dart';
import 'package:image/src/filter/sepia.dart';
import 'package:image/src/filter/sobel.dart';
import 'package:image/src/filter/vignette.dart';
import 'package:image_picker_saver/image_picker_saver.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tflite/tflite.dart';

import 'package:photoducer/persistent_canvas.dart';
import 'package:photoducer/photoducer.dart';
import 'package:photoducer/photograph_transducer.dart';

void main() async {
  bool inDebugMode = false;
  assert(inDebugMode = true);
  debugPrint('Photoducer main() inDebugMode=' + inDebugMode.toString());

  FlutterError.onError = (FlutterErrorDetails details) {
    if (inDebugMode) FlutterError.dumpErrorToConsole(details);
    else Zone.current.handleUncaughtError(details.exception, details.stack);
  };

  await FlutterCrashlytics().initialize();

  runZoned<Future<void>>(
    () async {
      runApp(MaterialApp(
        title: 'Photoducer',
        theme: ThemeData(
          primarySwatch: Colors.blue,
        ),
        home: _PhotoducerApp()
      ));
    }, onError: (error, stackTrace) async {
      await FlutterCrashlytics().reportCrash(error, stackTrace, forceCrash: false);
    }
  );
}

class _PhotoducerApp extends StatefulWidget {
  @override
  _PhotoducerAppState createState() => _PhotoducerAppState();
}

class _PhotoducerAppState extends State<_PhotoducerApp> {
  final PersistentCanvas persistentCanvas = PersistentCanvas();
  final PhotoducerModel photoducerState = PhotoducerModel();
  String loadedImage, loadedModel;
  bool loadingImage = false;

  PhotographTransducer model() { return persistentCanvas.model; }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(loadedImage != null ? loadedImage : 'Photoducer'),
        actions: <Widget>[
          IconButton(
            icon: new Icon(Icons.undo),
            tooltip: 'Undo',
            onPressed: () { model().walkVersion(-1); }
          ),

          IconButton(
            icon: new Icon(Icons.redo),
            tooltip: 'Redo',
            onPressed: () { model().walkVersion(1); }
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
                    Photoducer(photoducerState, persistentCanvas)
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

  Widget buildToolbar(BuildContext c) {
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
              if      (v == 'new') { loadedImage=null; loadUiImage(null); }
              else if (v == 'save') saveImage(context);
              else if (v == 'load') loadImage(context);
              else if (v == 'stock') loadAssetImage(context, 'dogandhorse.jpg');
            }
          ),

          PopupMenuButton(
            icon: Icon(Icons.build),
            itemBuilder: (_) => <PopupMenuItem<String>>[
              PopupMenuItem<String>(child: const Text('Hand'), value: 'hand'),
              PopupMenuItem<String>(child: const Text('Draw'), value: 'draw'), // Icons.brush
            ],
            onSelected: (String v) {
              switch (v) {
                case 'hand':
                  photoducerState.setTool(PhotoducerTool.none);
                  break;

                case 'draw':
                  photoducerState.setTool(PhotoducerTool.draw);
                  break;
              }
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
                Color pickerColor = model().orthogonalState.paint.color;
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
                          model().addChangeColor(pickerColor);
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
              PopupMenuItem<String>(child: const Text('Emboss'),      value: 'emboss'),
              PopupMenuItem<String>(child: const Text('Vignette'),    value: 'vignette'),
              PopupMenuItem<String>(child: const Text('Sepia'),       value: 'sepia'),
              PopupMenuItem<String>(child: const Text('Grayscale'),   value: 'grayscale'),
            ],
            onSelected: (String v) {
              switch (v) {
                case 'blur':
                  model().addDownloadedTransform((img.Image x) => gaussianBlur(x, 10));
                  break;

                case 'edgeDetect':
                  model().addDownloadedTransform((img.Image x) => sobel(x));
                  break;

                case 'emboss':
                  model().addDownloadedTransform((img.Image x) => emboss(x));
                  break;

                case 'vignette':
                  model().addDownloadedTransform((img.Image x) => vignette(x));
                  break;

                case 'sepia':
                  model().addDownloadedTransform((img.Image x) => sepia(x));
                  break;

                case 'grayscale':
                  model().addDownloadedTransform((img.Image x) => grayscale(x));
                  break;
              }
            }
          ),

          PopupMenuButton(
            icon: Icon(Icons.settings),
            itemBuilder: (_) => <PopupMenuItem<String>>[
              PopupMenuItem<String>(child: const Text('repaint'),    value: 'repaint'),
              PopupMenuItem<String>(child: const Text('paintDelta'), value: 'paintDelta'),
            ],
            onSelected: (String v) {
              if (v == 'repaint')    model().updateStateMethod = model().updateStateRepaint;
              if (v == 'paintDelta') model().updateStateMethod = model().updateStatePaintDelta;
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

  Future<void> loadImage(BuildContext context) async {
    String filePath = await FilePicker.getFilePath(type: FileType.IMAGE);
    if (filePath == '') return voidResult();
    setState((){
      loadingImage = true;
      loadedImage = filePath.split(Platform.pathSeparator).last;
    });
    return loadImageFileNamed(filePath);
  }

  Future<void> loadAssetImage(BuildContext context, String name) async {
    setState((){
      loadingImage = true;
      loadedImage = name;
    });
    ByteData bytes = await rootBundle.load("assets" + Platform.pathSeparator + name);
    return loadImageFileBytes(bytes.buffer.asUint8List());
  }

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
    setState((){ loadingImage = false; });
    photoducerState.reset();
    model().reset(image);
  }

  Future<String> saveImage(BuildContext context) async {
    ui.Image image = await model().state.uploaded;
    var pngBytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return ImagePickerSaver.saveFile(fileData: pngBytes.buffer.asUint8List());
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

  Future<String> stashRenderedImage(BuildContext context, String name) async {
    ui.Image image = await model().state.uploaded;
    return stashImage(image, name);
  }

  Future<void> unstashImage(BuildContext context, String name) async {
    String filePath = await stashImagePath(name);
    return loadImageFileNamed(filePath);
  }

  void generateImage(BuildContext context) async {
    var loaded = await loadModel("contours2cats");
    if (!loaded) return;

    ui.Image input = await model().state.uploaded;
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

    ui.Image input = await model().state.uploaded;
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
    ui.Image input = await model().state.uploaded;
    img.Image oriImage = await imgFromImage(input);
    img.Image resizedImage = img.copyResize(oriImage, 416, 416);
    var recognitions = await Tflite.detectObjectOnBinary(
      binary: imgToFloat32List(resizedImage, 416, 0.0, 255.0).buffer.asUint8List(),
      model: "YOLO",
      threshold: 0.3,
      numResultsPerClass: 1,
    );
    */

    photoducerState.setObjectRecognition(recognitions);
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
