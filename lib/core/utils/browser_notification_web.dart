import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

Future<bool> ensureNotificationPermission() async {
  if (!web.window.has('Notification')) return false;

  final permission = web.Notification.permission;
  if (permission == 'granted') return true;
  if (permission == 'denied') return false;

  final requested = await web.Notification.requestPermission().toDart;
  return requested.toDart == 'granted';
}

void showBrowserNotification({required String title, required String body}) {
  if (!web.window.has('Notification')) return;
  if (web.Notification.permission != 'granted') return;

  final notification = web.Notification(
    title,
    web.NotificationOptions(body: body, icon: '/icons/Icon-192.png'),
  );

  late JSFunction onClick;
  onClick = ((web.Event _) {
    notification.removeEventListener('click', onClick);
    notification.close();
  }).toJS;

  notification.addEventListener('click', onClick);
}
