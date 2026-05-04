part of '../admin_home.dart';

class AdminLiveFleetTab extends StatefulWidget {
  const AdminLiveFleetTab({super.key});

  @override
  State<AdminLiveFleetTab> createState() => _AdminLiveFleetTabState();
}

class _AdminLiveFleetTabState extends State<AdminLiveFleetTab> {
  final MapController _mapController = MapController();

  final Stream<List<Bus>> _busStream = FirebaseService.getBuses();
  final Stream<Map<String, GpsTracking>> _gpsStream =
      FirebaseService.getAllGpsTracking();

  static const LatLng _fallback = LatLng(3.1390, 101.6869);

  String? _lastFittedSignature;
  String? _selectedBusId;
  Map<String, PlannedRoute> _plannedByIdCache = const {};

  @override
  void dispose() {
    final c = _mapController;
    WidgetsBinding.instance.addPostFrameCallback((_) => c.dispose());
    super.dispose();
  }

  void _focusBusOnMap(Bus bus, Map<String, GpsTracking> gpsByBus) {
    setState(() => _selectedBusId = bus.id);
    final pos = fleetBusMapPosition(gps: gpsByBus[bus.id], bus: bus);
    if (pos == null) {
      final routeId = bus.assignedRouteId;
      if (routeId != null && routeId.trim().isNotEmpty) {
        final planned = _plannedByIdCache[routeId];
        if (planned != null && planned.waypoints.isNotEmpty) {
          final points = planned.waypoints
              .map((w) => LatLng(w.latitude, w.longitude))
              .toList();
          try {
            if (points.length == 1) {
              _mapController.move(points.first, 15);
            } else {
              _mapController.fitCamera(
                CameraFit.bounds(
                  bounds: LatLngBounds.fromPoints(points),
                  padding: const EdgeInsets.all(80),
                  maxZoom: 17,
                ),
              );
            }
            return;
          } catch (_) {}
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No GPS position for ${bus.busNumber} yet.',
            style: const TextStyle(fontFamily: 'Lexend'),
          ),
          backgroundColor: Colors.orange.shade800,
        ),
      );
      return;
    }
    try {
      _mapController.move(pos, 15);
    } catch (_) {}
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Active':
        return Colors.green;
      case 'Idle':
        return Colors.orange;
      case 'Maintenance':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _formatTimestamp(DateTime? timestamp) {
    if (timestamp == null) return 'No data';
    final now = DateTime.now();
    final diff = now.difference(timestamp);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) {
      return '${diff.inHours} hour${diff.inHours > 1 ? 's' : ''} ago';
    }
    return '${diff.inDays} day${diff.inDays > 1 ? 's' : ''} ago';
  }

  LatLng? _positionForBus(Bus bus, Map<String, GpsTracking> gpsByBus) {
    return fleetBusMapPosition(gps: gpsByBus[bus.id], bus: bus);
  }

  String _positionsSignature(
    List<Bus> buses,
    Map<String, GpsTracking> gpsByBus,
  ) {
    final parts = <String>[];
    for (final bus in buses) {
      final pos = _positionForBus(bus, gpsByBus);
      if (pos == null) continue;
      parts.add(
        '${bus.id}:${pos.latitude.toStringAsFixed(5)},${pos.longitude.toStringAsFixed(5)}',
      );
    }
    parts.sort();
    return parts.join('|');
  }

  void _scheduleFitToAllBuses(List<LatLng> points, String signature) {
    if (signature.isEmpty) {
      _lastFittedSignature = null;
      return;
    }
    if (signature == _lastFittedSignature) return;
    _lastFittedSignature = signature;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (points.isEmpty) return;
      final mc = _mapController;
      try {
        if (points.length == 1) {
          mc.move(points.first, 14);
          return;
        }
        final bounds = LatLngBounds.fromPoints(points);
        final latSpan = (bounds.north - bounds.south).abs();
        final lngSpan = (bounds.east - bounds.west).abs();
        if (latSpan < 1e-8 && lngSpan < 1e-8) {
          mc.move(points.first, 14);
          return;
        }
        mc.fitCamera(
          CameraFit.bounds(
            bounds: bounds,
            padding: const EdgeInsets.all(80),
            maxZoom: 18,
            minZoom: 2,
          ),
        );
      } catch (_) {
        try {
          mc.move(points.first, 13);
        } catch (_) {}
      }
    });
  }

  void _zoomIn() {
    try {
      final c = _mapController.camera;
      _mapController.move(c.center, (c.zoom + 1).clamp(3, 19));
    } catch (_) {}
  }

  void _zoomOut() {
    try {
      final c = _mapController.camera;
      _mapController.move(c.center, (c.zoom - 1).clamp(3, 19));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Bus>>(
      stream: _busStream,
      builder: (context, busSnapshot) {
        if (busSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF0077B6)),
          );
        }
        if (busSnapshot.hasError) {
          return Center(
            child: Text(
              'Error loading fleet: ${busSnapshot.error}',
              style: const TextStyle(fontFamily: 'Lexend'),
            ),
          );
        }

        final buses = busSnapshot.data ?? [];
        final activeBuses = buses.where((b) => b.status == 'Active').length;

        return StreamBuilder<QuerySnapshot>(
          stream: swFirestore
              .collection('students')
              .snapshots(),
          builder: (context, studentSnapshot) {
            final totalStudents = studentSnapshot.data?.docs.length ?? 0;

            return StreamBuilder<Map<String, GpsTracking>>(
              stream: _gpsStream,
              builder: (context, gpsSnapshot) {
                final gpsByBus = gpsSnapshot.data ?? {};
                return StreamBuilder<List<PlannedRoute>>(
                  stream: FirebaseService.getPlannedRoutes(),
                  builder: (context, plannedSnapshot) {
                    final plannedById = <String, PlannedRoute>{};
                    for (final route
                        in plannedSnapshot.data ?? const <PlannedRoute>[]) {
                      plannedById[route.id] = route;
                    }
                    _plannedByIdCache = plannedById;

                    // Build markers
                    final markers = <Marker>[];
                    final points = <LatLng>[];
                    for (final bus in buses) {
                      final pos = _positionForBus(bus, gpsByBus);
                      if (pos == null) continue;
                      points.add(pos);
                      markers.add(buildFleetBusMarker(
                        point: pos,
                        busId: bus.id,
                        busLabel: bus.busNumber,
                      ));
                    }

                    final center = points.isEmpty
                        ? _fallback
                        : LatLng(
                            points
                                    .map((p) => p.latitude)
                                    .reduce((a, b) => a + b) /
                                points.length,
                            points
                                    .map((p) => p.longitude)
                                    .reduce((a, b) => a + b) /
                                points.length,
                          );
                    final zoom = points.isEmpty
                        ? 11.0
                        : (points.length == 1 ? 14.0 : 11.0);

                    final sig = _positionsSignature(buses, gpsByBus);
                    _scheduleFitToAllBuses(points, sig);

                    return StreamBuilder<List<RouteSession>>(
                      stream: FirebaseService.watchAllActiveRouteSessions(),
                      builder: (context, sessionSnap) {
                        var tripDirForSelected = TripDirection.toSchool;
                        if (_selectedBusId != null) {
                          for (final s
                              in sessionSnap.data ?? const <RouteSession>[]) {
                            if (s.busId == _selectedBusId) {
                              tripDirForSelected = s.tripDirection;
                              break;
                            }
                          }
                        }

                        Polyline? selectedRoutePolyline;
                        final selectedStopMarkers = <Marker>[];
                        if (_selectedBusId != null) {
                          final selectedMatches =
                              buses.where((b) => b.id == _selectedBusId);
                          final selectedBus = selectedMatches.isEmpty
                              ? null
                              : selectedMatches.first;
                          final routeId = selectedBus?.assignedRouteId;
                          if (routeId != null && routeId.trim().isNotEmpty) {
                            final planned = plannedById[routeId];
                            if (planned != null &&
                                planned.waypoints.length >= 2) {
                              selectedRoutePolyline = Polyline(
                                points: planned
                                    .waypointsForTrip(tripDirForSelected)
                                    .map((w) => LatLng(w.latitude, w.longitude))
                                    .toList(),
                                strokeWidth: 5,
                                color: fleetBusAccentColor(_selectedBusId!)
                                    .withValues(alpha: 0.75),
                              );
                              final stops =
                                  planned.editableStopsForTrip(tripDirForSelected);
                              for (var i = 0; i < stops.length; i++) {
                                final stop = stops[i];
                                selectedStopMarkers.add(
                                  Marker(
                                    point:
                                        LatLng(stop.latitude, stop.longitude),
                                    width: 30,
                                    height: 30,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF00B4D8),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 2,
                                        ),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        '${i + 1}',
                                        style: const TextStyle(
                                          fontFamily: 'Lexend',
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }
                            }
                          }
                        }

                        return Stack(
                      fit: StackFit.expand,
                      children: [
                    // Full-screen map
                    Positioned.fill(
                      child: FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: center,
                          initialZoom: zoom,
                        ),
                        children: [
                          const OsmMapTileLayer(),
                          if (selectedRoutePolyline != null)
                            PolylineLayer(polylines: [selectedRoutePolyline]),
                          if (selectedStopMarkers.isNotEmpty)
                            MarkerLayer(markers: selectedStopMarkers),
                          if (markers.isNotEmpty)
                            MarkerLayer(markers: markers),
                        ],
                      ),
                    ),

                    // OSM attribution top-left
                    const Positioned(
                      top: 8,
                      left: 8,
                      right: 8,
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: OsmMapAttribution(compact: true),
                      ),
                    ),

                    // Floating stat badges — top-right
                    Positioned(
                      top: 40,
                      right: 12,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _FleetStatBadge(
                            icon: Icons.directions_bus,
                            value: '$activeBuses',
                            label: 'Active',
                            color: Colors.green,
                          ),
                          const SizedBox(height: 6),
                          _FleetStatBadge(
                            icon: Icons.people,
                            value: '$totalStudents',
                            label: 'Students',
                            color: const Color(0xFF0077B6),
                          ),
                          const SizedBox(height: 6),
                          _FleetStatBadge(
                            icon: Icons.airport_shuttle,
                            value: '${buses.length}',
                            label: 'Fleet',
                            color: Colors.orange,
                          ),
                        ],
                      ),
                    ),

                    // Zoom controls
                    Positioned(
                      right: 16,
                      bottom: 300,
                      child: Column(
                        children: [
                          _MapControlBtn(
                            icon: Icons.add,
                            tooltip: 'Zoom in',
                            onPressed: _zoomIn,
                          ),
                          const SizedBox(height: 8),
                          _MapControlBtn(
                            icon: Icons.remove,
                            tooltip: 'Zoom out',
                            onPressed: _zoomOut,
                          ),
                        ],
                      ),
                    ),

                    // Bus list as draggable bottom sheet
                    DraggableScrollableSheet(
                      initialChildSize: 0.30,
                      minChildSize: 0.10,
                      maxChildSize: 0.75,
                      snap: true,
                      snapSizes: const [0.10, 0.30, 0.75],
                      builder: (context, scrollController) {
                        return Container(
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(20),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 12,
                                offset: Offset(0, -4),
                              ),
                            ],
                          ),
                          child: buses.isEmpty
                              ? _buildEmptyState(scrollController)
                              : _buildBusList(
                                  buses,
                                  gpsByBus,
                                  scrollController,
                                ),
                        );
                      },
                    ),
                      ],
                    );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState(ScrollController scrollController) {
    return ListView(
      controller: scrollController,
      children: [
        _buildDragHandle(),
        const SizedBox(height: 48),
        const Center(
          child: Column(
            children: [
              Icon(
                Icons.directions_bus_outlined,
                size: 48,
                color: Color(0xFF00B4D8),
              ),
              SizedBox(height: 12),
              Text(
                'No buses in fleet',
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Add buses in Bus Management',
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 13,
                  color: Color(0xFF0077B6),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBusList(
    List<Bus> buses,
    Map<String, GpsTracking> gpsByBus,
    ScrollController scrollController,
  ) {
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        _buildDragHandle(),
        const Text(
          'Tap a bus card to show it on the map',
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 12,
            color: Color(0xFF0077B6),
          ),
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < buses.length; i++) ...[
          _buildBusCard(buses[i], gpsByBus),
          SizedBox(height: i < buses.length - 1 ? 12 : 24),
        ],
      ],
    );
  }

  Widget _buildDragHandle() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  Widget _buildBusCard(Bus bus, Map<String, GpsTracking> gpsByBus) {
    final statusColor = _getStatusColor(bus.status);
    final fleetAccent = fleetBusAccentColor(bus.id);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _focusBusOnMap(bus, gpsByBus),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: (_selectedBusId == bus.id
                      ? fleetAccent
                      : fleetAccent.withValues(alpha: 0.35)),
              width: _selectedBusId == bus.id ? 2 : 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: fleetAccent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.directions_bus,
                      color: fleetAccent,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          bus.busNumber,
                          style: const TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF03045E),
                          ),
                        ),
                        if (bus.currentDriverId != null)
                          FutureBuilder<Map<String, dynamic>?>(
                            future: FirebaseService.getUserDataByAuthUid(
                              bus.currentDriverId!,
                            ),
                            builder: (context, driverSnapshot) {
                              final driver = driverSnapshot.data;
                              return Text(
                                driver != null
                                    ? '${driver['firstName'] ?? ''} ${driver['lastName'] ?? ''}'
                                          .trim()
                                    : 'Loading driver...',
                                style: const TextStyle(
                                  fontFamily: 'Lexend',
                                  fontSize: 14,
                                  color: Color(0xFF0077B6),
                                ),
                                overflow: TextOverflow.ellipsis,
                              );
                            },
                          )
                        else
                          const Text(
                            'No driver assigned',
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 14,
                              color: Color(0xFF999999),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      bus.status,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(
                    Icons.route,
                    size: 16,
                    color: Color(0xFF00B4D8),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    bus.currentRoute ?? 'No route assigned',
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 14,
                      color: bus.currentRoute != null
                          ? const Color(0xFF0077B6)
                          : const Color(0xFF999999),
                      fontStyle: bus.currentRoute != null
                          ? FontStyle.normal
                          : FontStyle.italic,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.airline_seat_recline_normal,
                    size: 16,
                    color: Color(0xFF00B4D8),
                  ),
                  const SizedBox(width: 4),
                  StreamBuilder<QuerySnapshot>(
                    stream: swFirestore
                        .collection('students')
                        .where('assignedBusId', isEqualTo: bus.id)
                        .snapshots(),
                    builder: (context, studentsSnapshot) {
                      final count =
                          studentsSnapshot.data?.docs.length ?? 0;
                      return Text(
                        '$count/${bus.capacity} students',
                        style: const TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 12,
                          color: Color(0xFF0077B6),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 16),
                  const Icon(
                    Icons.pin,
                    size: 16,
                    color: Color(0xFF00B4D8),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    bus.licensePlate,
                    style: const TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 12,
                      color: Color(0xFF0077B6),
                    ),
                  ),
                  const Spacer(),
                  if (bus.lastLocation != null) ...[
                    const Icon(
                      Icons.access_time,
                      size: 16,
                      color: Color(0xFF00B4D8),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _formatTimestamp(bus.lastLocation?.timestamp),
                      style: const TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 12,
                        color: Color(0xFF999999),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FleetStatBadge extends StatelessWidget {
  const _FleetStatBadge({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 6,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            '$value $label',
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _MapControlBtn extends StatelessWidget {
  const _MapControlBtn({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      elevation: 2,
      child: IconButton(
        icon: Icon(icon, color: const Color(0xFF0077B6)),
        onPressed: onPressed,
        tooltip: tooltip,
      ),
    );
  }
}
