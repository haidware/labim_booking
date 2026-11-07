import 'package:flutter/services.dart';

import 'video_fullscreen_result.dart';

Future<VideoFullscreenResult> enterVideoFullscreen() async {
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  return const VideoFullscreenResult(
    browserFullscreen: true,
    landscapeLocked: true,
  );
}

Future<void> exitVideoFullscreen() async {
  await SystemChrome.setPreferredOrientations([]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
}
