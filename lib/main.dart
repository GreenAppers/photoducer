import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:busy_model/busy_model.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_crashlytics/flutter_crashlytics.dart';
import 'package:flutter_native_image/flutter_native_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker_saver/image_picker_saver.dart';
import 'package:path_provider/path_provider.dart';
import 'package:persistent_canvas/pixel_buffer.dart';
import 'package:persistent_canvas/persistent_canvas.dart';
import 'package:persistent_canvas/photograph_transducer.dart';
import 'package:tflite/tflite.dart';

import 'package:photoducer/photoducer.dart';

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
        home: PhotoducerApp()
      ));
    }, onError: (error, stackTrace) async {
      await FlutterCrashlytics().reportCrash(error, stackTrace, forceCrash: false);
    }
  );
}

class PhotoducerApp extends StatefulWidget {
  @override
  _PhotoducerAppState createState() => _PhotoducerAppState();
}

class _PhotoducerAppState extends State<PhotoducerApp> {
  final PersistentCanvas persistentCanvas = PersistentCanvas(busy: BusyModel());
  final PhotoducerModel photoducerState = PhotoducerModel();
  String loadedImage, loadedModel;
  Size loadedImageSize, scaledImageSize;

  PhotographTransducer get model => persistentCanvas.model;

  @override
  Widget build(BuildContext context) {
    List<Widget> column = <Widget>[];
    column.add(
      Expanded(
        child: ClipRect(
          child: Photoducer(photoducerState, persistentCanvas)
        ),
      ),
    );
    column.add(buildToolbar(context));

    return Scaffold(
      appBar: AppBar(
        title: Text(loadedImage != null ? loadedImage.split(Platform.pathSeparator).last : 'Photoducer'),
        actions: <Widget>[
          IconButton(
            icon: new Icon(Icons.undo),
            tooltip: 'Undo',
            onPressed: () { model.walkVersion(-1); }
          ),

          IconButton(
            icon: new Icon(Icons.redo),
            tooltip: 'Redo',
            onPressed: () { model.walkVersion(1); }
          ),
        ],
      ),

      body: BusyScope(
        model: model.busy,
        child: Container(
          decoration: BoxDecoration(color: Colors.blueGrey[50]),
          child: Column(
            children: column,
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
              PopupMenuItem<String>(child: Row(children: <Widget>[ Icon(Icons.refresh), Text('New') ]), value: 'new'), // Icons.refresh
              PopupMenuItem<String>(child: const Text('Save'), value: 'save'), // Icons.save
              PopupMenuItem<String>(child: const Text('Load'), value: 'load'), // Icons.open_in_browser
              PopupMenuItem<String>(child: const Text('Stock'), value: 'stock'),
            ],
            onSelected: (String v) {
              if      (v == 'new') newImage(context);
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
              PopupMenuItem<String>(child: const Text('Select Box'), value: 'selectBox'), // Icons.brush
            ],
            onSelected: (String v) {
              switch (v) {
                case 'hand':
                  photoducerState.setTool(PhotoducerTool.none);
                  break;

                case 'draw':
                  photoducerState.setTool(PhotoducerTool.draw);
                  break;

                case 'selectBox':
                  photoducerState.setTool(PhotoducerTool.selectBox);
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
                Color pickerColor = model.orthogonalState.paint.color;
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
                          model.changeColor(pickerColor);
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
            icon: Icon(Icons.crop_free),
            itemBuilder: (_) => <PopupMenuItem<String>>[
              PopupMenuItem<String>(child: const Text('Cut'), value: 'cut'),
              PopupMenuItem<String>(child: const Text('Crop'), value: 'crop'),
              PopupMenuItem<String>(child: const Text('Fill'), value: 'fill'),
            ],
            onSelected: (String v) {
              if (photoducerState.selectBox == null) return;
              switch (v) {
                case 'crop':
                  model.addCrop(photoducerState.selectBox);
                  break;
              }
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
                  model.addDownloadedTransform((img.Image x) => img.gaussianBlur(x, 10));
                  break;

                case 'edgeDetect':
                  model.addDownloadedTransform((img.Image x) => img.sobel(x));
                  break;

                case 'emboss':
                  model.addDownloadedTransform((img.Image x) => img.emboss(x));
                  break;

                case 'vignette':
                  model.addDownloadedTransform((img.Image x) => img.vignette(x));
                  break;

                case 'sepia':
                  model.addDownloadedTransform((img.Image x) => img.sepia(x));
                  break;

                case 'grayscale':
                  model.addDownloadedTransform((img.Image x) => img.grayscale(x));
                  break;
              }
            }
          ),

          PopupMenuButton(
            icon: Icon(Icons.art_track),
            itemBuilder: (_) => <PopupMenuItem<String>>[
              PopupMenuItem<String>(child: const Text('Recognize'), value: 'recognize'), // Icons.art_track
              PopupMenuItem<String>(child: const Text('Generate Cat'), value: 'generate_cat'), // Icons.toys
              PopupMenuItem<String>(child: const Text('Generate Shoe'), value: 'generate_shoe'), // Icons.toys
            ],
            onSelected: (String v) {
              if (v == 'recognize') recognizeImage(context);
              if (v == 'generate_cat') generateImage(context, 'contours2cats');
              if (v == 'generate_shoe') generateImage(context, 'edges2shoes');
            }
          ),

          PopupMenuButton(
            icon: Icon(Icons.settings),
            itemBuilder: (_) => <PopupMenuItem<String>>[
              PopupMenuItem<String>(child: const Text('repaint'),    value: 'repaint'),
              PopupMenuItem<String>(child: const Text('paintDelta'), value: 'paintDelta'),
            ],
            onSelected: (String v) {
              if (v == 'repaint')    model.updateUploadedStateMethod = model.updateUploadedStateRepaint;
              if (v == 'paintDelta') model.updateUploadedStateMethod = model.updateUploadedStatePaintDelta;
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

  Future<void> newImage(BuildContext context) async {
    scaledImageSize = null;
    loadedImage = null;
    loadUiImage(null);
  }

  Future<void> loadImage(BuildContext context) async {
    String filePath = await FilePicker.getFilePath(type: FileType.IMAGE);
    if (filePath == '') return voidResult();
    setState((){
      scaledImageSize = null;
      loadedImage = filePath;
      model.busy.setBusy('Loading ' + loadedImage);
    });
    ui.Image image = await loadImageFileNamed(filePath);
    loadUiImage(image);
  }

  Future<void> loadAssetImage(BuildContext context, String name) async {
    setState((){
      loadedImage = name;
      scaledImageSize = null;
      model.busy.setBusy('Loading ' + loadedImage);
    });
    ByteData bytes = await rootBundle.load("assets" + Platform.pathSeparator + name);
    ui.Image image = await loadImageFileBytes(bytes.buffer.asUint8List());
    loadUiImage(image);
  }

  Future<ui.Image> loadImageFileNamed(String filename, {downscale=true}) async {
    ImageProperties properties = await FlutterNativeImage.getImageProperties(filename);
    debugPrint('loadImageFileNamed ' + filename + ' ' + properties.width.toString() + ' x ' + properties.height.toString());
    loadedImageSize = Size(properties.width * 1.0, properties.height * 1.0);

    File file;
    if (downscale && (properties.width > 600 || properties.height > 600)) {
      scaledImageSize = Size(600.0, properties.height * 600 / properties.width);
      file = await FlutterNativeImage.compressImage(filename,
        quality: 80, 
        targetWidth: scaledImageSize.width.round(),
        targetHeight: scaledImageSize.height.round(),
      );
    } else {
      file = File(filename);
    }

    List<int> bytes = await file.readAsBytes();
    return loadImageFileBytes(bytes);
  }

  Future<ui.Image> loadImageFileBytes(List<int> bytes) async {
    ui.Codec codec = await ui.instantiateImageCodec(bytes);
    ui.FrameInfo frame = await codec.getNextFrame();
    return frame.image;
  }

  void loadUiImage(ui.Image image) {
    model.reset(image);
    photoducerState.reset();
    model.busy.reset();
    setState((){});
  }

  Future<String> saveImage(BuildContext context) async {
    ui.Image image = model.state.uploaded;
    if (scaledImageSize != null) {
      model.busy.setBusy('Rendering at full resolution');
      PhotographTransducer fullResTransducer = PhotographTransducer();
      fullResTransducer.reset(await loadImageFileNamed(loadedImage, downscale: false));
      fullResTransducer.addList(model.input, startIndex: 1);
      image = await fullResTransducer.getRenderedImage();
    }
    model.busy.setBusy('Saving');
    var pngBytes = await image.toByteData(format: ui.ImageByteFormat.png);
    String filename = await ImagePickerSaver.saveFile(fileData: pngBytes.buffer.asUint8List());
    model.busy.reset();
    return filename;
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
    ui.Image image = model.state.uploaded;
    return stashImage(image, name);
  }

  Future<ui.Image> unstashImage(BuildContext context, String name) async {
    String filePath = await stashImagePath(name);
    return loadImageFileNamed(filePath);
  }

  void generateImage(BuildContext context, String modelName) async {
    model.busy.setBusy('Generating');
    var loaded = await loadModel(modelName);
    if (!loaded) return;

    ui.Image input = model.state.uploaded;
    debugPrint("Running model on frame");

    String filePath = await stashImage(input, "recognize");
    var result = await Tflite.runPix2PixOnImage(
      path: filePath,
      imageMean: 0.0,
      imageStd: 255.0,
    );
    ui.Image uploadedImage = await loadImageFileBytes(result);

    /*
    img.Image oriImage = await imgFromImage(input);
    img.Image resizedImage = oriImage;
    if (oriImage.width != 256 || oriImage.height != 256)
      resizedImage = img.copyResize(oriImage, 256, 256);
    
    Float32List floats = imgToFloat32List(resizedImage, 256, 0.0, 255.0);
    var result = await Tflite.runPix2PixOnBinary(
      binary: floats.buffer.asUint8List(),
    );

    // Otherwise bug where x.asUint8List() == y.asUint8List() but x.asFloat32List() != y.asFloat32List()
    var binary = Uint8List.fromList(result); 
    
    img.Image genImage = imgFromFloat32List(binary.buffer.asFloat32List(), 256, 0.0, 255.0);
    ui.Image uploadedImage = await imageFromImg(genImage);
    */

    model.busy.reset();
    model.addRedraw(uploadedImage);
  }

  Future<void> recognizeImage(BuildContext context) async {
    model.busy.setBusy('Recognizing');
    var loaded = await loadModel("yolov2_tiny");
    if (!loaded) return;

    ui.Image input = model.state.uploaded;
    String filePath = await stashImage(input, "recognize");
    var recognitions = await Tflite.detectObjectOnImage(
      path: filePath,
      model: "YOLO",
      threshold: 0.3,
      imageMean: 0.0,
      imageStd: 255.0,
      numResultsPerClass: 1,
    );

    model.busy.reset();
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
