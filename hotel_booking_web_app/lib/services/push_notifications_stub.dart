Future<String> createPushSubscription(String publicKey) {
  throw UnsupportedError(
    "Web push notifications are only available in a browser.",
  );
}

String notificationPermissionState() => 'unsupported';

Future<String> loadExistingPushSubscription() async => '';
