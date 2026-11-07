import 'video_fullscreen_stub.dart'
    if (dart.library.js_interop) 'video_fullscreen_web.dart'
    as platform;

import 'video_fullscreen_result.dart';

export 'video_fullscreen_result.dart';

Future<VideoFullscreenResult> enterVideoFullscreen() =>
    platform.enterVideoFullscreen();

Future<void> exitVideoFullscreen() => platform.exitVideoFullscreen();
