import 'dart:html' as html;

Future<bool> ensureNotificationPermission() async {
  if (!html.Notification.supported) return false;

  final permission = html.Notification.permission;
  if (permission == 'granted') return true;
  if (permission == 'denied') return false;

  final requested = await html.Notification.requestPermission();
  return requested == 'granted';
}

void showBrowserNotification({
  required String title,
  required String body,
}) {
  if (!html.Notification.supported) return;
  if (html.Notification.permission != 'granted') return;

  final notification = html.Notification(
    title,
    body: body,
    icon: '/icons/Icon-192.png',
  );

  notification.onClick.listen((_) {
    notification.close();
  });
}
