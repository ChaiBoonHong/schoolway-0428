import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:schoolway/core/map/map_markers.dart';
import 'package:schoolway/core/map/schoolway_map.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:schoolway/core/widgets/route_geometry_missing_banner.dart';
import 'package:schoolway/l10n/app_localizations.dart';
import 'package:schoolway/models/models.dart';

class RouteStopPickerScreen extends StatefulWidget {
  const RouteStopPickerScreen({
    super.key,
    required this.route,
    this.initialStopIndex,
  });

  final PlannedRoute route;
  final int? initialStopIndex;

  @override
  State<RouteStopPickerScreen> createState() => _RouteStopPickerScreenState();
}

class _RouteStopPickerScreenState extends State<RouteStopPickerScreen> {
  int? _selectedStopIndex;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialStopIndex;
    _selectedStopIndex =
        initial != null &&
            initial >= 0 &&
            initial < widget.route.editableStops.length
        ? initial
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final stops = widget.route.editableStops;
    final routePoints = widget.route.googleWaypointsForTrip(
      TripDirection.toSchool,
    );
    final center = stops.isEmpty
        ? const LatLng(3.1390, 101.6869)
        : LatLng(stops.first.latitude, stops.first.longitude);

    return Scaffold(
      appBar: AppBar(title: Text(strings.selectPickupPoint)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              strings.selectPickupPointInstructions,
              style: const TextStyle(fontFamily: 'Lexend'),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                SchoolWayMap(
                  initialCenter: center,
                  initialZoom: 13,
                  markers: [
                    for (var index = 0; index < stops.length; index++)
                      SchoolWayMapMarker(
                        id: 'pickup-stop-$index-${index == _selectedStopIndex}',
                        latitude: stops[index].latitude,
                        longitude: stops[index].longitude,
                        width: 60,
                        height: 48,
                        child: Semantics(
                          button: true,
                          selected: index == _selectedStopIndex,
                          label: strings.pickupPointNumber(index + 1),
                          child: buildStopNumberWidget(number: index + 1),
                        ),
                        onTap: () => setState(() => _selectedStopIndex = index),
                      ),
                  ],
                  polylines: [
                    if (routePoints.length >= 2)
                      SchoolWayMapPolyline(
                        id: 'pickup-route',
                        points: routePoints,
                        strokeWidth: 5,
                        color: SchoolWayTheme.primary,
                      ),
                  ],
                ),
                if (stops.length >= 2 && routePoints.isEmpty)
                  const Positioned(
                    top: 8,
                    left: 8,
                    right: 8,
                    child: RouteGeometryMissingBanner(),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (var index = 0; index < stops.length; index++) ...[
                          ChoiceChip(
                            label: Text(strings.pickupPointNumber(index + 1)),
                            selected: index == _selectedStopIndex,
                            onSelected: (_) =>
                                setState(() => _selectedStopIndex = index),
                          ),
                          if (index != stops.length - 1)
                            const SizedBox(width: 8),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _selectedStopIndex == null
                        ? null
                        : () => Navigator.pop(context, _selectedStopIndex),
                    icon: const Icon(Icons.check),
                    label: Text(strings.confirmPickupPoint),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
