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
import 'package:gradient_picker/gradient_picker.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker_saver/image_picker_saver.dart';
import 'package:path_provider/path_provider.dart';
import 'package:persistent_canvas/pixel_buffer.dart';
import 'package:persistent_canvas/persistent_canvas.dart';
import 'package:persistent_canvas/photograph_transducer.dart';
import 'package:potrace/potrace.dart';
import 'package:scoped_model/scoped_model.dart';
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
      BusyModel busy = BusyModel();
      runApp(
        MaterialApp(
          title: 'Photoducer',
          theme: ThemeData(
            primarySwatch: Colors.green,
          ),
          home: BusyScope(
            model: busy,
            child: PhotoducerApp(busy),
          ),
        )
      );
    }, onError: (error, stackTrace) async {
      await FlutterCrashlytics().reportCrash(error, stackTrace, forceCrash: false);
    }
  );
}

/// Top level [Widget] state is already lifted up - no [Model] needed.
class PhotoducerApp extends StatefulWidget {
  final BusyModel busy;
  PhotoducerApp(this.busy);

  @override
  _PhotoducerAppState createState() => _PhotoducerAppState(busy);
}

/// Workspace overlay layer
class _PhotoducerAppState extends State<PhotoducerApp> {
  final PersistentCanvasLayers layers;
  final PhotoducerModel photoducerState = PhotoducerModel();
  bool showLayersView = false, showToolbar = true;
  String loadedImage, loadedModel;
  Size loadedImageSize, scaledImageSize;

  _PhotoducerAppState(BusyModel busy) :
    layers=PersistentCanvasLayers(
      coordinates: PersistentCanvasCoordinates.normalize,
      busy: busy
    );

  PhotographTransducer get model => layers.canvas.model;

