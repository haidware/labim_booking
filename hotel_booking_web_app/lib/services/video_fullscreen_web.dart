import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'video_fullscreen_result.dart';

Future<VideoFullscreenResult> enterVideoFullscreen() async {
  var browserFullscreen = false;
  var landscapeLocked = false;

  try {
    await web.document.documentElement!.requestFullscreen().toDart.timeout(
      const Duration(seconds: 2),
    );
    browserFullscreen = true;
  } on Object catch (error, stackTrace) {
    debugPrint('Browser fullscreen is unavailable: $error\n$stackTrace');
    return const VideoFullscreenResult(
      browserFullscreen: false,
      landscapeLocked: false,
    );
  }

  try {
    await web.window.screen.orientation
        .lock('landscape')
        .toDart
        .timeout(const Duration(seconds: 2));
    landscapeLocked = true;
  } on Object catch (error, stackTrace) {
    debugPrint(
      'Landscape orientation lock is unavailable: $error\n$stackTrace',
    );
    landscapeLocked = false;
  }

  return VideoFullscreenResult(
    browserFullscreen: browserFullscreen,
    landscapeLocked: landscapeLocked,
  );
}

Future<void> exitVideoFullscreen() async {
  try {
    web.window.screen.orientation.unlock();
  } on Object catch (error, stackTrace) {
    debugPrint('Could not unlock screen orientation: $error\n$stackTrace');
  }
  try {
    if (web.document.fullscreenElement != null) {
      await web.document.exitFullscreen().toDart.timeout(
        const Duration(seconds: 2),
      );
    }
  } on Object catch (error, stackTrace) {
    debugPrint('Could not exit browser fullscreen: $error\n$stackTrace');
  }
}
