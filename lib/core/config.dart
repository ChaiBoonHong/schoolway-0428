class AppConfig {
  static const gpsUploadInterval = Duration(seconds: 3); // target 3–5 seconds

  /// Shown on map screens and should match the contact published on your store listing.
  static const String supportContactEmail = 'support@schoolway.app';

  /// Web Push (FCM): Firebase Console → Project settings → Cloud Messaging →
  /// **Web Push certificates** → Generate key pair → paste the **public** key here.
  /// Required for `getToken` on web; leave empty to skip web token registration.
  static const String fcmWebVapidKey =
      'BNJ5ZHW2qpistGWMXSotp_ok-Mv-fwyECf9_IbCZQESDPMvatfBD9qCi4mA2iq9mYJYGvDwa_HWXb1RbhuwSOIg';

  /// Primary school administration phone hotline for driver support.
  static const String adminPhoneNumber = '+18005550199';
}
