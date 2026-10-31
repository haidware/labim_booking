import 'dart:js_interop';

@JS('roomsInstallPrompt.hasDismissed')
external JSBoolean _hasDismissed();

@JS('roomsInstallPrompt.dismiss')
external void _dismiss();

@JS('roomsInstallPrompt.platform')
external JSString _platform();

@JS('roomsInstallPrompt.isInstalled')
external JSBoolean _isInstalled();

bool hasDismissedInstallPrompt() => _hasDismissed().toDart;

void dismissInstallPrompt() => _dismiss();

String installPromptPlatform() => _platform().toDart;

bool isRunningAsInstalledApp() => _isInstalled().toDart;
