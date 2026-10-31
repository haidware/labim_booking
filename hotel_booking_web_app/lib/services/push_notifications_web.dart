import 'dart:js_interop';

@JS("roomsPush.subscribe")
external JSPromise<JSString> _subscribe(JSString publicKey);

@JS("roomsPush.permissionState")
external JSString _permissionState();

@JS("roomsPush.existingSubscription")
external JSPromise<JSString> _existingSubscription();

Future<String> createPushSubscription(String publicKey) async {
  final subscription = await _subscribe(publicKey.toJS).toDart;
  return subscription.toDart;
}

String notificationPermissionState() => _permissionState().toDart;

Future<String> loadExistingPushSubscription() async {
  return (await _existingSubscription().toDart).toDart;
}
