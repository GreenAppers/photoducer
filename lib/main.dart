import 'dart:async';

import 'package:flutter/material.dart';

import 'package:busy_model/busy_model.dart';
import 'package:flutter_crashlytics/flutter_crashlytics.dart';
import 'package:gradient_app_bar/gradient_app_bar.dart';
import 'package:gradient_picker/gradient_picker.dart';
import 'package:persistent_canvas/persistent_canvas.dart';
import 'package:persistent_canvas/persistent_canvas_stack.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:photoducer/workspace.dart';

void main() async {
  bool inDebugMode = false;
  assert(inDebugMode = true);
  PhotoducerPreferences prefs = PhotoducerPreferences(await SharedPreferences.getInstance());
  bool reportCrashes = prefs.reportCrashes;
  debugPrint('Photoducer main() inDebugMode=' + inDebugMode.toString() + ' reportCrashes=' + reportCrashes.toString());

  if (reportCrashes) {
    FlutterError.onError = (FlutterErrorDetails details) {
      if (inDebugMode) FlutterError.dumpErrorToConsole(details);
      else Zone.current.handleUncaughtError(details.exception, details.stack);
    };
    
    await FlutterCrashlytics().initialize();
  }

  runZoned<Future<void>>(
    () async => runApp(PhotoducerApp(prefs)),
    onError: (error, stackTrace) async {
      if (reportCrashes) {
        await FlutterCrashlytics().reportCrash(error, stackTrace, forceCrash: false);
      } else {
        debugPrint(stackTrace);
      }
    }
  );
}

class PhotoducerPreferences {
  final SharedPreferences prefs;
  PhotoducerPreferences(this.prefs);
  
  String get theme => prefs.getString(themeName) ?? 'green';
  void setTheme(String v) async => prefs.setString(themeName, v);

  bool get reportCrashes => prefs.getBool(reportCrashesName) ?? true;
  void setReportCrashes(bool v) async => prefs.setBool(reportCrashesName, v);

  static final String themeName = 'theme';
  static final String reportCrashesName = 'reportCrashes';
}

class PhotoducerApp extends StatefulWidget {
  final PhotoducerPreferences prefs;
  PhotoducerApp(this.prefs);

  @override
  _PhotoducerAppState createState() => _PhotoducerAppState();
}

class _PhotoducerAppState extends State<PhotoducerApp> {
  final PersistentCanvasStack layers = PersistentCanvasStack(
    busy: BusyModel(),
    coordinates: PersistentCanvasCoordinates.normalize,
  );

  @override
  Widget build(BuildContext context) {
    String theme = widget.prefs.theme;
    return MaterialApp(
      title: 'Photoducer',
      theme: ThemeData(
        primarySwatch: primaryColor[theme] ?? Colors.green,
        accentColor:    accentColor[theme] ?? Colors.greenAccent,
      ),
      home: BusyScope(
        model: layers.busy,
        child: PhotoducerWorkspace(layers),
      ),
      routes: <String, WidgetBuilder> {
        '/settings': (BuildContext context) => PhotoducerSettings(this, widget.prefs),
      },
    );
  }
}

class PhotoducerSettings extends StatefulWidget {
  final State appState;
  final PhotoducerPreferences prefs;
  PhotoducerSettings(this.appState, this.prefs);

  @override
  _PhotoducerSettingsState createState() => _PhotoducerSettingsState();
}

class _PhotoducerSettingsState extends State<PhotoducerSettings> {
  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: GradientAppBar(
        title: Text('Settings'),
        backgroundColorStart: theme.primaryColor,
        backgroundColorEnd: theme.accentColor,
      ),
      body: ListView(
        children: <Widget>[
          ListTile(
            title: Text('Theme'),
            trailing: DropdownButton<String>(
              value: widget.prefs.theme,
              onChanged: (String val) async {
                await widget.prefs.setTheme(val);
                widget.appState.setState((){});
              },
              items: buildDropdownMenuItem(primaryColor.keys.toList()),
            ),
          ),

          ListTile(
            title: Text('Send crash reports and anonymous usage statistics'),
            trailing: Checkbox(
              value: widget.prefs.reportCrashes,
              onChanged: (bool val) async {
                await widget.prefs.setReportCrashes(val);
                widget.appState.setState((){});
              },
            ),
          ),
        ]
      ),
    );
  }
}

const Map<String, MaterialColor> primaryColor = <String, MaterialColor>{
  'red':        Colors.red,        
  'pink':       Colors.pink,
  'purple':     Colors.purple,
  'deepPurple': Colors.deepPurple,
  'indigo':     Colors.indigo,
  'blue':       Colors.blue,
  'lightBlue':  Colors.lightBlue,
  'cyan':       Colors.cyan,
  'teal':       Colors.teal,
  'green':      Colors.green,
  'lightGreen': Colors.lightGreen,
  'lime':       Colors.lime,
  'yellow':     Colors.yellow,
  'amber':      Colors.amber,
  'orange':     Colors.orange,
  'deepOrange': Colors.deepOrange,
  'brown':      Colors.brown,
  'blueGrey':   Colors.blueGrey,
};

Map<String, Color> accentColor = <String, Color>{
  'red':        Colors.redAccent,
  'pink':       Colors.pinkAccent,
  'purple':     Colors.purpleAccent,
  'deepPurple': Colors.deepPurpleAccent,
  'indigo':     Colors.indigoAccent,
  'blue':       Colors.blueAccent,
  'lightBlue':  Colors.lightBlueAccent,
  'cyan':       Colors.cyanAccent,
  'teal':       Colors.tealAccent,
  'green':      Colors.greenAccent,
  'lightGreen': Colors.lightGreenAccent,
  'lime':       Colors.limeAccent,
  'yellow':     Colors.yellowAccent,
  'amber':      Colors.amberAccent,
  'orange':     Colors.orangeAccent,
  'deepOrange': Colors.deepOrangeAccent,
  'brown':      Colors.brown[100],
  'blueGrey':   Colors.blueGrey[100],
};
