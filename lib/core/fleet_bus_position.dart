import 'package:latlong2/latlong.dart';
import 'package:schoolway/models/models.dart';

/// Canonical map pin: live `gps_tracking` first, else Firestore `bus.lastLocation`.
/// Used by admin, parent, and driver so all tabs show the same coordinates.
LatLng? fleetBusMapPosition({GpsTracking? gps, Bus? bus}) {
  if (gps != null) return LatLng(gps.latitude, gps.longitude);
  final l = bus?.lastLocation;
  if (l != null) return LatLng(l.latitude, l.longitude);
  return null;
}

bool fleetBusHasMapPosition({GpsTracking? gps, Bus? bus}) =>
    fleetBusMapPosition(gps: gps, bus: bus) != null;

String formatFleetRelativeTime(DateTime timestamp) {
  final now = DateTime.now();
  final difference = now.difference(timestamp);
  if (difference.inMinutes < 1) {
    return 'Just now';
  } else if (difference.inMinutes < 60) {
    return '${difference.inMinutes} min${difference.inMinutes == 1 ? '' : 's'} ago';
  } else if (difference.inHours < 24) {
    return '${difference.inHours} hour${difference.inHours == 1 ? '' : 's'} ago';
  } else {
    return '${difference.inDays} day${difference.inDays == 1 ? '' : 's'} ago';
  }
}

/// Single "last seen" line for status UI (matches parent cards).
String fleetBusLastSeenLabel({GpsTracking? gps, Bus? bus}) {
  if (gps != null) return gps.getLastSeenText();
  final t = bus?.lastLocation?.timestamp;
  if (t != null) return formatFleetRelativeTime(t);
  return '—';
}
