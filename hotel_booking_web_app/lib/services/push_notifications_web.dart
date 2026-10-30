import 'dart:js_interop';

@JS("roomsPush.subscribe")
external JSPromise<JSString> _subscribe(JSString publicKey);

Future<String> createPushSubscription(String publicKey) async {
  final subscription = await _subscribe(publicKey.toJS).toDart;
  return subscription.toDart;
}
