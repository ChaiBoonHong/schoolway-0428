import 'package:flutter/material.dart';

/// One stable accent per [busId] for parent, admin, and driver maps (same bus → same colour).
Color fleetBusAccentColor(String busId) {
  if (busId.isEmpty) {
    return const Color(0xFF0077B6);
  }
  final h = busId.hashCode & 0x7fffffff;
  const golden = 137.508;
  final hue = ((h % 360) * golden) % 360.0;
  return HSVColor.fromAHSV(1.0, hue, 0.72, 0.88).toColor();
}
