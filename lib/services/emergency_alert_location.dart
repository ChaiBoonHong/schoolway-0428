import 'package:schoolway/models/gps_tracking.dart';

const emergencyLocationMaxAge = Duration(seconds: 90);

/// Returns the authoritative current bus position for an emergency alert.
/// The driver GPS uploader writes simulated fixes to the same record as real
/// fixes, so this deliberately preserves [GpsTracking.isSimulated] rather
/// than falling back to the handset location.
GpsTracking? emergencyLocationForActiveSession({
  required GpsTracking? tracking,
  required String sessionId,
  required String driverUid,
  required DateTime now,
}) {
  if (tracking == null ||
      tracking.sessionId != sessionId ||
      tracking.driverUid != driverUid ||
      now.difference(tracking.timestamp).abs() > emergencyLocationMaxAge ||
      !tracking.latitude.isFinite ||
      !tracking.longitude.isFinite ||
      (tracking.latitude == 0 && tracking.longitude == 0)) {
    return null;
  }
  return tracking;
}