  @override
  Widget build(BuildContext context) {
    ScopedModel.of<BusyModel>(context, rebuildOnChange: true);

    List<Widget> column = <Widget>[];
    column.add(
      Expanded(
        child: ClipRect(
          child: PaintView(photoducerState, layers)
        ),
      ),
    );
    if (showLayersView) 
      column.add(LayersView(photoducerState, layers));
    if (showToolbar) 
      column.add(buildToolbar(context));

    return Scaffold(
      appBar: AppBar(
        title: Text(loadedImage != null ? loadedImage.split(Platform.pathSeparator).last : 'Photoducer'),
        actions: <Widget>[
          Container(
            child: IconButton(
              icon: Icon(
                PhotoducerModel.getToolIconData(photoducerState.tool),
                color: model.orthogonalState.paint.color,
              ),
              tooltip: 'Color',
              onPressed: pickColor,
            ),
            color: model.orthogonalState.backgroundColor,
            margin: EdgeInsets.all(10.0),
          ),

          IconButton(
            icon: Icon(Icons.undo),
            tooltip: 'Undo',
            onPressed: () { model.walkVersion(-1); photoducerState.reset(); }
          ),

          IconButton(
            icon: Icon(Icons.redo),
            tooltip: 'Redo',
            onPressed: () { model.walkVersion(1); photoducerState.reset(); }
          ),

          (PopupMenuBuilder(icon: Icon(Icons.menu))
            ..addItem(
              icon: Icon(showLayersView ? Icons.check_box : Icons.check_box_outline_blank),
              text: 'Layers', onSelected: (){ setState((){ showLayersView = !showLayersView; }); }
            )
            ..addItem(
              icon: Icon(showToolbar ? Icons.check_box : Icons.check_box_outline_blank),
              text: 'Toolbar', onSelected: (){ setState((){ showToolbar = !showToolbar; }); }
            )
          ).build(),
        ],
      ),

      body: ScopedModel<PhotoducerModel>(
        model: photoducerState,
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
    List<Widget> toolbar = <Widget>[
      (PopupMenuBuilder(icon: Icon(Icons.save))
        ..addItem(icon: Icon(Icons.refresh),         text: 'New',    onSelected: newImage)
        ..addItem(icon: Icon(Icons.save),            text: 'Save',   onSelected: saveImage)
        ..addItem(icon: Icon(Icons.screen_share),    text: 'Export', onSelected: exportSVG)
        ..addItem(icon: Icon(Icons.open_in_browser), text: 'Load',   onSelected: pickImage)
        ..addItem(icon: Icon(Icons.photo_library),   text: 'Stock',  onSelected: pickStockImage)
      ).build(),

      (PopupMenuBuilder(icon: Icon(Icons.build))
        ..addItem(icon: PhotoducerModel.getToolIcon(PhotoducerTool.none),        text: 'Hand',         onSelected: (){ setTool(PhotoducerTool.none); })
        ..addItem(icon: PhotoducerModel.getToolIcon(PhotoducerTool.draw),        text: 'Draw',         onSelected: (){ setTool(PhotoducerTool.draw); })
        ..addItem(icon: PhotoducerModel.getToolIcon(PhotoducerTool.selectBox),   text: 'Select Box',   onSelected: (){ setTool(PhotoducerTool.selectBox); })
        ..addItem(icon: PhotoducerModel.getToolIcon(PhotoducerTool.selectFlood), text: 'Select Wand',  onSelected: (){ setTool(PhotoducerTool.selectFlood); })
        ..addItem(icon: PhotoducerModel.getToolIcon(PhotoducerTool.colorSample), text: 'Sample Color', onSelected: (){ setTool(PhotoducerTool.colorSample); })
        ..addItem(icon: PhotoducerModel.getToolIcon(PhotoducerTool.fillFlood),   text: 'Fill',         onSelected: (){ setTool(PhotoducerTool.fillFlood); })
      ).build(),

      (PopupMenuBuilder(icon: Icon(Icons.category))
        ..addItem(icon: Icon(Icons.palette),           text: 'Color',    onSelected: pickColor)
        ..addItem(icon: Icon(Icons.format_color_text), text: 'Font',     onSelected: pickFont)
        ..addItem(icon: Icon(Icons.brush),             text: 'Brush',    onSelected: pickBrush)
        ..addItem(icon: Icon(Icons.gradient),          text: 'Gradient', onSelected: pickGradient)
      ).build(),

      (PopupMenuBuilder(icon: Icon(Icons.crop_free))
        ..addItem(icon: PhotoducerModel.getToolIcon(PhotoducerTool.selectMove),  text: 'Move',  onSelected: (){ setTool(PhotoducerTool.selectMove); })
        ..addItem(icon: PhotoducerModel.getToolIcon(PhotoducerTool.selectScale), text: 'Scale', onSelected: (){ setTool(PhotoducerTool.selectScale); })
        ..addItem(icon: Icon(Icons.content_copy), text: 'Copy',  onSelected: (){
          if (photoducerState.selection != null) photoducerState.copySelection(layers.canvas);
        })
        ..addItem(icon: Icon(Icons.remove_from_queue), text: 'Cut',  onSelected: (){
          if (photoducerState.selection != null) photoducerState.copySelection(layers.canvas, cut: true);
        })
        ..addItem(icon: Icon(Icons.add_to_queue), text: 'Paste',  onSelected: (){
          if (photoducerState.selection != null && photoducerState.pasteBuffer != null) photoducerState.pasteToSelection(layers.canvas);
        })
        ..addItem(icon: Icon(Icons.crop),              text: 'Crop', onSelected: (){
          model.addCrop(photoducerState.selection.getBounds());
          photoducerState.reset();
        })
        ..addItem(icon: Icon(Icons.format_color_fill), text: 'Fill', onSelected: (){
          if (photoducerState.selection != null) layers.canvas.drawPath(photoducerState.selection, model.orthogonalState.paint);
        })
      ).build(),

      (PopupMenuBuilder(icon: Icon(Icons.border_clear))
        ..addItem(text: 'Blur',        onSelected: (){ model.addDownloadedTransform((img.Image x) => img.gaussianBlur(x, 10)); })
        ..addItem(text: 'Edge detect', onSelected: (){ model.addDownloadedTransform((img.Image x) => img.sobel(x)); })
        ..addItem(text: 'Emboss',      onSelected: (){ model.addDownloadedTransform((img.Image x) => img.emboss(x)); })
        ..addItem(text: 'Vignette',    onSelected: (){ model.addDownloadedTransform((img.Image x) => img.vignette(x)); })
        ..addItem(text: 'Sepia',       onSelected: (){ model.addDownloadedTransform((img.Image x) => img.sepia(x)); })
        ..addItem(text: 'Grayscale',   onSelected: (){ model.addDownloadedTransform((img.Image x) => img.grayscale(x)); })
      ).build(),

      (PopupMenuBuilder(icon: Icon(Icons.art_track))
        ..addItem(icon: Icon(Icons.art_track),      text: 'Recognize',     onSelected: recognizeImage)
        ..addItem(icon: Icon(Icons.filter_vintage), text: 'Generate Cat',  onSelected: (){ generateImage('contours2cats'); })
        ..addItem(icon: Icon(Icons.toys),           text: 'Generate Shoe', onSelected: (){ generateImage('edges2shoes'); })
      ).build(),

      (PopupMenuBuilder(icon: Icon(Icons.settings))
        ..addItem(text: 'repaint',    onSelected: (){ model.updateUploadedStateMethod = model.updateUploadedStateRepaint; })
        ..addItem(text: 'paintDelta', onSelected: (){ model.updateUploadedStateMethod = model.updateUploadedStatePaintDelta; })
      ).build(),

      (PopupMenuBuilder(icon: Icon(Icons.share))
        ..addItem(text: 'Twitter')
        ..addItem(text: 'Facebook')
      ).build(),
    ];

    return Container(
      height: 100,
      child: Card(
        color: Colors.blueGrey[100],
        child: Center(
          child: ListView(
            shrinkWrap: true,
            scrollDirection: Axis.horizontal,
            children: toolbar,
          ),
        ),
      ),
    );
  }

  void setTool(PhotoducerTool tool) => setState((){ photoducerState.setTool(tool); });

  void pickStockImage() {
    List<String> stockImages = const <String> [ 'dogandhorse.jpg', 'shoeedges.png', 'catcontours.png', 'yao.jpg' ];
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Select an image'),
        content: Container(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            scrollDirection: Axis.vertical,
            itemCount: stockImages.length,
            itemBuilder: (BuildContext context, int index) => GestureDetector(
              child: Image(image: AssetImage(assetPath(stockImages[index]))),
              onTap: (){
                Navigator.of(context).pop();
                loadAssetImage(stockImages[index]);
              },
            ),
          ),
        ),
        actions: <Widget>[
          FlatButton(
            child: const Text('Cancel'),
            onPressed: () { Navigator.of(context).pop(); },
          ),
        ],
      ),
    );
  }

  void pickColor() {
    Color pickerColor = model.orthogonalState.paint.color;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Pick a color'),
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
            child: const Text('Done'),
            onPressed: () {
              setState((){ model.changeColor(pickerColor); });
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }

  void pickFont() {
    List<String> fontFamily = const <String> [ 'Roboto', 'Rock Salt', 'VT323', 'Ewert', 'MaterialIcons' ];
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Select a font'),
        content: Container(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            scrollDirection: Axis.vertical,
            itemCount: fontFamily.length,
            itemBuilder: (BuildContext context, int index) => GestureDetector(
              child: Container(
                child: Column(
                  children: <Widget>[
                    Text(fontFamily[index]),
                    Text(fontFamily[index] == 'MaterialIcons' ?
                      '\u{E914}\u{E000}\u{E90D}\u{E3AF}\u{E40A}\u{E420}\u{E52F}\u{E636}\u{EB3E}\u{E80B}\u{E838}' :
                      'Brevity is levity pressed for expressitivity',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: fontFamily[index],
                        fontSize: 17.0,
                      ),
                    ),
                  ],
                ),
                margin: const EdgeInsets.all(10.0),
                padding: const EdgeInsets.all(10.0),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.all(Radius.circular(5.0)),
                ),
              ),
              onTap: () { Navigator.of(context).pop(); },
            ),
          ),
        ),
        actions: <Widget>[
          FlatButton(
            child: const Text('Done'),
            onPressed: () { Navigator.of(context).pop(); },
          ),
        ],
      ),
    );
  }

  void pickBrush() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Brush'),
        content: _BrushPicker(model.orthogonalState.paint),
        actions: <Widget>[
          FlatButton(
            child: const Text('Done'),
            onPressed: () { Navigator.of(context).pop(); },
          ),
        ],
      ),
    );
  }

  void pickGradient() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Gradient'),
        content: GradientPicker(photoducerState.gradient, model.orthogonalState.paint),
        actions: <Widget>[
          FlatButton(
            child: const Text('Done'),
            onPressed: () { Navigator.of(context).pop(); },
          ),
        ],
      ),
    );
  }

  Future<void> voidResult() async {}

  Future<void> newImage() async {
    scaledImageSize = null;
    loadedImage = null;
    loadUiImage(null);
  }

  Future<void> pickImage() async {
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

  Future<void> loadAssetImage(String name) async {
    setState((){
      loadedImage = name;
      scaledImageSize = null;
      model.busy.setBusy('Loading ' + loadedImage);
    });
    ui.Image image = await loadAssetFile(name);
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
    return loadImageFile(file);
  }

  void loadUiImage(ui.Image image) {
    model.reset(image);
    photoducerState.reset();
    model.busy.reset();
    setState((){});
  }

  Future<String> saveImage() async {
    ui.Image image = model.state.uploaded;
    if (scaledImageSize != null) {
      model.busy.setBusy('Rendering at full resolution');
      PhotographTransducer fullResTransducer = PhotographTransducer();
      fullResTransducer.reset(await loadImageFileNamed(loadedImage, downscale: false));
      fullResTransducer.addList(model.input, startIndex: 1);
      image = await fullResTransducer.getUploadedState();
    }
    model.busy.setBusy('Saving');
    var pngBytes = await image.toByteData(format: ui.ImageByteFormat.png);
    String filename = await ImagePickerSaver.saveFile(fileData: pngBytes.buffer.asUint8List());
    model.busy.reset();
    return filename;
  }

  Future<String> exportSVG() async {
    img.Image downloaded = await model.state.getDownloadedState();
    String svg = potrace(downloaded);
    String path = await stashPath('export.svg');
    debugPrint('exportSVG: ' + path);
    await File(path).writeAsString(svg);
    return path;
  }

  Future<String> stashPath(String name) async {
    Directory directory = await getApplicationDocumentsDirectory();
    return directory.path + Platform.pathSeparator + name;
  }

  Future<String> stashImagePath(String name) async => stashPath(name + '.png');

  Future<String> stashImage(ui.Image image, String name) async {
    var pngBytes = await image.toByteData(format: ui.ImageByteFormat.png);
    String path = await stashImagePath(name);
    File(path).writeAsBytesSync(pngBytes.buffer.asInt8List());
    return path;
  }

  Future<String> stashRenderedImage(String name) async {
    ui.Image image = model.state.uploaded;
    return stashImage(image, name);
  }

  Future<ui.Image> unstashImage(String name) async {
    String filePath = await stashImagePath(name);
    return loadImageFileNamed(filePath);
  }

  void generateImage(String modelName) async {
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

    model.busy.reset();
    model.addRedraw(uploadedImage);
  }

  Future<void> recognizeImage() async {
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
        model:  assetPath(name + '.tflite'),
        labels: assetPath(name + '.txt'),
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

class _BrushPicker extends StatefulWidget {
  Paint paint;
  _BrushPicker(this.paint);

  @override
  _BrushPickerState createState() => _BrushPickerState();
}

class _BrushPickerState extends State<_BrushPicker> {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.maxFinite,
      child: ListView(
        shrinkWrap: true,
        children: <Widget>[
          ListTile(
            title: Text('Shape'),
            trailing: DropdownButton<String>(
              value: enumName(widget.paint.strokeCap),
              onChanged: (String val) =>
                setState((){ widget.paint.strokeCap = StrokeCap.values.firstWhere((x) => enumName(x) == val); }),
              items: buildDropdownMenuItem(StrokeCap.values.map(enumName).toList()),
            ),
          ),

          ListTile(
            title: Text('Blend'),
            trailing: DropdownButton<String>(
              value: enumName(widget.paint.blendMode),
              onChanged: (String val) =>
                setState((){ widget.paint.blendMode = BlendMode.values.firstWhere((x) => enumName(x) == val); }),
              items: buildDropdownMenuItem(BlendMode.values.map(enumName).toList()),
            ),
            onTap: () => setState((){ widget.paint.blendMode = BlendMode.srcOver; }),
          ),

          ListTile(
            title: Text('Anti-Alias'),
            trailing: Checkbox(
              value: widget.paint.isAntiAlias,
              onChanged: (bool val) => setState((){ widget.paint.isAntiAlias = val; }),
            ),
            onTap: () => setState((){ widget.paint.isAntiAlias = !widget.paint.isAntiAlias; }),
          ),

          NumberPicker('Width',
            ([double x]) {
              if (x != null) setState(() => widget.paint.strokeWidth = x);
              return widget.paint.strokeWidth;
            }
          ),

          Card(
            color: Colors.blueGrey[50],
            child: Container(
              width: 100,
              height: 100,
              child: CustomPaint(
                painter: _BrushPainter(widget.paint),
              ),
            ),
          ),
        ]
      ),
    );
  }
}

class _BrushPainter extends CustomPainter {
  Paint style;
  _BrushPainter(this.style);

  @override
  void paint(Canvas canvas, Size size) {
    Offset c = Offset(size.width/2.0, size.height/2.0);
    if (style.strokeCap == StrokeCap.round) {
      canvas.drawCircle(c, style.strokeWidth, style);
    } else {
      double w = style.strokeWidth;
      canvas.drawRect(Rect.fromLTRB(c.dx - w, c.dy - w,
                                    c.dx + w, c.dy + w), style);
    }
  }

  @override
  bool shouldRepaint(_BrushPainter oldDelegate) => true;
}
