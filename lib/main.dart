import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_crashlytics/flutter_crashlytics.dart';

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

  runZoned<Future<void>>(() async {
    runApp(PhotoducerApp());
  }, onError: (error, stackTrace) async {
    await FlutterCrashlytics().reportCrash(error, stackTrace, forceCrash: false);
  });
}

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
