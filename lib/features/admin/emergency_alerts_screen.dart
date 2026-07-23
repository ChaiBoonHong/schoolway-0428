import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:schoolway/core/widgets/osm_map_tile_layer.dart';
import 'package:schoolway/models/models.dart';
import 'package:schoolway/services/firebase_service.dart';

/// Lists active emergency alerts from drivers and allows resolving them.
class EmergencyAlertsScreen extends StatelessWidget {
  const EmergencyAlertsScreen({super.key});

  void _openMap(BuildContext context, EmergencyAlert alert) {
    final lat = alert.location.latitude;
    final lng = alert.location.longitude;
    final point = LatLng(lat, lng);

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: Stack(
              children: [
                FlutterMap(
                  options: MapOptions(
                    initialCenter: point,
                    initialZoom: 16.0,
                  ),
                  children: [
                    const OsmMapTileLayer(),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: point,
                          width: 40,
                          height: 40,
                          child: const Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.red,
                            size: 40,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton.filled(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _resolve(BuildContext context, EmergencyAlert alert) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseService.resolveEmergencyAlert(alert.id, uid);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Marked resolved', style: TextStyle(fontFamily: 'Lexend')),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$e', style: const TextStyle(fontFamily: 'Lexend')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFCAF0F8),
      appBar: AppBar(
        title: const Text(
          'Emergency alerts',
          style: TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w600,
            color: Color(0xFF03045E),
          ),
        ),
        backgroundColor: const Color(0xFFCAF0F8),
        elevation: 0,
        foregroundColor: const Color(0xFF03045E),
      ),
      body: StreamBuilder<List<EmergencyAlert>>(
        stream: FirebaseService.getActiveEmergencyAlerts(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '${snap.error}',
                  style: const TextStyle(fontFamily: 'Lexend'),
                ),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF0077B6)),
            );
          }
          final alerts = snap.data!;
          if (alerts.isEmpty) {
            return const Center(
              child: Text(
                'No active emergency alerts.',
                style: TextStyle(fontFamily: 'Lexend'),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: alerts.length,
            itemBuilder: (context, i) {
              final a = alerts[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: Colors.red),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FutureBuilder<Bus?>(
                              future: FirebaseService.getBusById(a.busId),
                              builder: (context, busSnap) {
                                final label = busSnap.data?.busNumber ?? a.busId;
                                return Text(
                                  'Bus $label',
                                  style: const TextStyle(
                                    fontFamily: 'Lexend',
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        DateFormat.yMMMd().add_jm().format(a.timestamp),
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 13,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Location: ${a.location.latitude.toStringAsFixed(5)}, ${a.location.longitude.toStringAsFixed(5)}',
                        style: const TextStyle(fontFamily: 'Lexend', fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Parents notified: ${a.parentsNotifiedCount}',
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 13,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: () => _openMap(context, a),
                            icon: const Icon(Icons.map_outlined, size: 20),
                            label: const Text(
                              'Open in maps',
                              style: TextStyle(fontFamily: 'Lexend'),
                            ),
                          ),
                          const Spacer(),
                          FilledButton(
                            onPressed: () => _resolve(context, a),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF03045E),
                            ),
                            child: const Text(
                              'Resolve',
                              style: TextStyle(fontFamily: 'Lexend'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
