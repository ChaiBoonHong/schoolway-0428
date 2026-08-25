part of '../admin_home.dart';

class AdminLiveFleetTab extends StatefulWidget {
  const AdminLiveFleetTab({super.key});

  @override
  State<AdminLiveFleetTab> createState() => _AdminLiveFleetTabState();
}

class _AdminLiveFleetTabState extends State<AdminLiveFleetTab> {
  final SchoolWayMapController _mapController = SchoolWayMapController();
  double _zoom = 11;

  final Stream<List<Bus>> _busStream = FirebaseService.getBuses();
  final Stream<Map<String, GpsTracking>> _gpsStream =
      FirebaseService.getAllGpsTracking();

  static const LatLng _fallback = LatLng(3.1390, 101.6869);

  String? _lastFittedSignature;
  String? _selectedBusId;
  Map<String, PlannedRoute> _plannedByIdCache = {};
  final TrafficEtaService _trafficEta = TrafficEtaService();
  String? _trafficEtaSessionId;

  @override
  void dispose() {
    _trafficEta.dispose();
    _mapController.dispose();
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
          if (points.length == 1) {
            _mapController.move(center: points.first, zoom: 15);
          } else {
            _fitBounds(points);
          }
          return;
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No GPS position for ${bus.busNumber} yet.',
            style: TextStyle(fontFamily: 'Lexend'),
          ),
          backgroundColor: SchoolWayTheme.warning,
        ),
      );
      return;
    }
    _mapController.move(center: pos, zoom: 15);
  }

  void _fitBounds(List<LatLng> points) {
    if (points.isEmpty) return;
    if (points.length == 1) {
      _mapController.move(center: points.first, zoom: 14);
      return;
    }
    var south = points.first.latitude;
    var north = points.first.latitude;
    var west = points.first.longitude;
    var east = points.first.longitude;
    for (final p in points) {
      south = p.latitude < south ? p.latitude : south;
      north = p.latitude > north ? p.latitude : north;
      west = p.longitude < west ? p.longitude : west;
      east = p.longitude > east ? p.longitude : east;
    }
    if ((north - south).abs() < 1e-8 && (east - west).abs() < 1e-8) {
      _mapController.move(center: points.first, zoom: 14);
      return;
    }
    _mapController.fitBounds(
      southLatitude: south,
      westLongitude: west,
      northLatitude: north,
      eastLongitude: east,
      padding: 80,
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Active':
        return SchoolWayTheme.success;
      case 'Idle':
        return SchoolWayTheme.warning;
      case 'Maintenance':
        return SchoolWayTheme.danger;
      default:
        return SchoolWayTheme.muted;
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
      _fitBounds(points);
    });
  }

  void _zoomIn() {
    final center = _mapController.lastRequestedCenter ?? _fallback;
    _mapController.move(center: center, zoom: _zoom + 1);
  }

  void _zoomOut() {
    final center = _mapController.lastRequestedCenter ?? _fallback;
    _mapController.move(center: center, zoom: _zoom - 1);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Bus>>(
      stream: _busStream,
      builder: (context, busSnapshot) {
        if (busSnapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(color: SchoolWayTheme.primary),
          );
        }
        if (busSnapshot.hasError) {
          return Center(
            child: Text(
              'Error loading fleet: ${busSnapshot.error}',
              style: TextStyle(fontFamily: 'Lexend'),
            ),
          );
        }

        final buses = busSnapshot.data ?? [];
        final activeBuses = buses.where((b) => b.status == 'Active').length;

        return StreamBuilder<QuerySnapshot>(
          stream: swFirestore.collection('students').snapshots(),
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
                    final markers = <SchoolWayMapMarker>[];
                    final points = <LatLng>[];
                    for (final bus in buses) {
                      final pos = _positionForBus(bus, gpsByBus);
                      if (pos == null) continue;
                      points.add(pos);
                      markers.add(
                        SchoolWayMapMarker(
                          id: 'fleet-bus-${bus.id}',
                          latitude: pos.latitude,
                          longitude: pos.longitude,
                          width: 90,
                          height: 72,
                          alignment: Alignment.bottomCenter,
                          child: buildFleetBusMarkerWidget(
                            busId: bus.id,
                            busLabel: bus.busNumber,
                          ),
                        ),
                      );
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
                        RouteSession? selectedSession;
                        if (_selectedBusId != null) {
                          for (final s
                              in sessionSnap.data ?? const <RouteSession>[]) {
                            if (s.busId == _selectedBusId) {
                              tripDirForSelected = s.tripDirection;
                              selectedSession = s;
                              break;
                            }
                          }
                        }
                        if (_trafficEtaSessionId != selectedSession?.id) {
                          _trafficEtaSessionId = selectedSession?.id;
                          if (selectedSession != null) {
                            _trafficEta.start(selectedSession.id);
                          } else {
                            _trafficEta.stop();
                          }
                        }

                        SchoolWayMapPolyline? selectedGoogleRoutePolyline;
                        var selectedRouteMissingGeometry = false;
                        final selectedStopMarkers = <SchoolWayMapMarker>[];
                        if (_selectedBusId != null) {
                          final selectedMatches = buses.where(
                            (b) => b.id == _selectedBusId,
                          );
                          final selectedBus = selectedMatches.isEmpty
                              ? null
                              : selectedMatches.first;
                          final routeId = selectedBus?.assignedRouteId;
                          if (routeId != null && routeId.trim().isNotEmpty) {
                            final planned = plannedById[routeId];
                            if (planned != null &&
                                planned.editableStops.length >= 2) {
                              final googlePoints = planned
                                  .googleWaypointsForTrip(tripDirForSelected);
                              if (googlePoints.length >= 2) {
                                selectedGoogleRoutePolyline =
                                    SchoolWayMapPolyline(
                                      id: 'fleet-selected-route',
                                      points: googlePoints,
                                      strokeWidth: 5,
                                      color: fleetBusAccentColor(
                                        _selectedBusId!,
                                      ).withValues(alpha: 0.75),
                                    );
                              } else {
                                selectedRouteMissingGeometry = true;
                              }
                              final students =
                                  studentSnapshot.data?.docs
                                      .map(Student.fromFirestore)
                                      .toList() ??
                                  const <Student>[];
                              final assignedStops = buildAssignedRouteStops(
                                route: planned,
                                busId: _selectedBusId!,
                                direction: tripDirForSelected,
                                students: students,
                                serviceStopRouteIndices:
                                    selectedSession?.serviceStopRouteIndices ??
                                    const [],
                              );
                              for (final assignedStop in assignedStops) {
                                final stop = assignedStop.waypoint;
                                selectedStopMarkers.add(
                                  SchoolWayMapMarker(
                                    id: 'fleet-stop-$_selectedBusId-${assignedStop.routeStopIndex}',
                                    latitude: stop.latitude,
                                    longitude: stop.longitude,
                                    width: 30,
                                    height: 30,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: SchoolWayTheme.accent,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: SchoolWayTheme.surface,
                                          width: 2,
                                        ),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        '${assignedStop.serviceStopNumber}',
                                        style: TextStyle(
                                          fontFamily: 'Lexend',
                                          color: SchoolWayTheme.surface,
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
                              child: ValueListenableBuilder<TrafficEtaState>(
                                valueListenable: _trafficEta.state,
                                builder: (context, trafficState, _) {
                                  final trafficPolyline =
                                      trafficState.isAvailable &&
                                          trafficState.snapshot != null
                                      ? trafficState.snapshot!.decodeWaypoints()
                                      : const <RouteWaypoint>[];
                                  return SchoolWayMap(
                                    controller: _mapController,
                                    initialCenter: center,
                                    initialZoom: zoom,
                                    markers: [
                                      ...selectedStopMarkers,
                                      ...markers,
                                    ],
                                    polylines: [
                                      ?selectedGoogleRoutePolyline,
                                      if (trafficPolyline.length >= 2)
                                        SchoolWayMapPolyline(
                                          id: 'fleet-traffic-eta',
                                          points: trafficPolyline,
                                          strokeWidth: 5,
                                          color: SchoolWayTheme.violet,
                                        ),
                                    ],
                                    onCameraChanged: (lat, lng, zoom) {
                                      _zoom = zoom;
                                    },
                                  );
                                },
                              ),
                            ),

                            // Traffic ETA status chip — top-left
                            Positioned(
                              top: 8,
                              left: 8,
                              child: ValueListenableBuilder<TrafficEtaState>(
                                valueListenable: _trafficEta.state,
                                builder: (context, state, _) => Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    TrafficEtaChip(state: state),
                                    if (selectedRouteMissingGeometry)
                                      Padding(
                                        padding: EdgeInsets.only(top: 8),
                                        child: RouteGeometryMissingBanner(),
                                      ),
                                  ],
                                ),
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
                                    label: AppLocalizations.of(context).active,
                                    color: SchoolWayTheme.success,
                                  ),
                                  SizedBox(height: 6),
                                  _FleetStatBadge(
                                    icon: Icons.people,
                                    value: '$totalStudents',
                                    label: AppLocalizations.of(
                                      context,
                                    ).students,
                                    color: SchoolWayTheme.primary,
                                  ),
                                  SizedBox(height: 6),
                                  _FleetStatBadge(
                                    icon: Icons.airport_shuttle,
                                    value: '${buses.length}',
                                    label: AppLocalizations.of(context).fleet,
                                    color: SchoolWayTheme.warning,
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
                                    tooltip: AppLocalizations.of(
                                      context,
                                    ).zoomIn,
                                    onPressed: _zoomIn,
                                  ),
                                  SizedBox(height: 8),
                                  _MapControlBtn(
                                    icon: Icons.remove,
                                    tooltip: AppLocalizations.of(
                                      context,
                                    ).zoomOut,
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
                              snapSizes: [0.10, 0.30, 0.75],
                              builder: (context, scrollController) {
                                return Container(
                                  decoration: BoxDecoration(
                                    color: SchoolWayTheme.surface,
                                    borderRadius: BorderRadius.vertical(
                                      top: Radius.circular(20),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: SchoolWayTheme.text26,
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
        SizedBox(height: 48),
        Center(
          child: Column(
            children: [
              Icon(
                Icons.directions_bus_outlined,
                size: 48,
                color: SchoolWayTheme.accent,
              ),
              SizedBox(height: 12),
              Text(
                AppLocalizations.of(context).noBusesInFleet,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 4),
              Text(
                AppLocalizations.of(context).addBusesInBusManagement,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 13,
                  color: SchoolWayTheme.primary,
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
        Text(
          AppLocalizations.of(context).tapABusCardToShowIt,
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 12,
            color: SchoolWayTheme.primary,
          ),
        ),
        SizedBox(height: 10),
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
            color: SchoolWayTheme.muted,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  Widget _buildBusCard(Bus bus, Map<String, GpsTracking> gpsByBus) {
    final statusColor = _getStatusColor(bus.status);
    final fleetAccent = fleetBusAccentColor(bus.id);
    final simulated =
        gpsByBus[bus.id]?.isSimulated ?? bus.lastLocation?.isSimulated ?? false;

    return Material(
      color: SchoolWayTheme.transparent,
      child: InkWell(
        onTap: () => _focusBusOnMap(bus, gpsByBus),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: SchoolWayTheme.surface,
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
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.directions_bus,
                      color: fleetAccent,
                      size: 24,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          bus.busNumber,
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: SchoolWayTheme.navy,
                          ),
                        ),
                        if (bus.currentDriverUid != null)
                          FutureBuilder<Map<String, dynamic>?>(
                            future: FirebaseService.getUserDataByAuthUid(
                              bus.currentDriverUid!,
                            ),
                            builder: (context, driverSnapshot) {
                              final driver = driverSnapshot.data;
                              return Text(
                                driver != null
                                    ? '${driver['firstName'] ?? ''} ${driver['lastName'] ?? ''}'
                                          .trim()
                                    : 'Loading driver...',
                                style: TextStyle(
                                  fontFamily: 'Lexend',
                                  fontSize: 14,
                                  color: SchoolWayTheme.primary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              );
                            },
                          )
                        else
                          Text(
                            AppLocalizations.of(context).noDriverAssigned,
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 14,
                              color: SchoolWayTheme.disabled,
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
              SizedBox(height: 12),
              if (simulated) ...[
                Chip(
                  avatar: Icon(Icons.science_outlined, size: 16),
                  label: Text(
                    AppLocalizations.of(context).simulatedPosition,
                    style: TextStyle(fontFamily: 'Lexend'),
                  ),
                ),
                SizedBox(height: 8),
              ],
              Row(
                children: [
                  Icon(Icons.route, size: 16, color: SchoolWayTheme.accent),
                  SizedBox(width: 4),
                  Text(
                    bus.currentRoute ?? 'No route assigned',
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 14,
                      color: bus.currentRoute != null
                          ? SchoolWayTheme.primary
                          : SchoolWayTheme.disabled,
                      fontStyle: bus.currentRoute != null
                          ? FontStyle.normal
                          : FontStyle.italic,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.airline_seat_recline_normal,
                    size: 16,
                    color: SchoolWayTheme.accent,
                  ),
                  SizedBox(width: 4),
                  StreamBuilder<QuerySnapshot>(
                    stream: swFirestore
                        .collection('students')
                        .where('assignedBusId', isEqualTo: bus.id)
                        .snapshots(),
                    builder: (context, studentsSnapshot) {
                      final count = studentsSnapshot.data?.docs.length ?? 0;
                      return Text(
                        '$count/${bus.capacity} students',
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 12,
                          color: SchoolWayTheme.primary,
                        ),
                      );
                    },
                  ),
                  SizedBox(width: 16),
                  Icon(Icons.pin, size: 16, color: SchoolWayTheme.accent),
                  SizedBox(width: 4),
                  Text(
                    bus.licensePlate,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 12,
                      color: SchoolWayTheme.primary,
                    ),
                  ),
                  Spacer(),
                  if (bus.lastLocation != null) ...[
                    Icon(
                      Icons.access_time,
                      size: 16,
                      color: SchoolWayTheme.accent,
                    ),
                    SizedBox(width: 4),
                    Text(
                      _formatTimestamp(bus.lastLocation?.timestamp),
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 12,
                        color: SchoolWayTheme.disabled,
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
        color: SchoolWayTheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: SchoolWayTheme.text.withValues(alpha: 0.12),
            blurRadius: 6,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          SizedBox(width: 5),
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
      color: SchoolWayTheme.surface,
      borderRadius: BorderRadius.circular(12),
      elevation: 2,
      child: IconButton(
        icon: Icon(icon, color: SchoolWayTheme.primary),
        onPressed: onPressed,
        tooltip: tooltip,
      ),
    );
  }
}
