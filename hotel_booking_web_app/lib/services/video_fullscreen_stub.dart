import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'video_fullscreen_result.dart';

Future<VideoFullscreenResult> enterVideoFullscreen() async {
  var landscapeLocked = false;
  try {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    landscapeLocked = true;
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  } on Object catch (error, stackTrace) {
    debugPrint('Landscape fullscreen is unavailable: $error\n$stackTrace');
  }
  return VideoFullscreenResult(
    browserFullscreen: true,
    landscapeLocked: landscapeLocked,
  );
}

Future<void> exitVideoFullscreen() async {
  try {
    await SystemChrome.setPreferredOrientations([]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  } on Object catch (error, stackTrace) {
    debugPrint('Could not restore screen orientation: $error\n$stackTrace');
  }
}
