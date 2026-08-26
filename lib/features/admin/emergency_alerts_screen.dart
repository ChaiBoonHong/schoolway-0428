import 'package:schoolway/l10n/app_localizations.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:schoolway/core/diagnostics/error_reporter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:schoolway/core/widgets/emergency_alert_map_dialog.dart';
import 'package:schoolway/models/models.dart';
import 'package:schoolway/services/firebase_service.dart';

/// Lists active emergency alerts from drivers and allows resolving them.
class EmergencyAlertsScreen extends StatelessWidget {
  const EmergencyAlertsScreen({super.key});

  void _showNotifiedParents(BuildContext context, EmergencyAlert alert) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.of(context).parentsNotified,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 8),
              ...alert.notifiedParents.map(
                (parent) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(child: Icon(Icons.person)),
                  title: Text(
                    parent.name.isEmpty ? parent.username : parent.name,
                    style: TextStyle(fontFamily: 'Lexend'),
                  ),
                  subtitle: parent.name.isEmpty
                      ? null
                      : Text(
                          parent.username,
                          style: TextStyle(fontFamily: 'Lexend'),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openMap(BuildContext context, EmergencyAlert alert) {
    showEmergencyAlertMapDialog(context, alert.location);
  }

  Future<void> _resolve(BuildContext context, EmergencyAlert alert) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseService.resolveEmergencyAlert(alert.id, uid);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).markedResolved,
              style: TextStyle(fontFamily: 'Lexend'),
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ErrorReporter.userMessage(
                context,
                e,
                StackTrace.current,
                category: 'emergency',
                message: 'Emergency alert operation failed.',
              ),
              style: TextStyle(fontFamily: 'Lexend'),
            ),
            backgroundColor: SchoolWayTheme.danger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SchoolWayTheme.background,
      appBar: AppBar(
        title: Text(
          AppLocalizations.of(context).emergencyAlerts,
          style: TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w600,
            color: SchoolWayTheme.navy,
          ),
        ),
        backgroundColor: SchoolWayTheme.background,
        elevation: 0,
        foregroundColor: SchoolWayTheme.navy,
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
                  style: TextStyle(fontFamily: 'Lexend'),
                ),
              ),
            );
          }
          if (!snap.hasData) {
            return Center(
              child: CircularProgressIndicator(color: SchoolWayTheme.primary),
            );
          }
          final alerts = snap.data!;
          if (alerts.isEmpty) {
            return Center(
              child: Text(
                AppLocalizations.of(context).noActiveEmergencyAlerts,
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
                          Icon(
                            Icons.warning_amber_rounded,
                            color: SchoolWayTheme.danger,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: FutureBuilder<Bus?>(
                              future: FirebaseService.getBusById(a.busId),
                              builder: (context, busSnap) {
                                final label =
                                    busSnap.data?.busNumber ?? a.busId;
                                return Text(
                                  'Bus $label',
                                  style: TextStyle(
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
                      SizedBox(height: 8),
                      Text(
                        DateFormat.yMMMd().add_jm().format(a.timestamp),
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 13,
                          color: SchoolWayTheme.muted,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Location: ${a.location.latitude.toStringAsFixed(5)}, ${a.location.longitude.toStringAsFixed(5)}',
                        style: TextStyle(fontFamily: 'Lexend', fontSize: 13),
                      ),
                      SizedBox(height: 4),
                      TextButton.icon(
                        onPressed: a.notifiedParents.isEmpty
                            ? null
                            : () => _showNotifiedParents(context, a),
                        icon: Icon(Icons.people_outline, size: 18),
                        label: Text(
                          'Parents notified: ${a.parentsNotifiedCount}',
                          style: TextStyle(fontFamily: 'Lexend'),
                        ),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      SizedBox(height: 12),
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        runSpacing: 8,
                        spacing: 8,
                        children: [
                          TextButton.icon(
                            onPressed: () => _openMap(context, a),
                            icon: Icon(Icons.map_outlined, size: 20),
                            label: Text(
                              AppLocalizations.of(context).openInMaps,
                              style: TextStyle(fontFamily: 'Lexend'),
                            ),
                          ),
                          FilledButton(
                            onPressed: () => _resolve(context, a),
                            style: FilledButton.styleFrom(
                              backgroundColor: SchoolWayTheme.navy,
                            ),
                            child: Text(
                              AppLocalizations.of(context).resolve,
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
