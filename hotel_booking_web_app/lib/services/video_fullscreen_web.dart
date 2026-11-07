import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'video_fullscreen_result.dart';

Future<VideoFullscreenResult> enterVideoFullscreen() async {
  var browserFullscreen = false;
  var landscapeLocked = false;

  try {
    await web.document.documentElement!.requestFullscreen().toDart;
    browserFullscreen = true;
  } on Object {
    return const VideoFullscreenResult(
      browserFullscreen: false,
      landscapeLocked: false,
    );
  }

  try {
    await web.window.screen.orientation.lock('landscape').toDart;
    landscapeLocked = true;
  } on Object {
    landscapeLocked = false;
  }

  return VideoFullscreenResult(
    browserFullscreen: browserFullscreen,
    landscapeLocked: landscapeLocked,
  );
}

Future<void> exitVideoFullscreen() async {
  web.window.screen.orientation.unlock();
  if (web.document.fullscreenElement != null) {
    await web.document.exitFullscreen().toDart;
  }
}
