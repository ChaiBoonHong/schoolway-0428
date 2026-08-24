import 'package:schoolway/l10n/app_localizations.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:schoolway/models/models.dart';
import 'package:schoolway/services/firebase_service.dart';
import 'package:schoolway/features/admin/route_history_map_viewer.dart';

class AdminRouteHistoryScreen extends StatefulWidget {
  const AdminRouteHistoryScreen({super.key});

  @override
  State<AdminRouteHistoryScreen> createState() =>
      _AdminRouteHistoryScreenState();
}

class _AdminRouteHistoryScreenState extends State<AdminRouteHistoryScreen> {
  late Stream<List<RouteSession>> _sessionsStream;
  final Map<String, Bus> _buses = {};
  final Map<String, PlannedRoute> _routes = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    setState(() {
      _sessionsStream = FirebaseService.getCompletedSessions();
    });

    // Fetch lookup data
    FirebaseService.getBuses().first.then((buses) {
      if (mounted) {
        setState(() {
          for (final b in buses) {
            _buses[b.id] = b;
          }
        });
      }
    });
    FirebaseService.getPlannedRoutes().first.then((routes) {
      if (mounted) {
        setState(() {
          for (final r in routes) {
            _routes[r.id] = r;
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SchoolWayTheme.background,
      appBar: AppBar(
        backgroundColor: SchoolWayTheme.background,
        elevation: 0,
        foregroundColor: SchoolWayTheme.navy,
        title: Text(
          AppLocalizations.of(context).routeHistory,
          style: TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w600,
            color: SchoolWayTheme.navy,
          ),
        ),
      ),
      body: StreamBuilder<List<RouteSession>>(
        stream: _sessionsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error loading history: ${snapshot.error}',
                style: TextStyle(fontFamily: 'Lexend'),
              ),
            );
          }
          final sessions = snapshot.data ?? [];
          if (sessions.isEmpty) {
            return Center(
              child: Text(
                AppLocalizations.of(context).noCompletedRoutesFound,
                style: TextStyle(fontFamily: 'Lexend'),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: sessions.length,
            itemBuilder: (context, index) {
              final session = sessions[index];
              final bus = _buses[session.busId];
              final route = session.routeId != null
                  ? _routes[session.routeId!]
                  : null;

              final busName = bus?.busNumber ?? 'Unknown Bus';
              final driverName =
                  session.driverUid; // We don't have driver name lookup
              final routeName = route?.name ?? 'Custom Route';

              final dateFormat = DateFormat('MMM d, y, h:mm a');
              final startStr = dateFormat.format(session.startTime);
              final duration = session.endTime != null
                  ? session.endTime!.difference(session.startTime)
                  : Duration.zero;

              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => RouteHistoryMapViewer(
                          session: session,
                          bus: bus,
                          route: route,
                        ),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: SchoolWayTheme.primary.withValues(
                                  alpha: 0.1,
                                ),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.history,
                                color: SchoolWayTheme.primary,
                              ),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    routeName,
                                    style: TextStyle(
                                      fontFamily: 'Lexend',
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: SchoolWayTheme.navy,
                                    ),
                                  ),
                                  Text(
                                    startStr,
                                    style: TextStyle(
                                      fontFamily: 'Lexend',
                                      color: SchoolWayTheme.primary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(
                              Icons.directions_bus,
                              size: 16,
                              color: SchoolWayTheme.muted,
                            ),
                            SizedBox(width: 4),
                            Text(
                              busName,
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                color: SchoolWayTheme.muted,
                              ),
                            ),
                            SizedBox(width: 16),
                            Icon(
                              Icons.person,
                              size: 16,
                              color: SchoolWayTheme.muted,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Driver: $driverName',
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                color: SchoolWayTheme.muted,
                              ),
                            ),
                            SizedBox(width: 16),
                            Icon(
                              Icons.timer,
                              size: 16,
                              color: SchoolWayTheme.muted,
                            ),
                            SizedBox(width: 4),
                            Text(
                              '${duration.inMinutes}m',
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                color: SchoolWayTheme.muted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
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
