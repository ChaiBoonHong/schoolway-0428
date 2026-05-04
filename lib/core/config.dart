class AppConfig {
  static const gpsUploadInterval = Duration(seconds: 3); // target 3–5 seconds

  /// Firestore document for optional remote overrides (field `tileUrlTemplate`).
  /// Create `app_config/map` in the console; authenticated clients may read per rules.
  static const String mapTileFirestoreDocPath = 'app_config/map';

  /// Default XYZ template when Firestore is absent or invalid. Prefer a CDN or
  /// policy-compliant host that supports HTTPS (HTTP/2 where available).
  static const String defaultMapTileUrlTemplate =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// Shown on map screens and should match the contact published on your store listing.
  static const String supportContactEmail = 'support@schoolway.app';

  static const String openStreetMapReportIssueUrl =
      'https://www.openstreetmap.org/fixthemap';

  /// Web Push (FCM): Firebase Console → Project settings → Cloud Messaging →
  /// **Web Push certificates** → Generate key pair → paste the **public** key here.
  /// Required for `getToken` on web; leave empty to skip web token registration.
  static const String fcmWebVapidKey =
      'BNJ5ZHW2qpistGWMXSotp_ok-Mv-fwyECf9_IbCZQESDPMvatfBD9qCi4mA2iq9mYJYGvDwa_HWXb1RbhuwSOIg';
}
