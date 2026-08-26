import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:schoolway/core/diagnostics/error_reporter.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:schoolway/core/widgets/emergency_alert_map_dialog.dart';
import 'package:schoolway/l10n/app_localizations.dart';
import 'package:schoolway/models/models.dart';
import 'package:schoolway/services/firebase_service.dart';

/// In-app notification inbox (boarding events, system messages, alerts)
/// organized by date with clear/delete capabilities.
class NotificationsInboxScreen extends StatefulWidget {
  const NotificationsInboxScreen({
    super.key,
    this.onEmergencyTapOpenLiveMap,
    this.onBoardingTapOpenTripHistory,
  });

  final VoidCallback? onEmergencyTapOpenLiveMap;
  final ValueChanged<String>? onBoardingTapOpenTripHistory;

  @override
  State<NotificationsInboxScreen> createState() =>
      _NotificationsInboxScreenState();
}

class _NotificationsInboxScreenState extends State<NotificationsInboxScreen> {
  bool _markingAll = false;
  bool _clearingAll = false;

  void _closeInboxAndRun(BuildContext context, VoidCallback? action) {
    if (action == null) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      Future<void>.microtask(action);
      return;
    }
    action();
  }

  void _openEmergencyMap(BuildContext context, InAppNotification notification) {
    if (!notification.read) {
      FirebaseService.markNotificationRead(notification.id);
    }
    if (notification.location != null) {
      showEmergencyAlertMapDialog(context, notification.location!);
      return;
    }
    _closeInboxAndRun(context, widget.onEmergencyTapOpenLiveMap);
  }

  String _dateGroupTitle(DateTime date, AppLocalizations l10n) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final notificationDate = DateTime(date.year, date.month, date.day);
    final diff = today.difference(notificationDate).inDays;

    if (diff == 0) {
      return l10n.today;
    } else if (diff == 1) {
      return l10n.yesterday;
    } else if (now.year == date.year) {
      return DateFormat('EEEE, d MMMM').format(date);
    } else {
      return DateFormat('d MMMM yyyy').format(date);
    }
  }

  Map<DateTime, List<InAppNotification>> _groupNotificationsByDate(
    List<InAppNotification> list,
  ) {
    final grouped = <DateTime, List<InAppNotification>>{};
    for (final n in list) {
      final dateKey = DateTime(
        n.createdAt.year,
        n.createdAt.month,
        n.createdAt.day,
      );
      grouped.putIfAbsent(dateKey, () => []).add(n);
    }
    return grouped;
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'emergency':
        return Icons.warning_amber_rounded;
      case 'boarding':
        return Icons.login_rounded;
      case 'dropoff':
        return Icons.logout_rounded;
      default:
        return Icons.notifications_outlined;
    }
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'emergency':
        return SchoolWayTheme.danger;
      case 'boarding':
        return SchoolWayTheme.success;
      case 'dropoff':
        return SchoolWayTheme.primary;
      default:
        return SchoolWayTheme.accent;
    }
  }

  Future<void> _confirmClearAll(String uid) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          l10n.clearAllNotificationsConfirmTitle,
          style: const TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          l10n.clearAllNotificationsConfirmBody,
          style: const TextStyle(fontFamily: 'Lexend', height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: SchoolWayTheme.danger,
              foregroundColor: SchoolWayTheme.surface,
            ),
            child: Text(
              l10n.clearAll,
              style: const TextStyle(
                fontFamily: 'Lexend',
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final messenger = ScaffoldMessenger.of(context);
      setState(() => _clearingAll = true);
      try {
        await FirebaseService.clearAllNotificationsForUser(uid);
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              l10n.notificationsCleared,
              style: const TextStyle(fontFamily: 'Lexend'),
            ),
          ),
        );
      } catch (e, st) {
        if (!mounted) return;
        final msg = ErrorReporter.userMessage(
          context,
          e,
          st,
          category: 'notifications',
          message: 'Failed to clear notifications.',
        );
        messenger.showSnackBar(
          SnackBar(
            content: Text(msg, style: const TextStyle(fontFamily: 'Lexend')),
            backgroundColor: SchoolWayTheme.danger,
          ),
        );
      } finally {
        if (mounted) setState(() => _clearingAll = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final l10n = AppLocalizations.of(context);

    if (uid == null) {
      return Scaffold(
        body: Center(
          child: Text(
            l10n.pleaseSignIn,
            style: const TextStyle(fontFamily: 'Lexend'),
          ),
        ),
      );
    }

    return StreamBuilder<List<InAppNotification>>(
      stream: FirebaseService.notificationsForAuthUid(uid),
      builder: (context, snap) {
        final list = snap.hasData ? snap.data! : const <InAppNotification>[];
        final unread = list.where((n) => !n.read).length;

        return Scaffold(
          backgroundColor: SchoolWayTheme.background,
          appBar: AppBar(
            title: Text(
              l10n.notifications,
              style: const TextStyle(
                fontFamily: 'Lexend',
                fontWeight: FontWeight.w600,
                color: SchoolWayTheme.navy,
              ),
            ),
            backgroundColor: SchoolWayTheme.surface,
            elevation: 0,
            foregroundColor: SchoolWayTheme.navy,
            actions: [
              if (_markingAll || _clearingAll)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: SchoolWayTheme.primary,
                      ),
                    ),
                  ),
                )
              else ...[
                if (unread > 0 && snap.hasData)
                  TextButton(
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      setState(() => _markingAll = true);
                      try {
                        await FirebaseService.markAllNotificationsReadForUser(
                          uid,
                        );
                        if (!mounted) return;
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              l10n.allNotificationsMarkedAsRead,
                              style: const TextStyle(fontFamily: 'Lexend'),
                            ),
                          ),
                        );
                      } catch (e, st) {
                        if (!mounted) return;
                        final msg = ErrorReporter.userMessage(
                          this.context,
                          e,
                          st,
                          category: 'notifications',
                          message: 'Failed to mark notifications as read.',
                        );
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              msg,
                              style: const TextStyle(fontFamily: 'Lexend'),
                            ),
                            backgroundColor: SchoolWayTheme.danger,
                          ),
                        );
                      } finally {
                        if (mounted) {
                          setState(() => _markingAll = false);
                        }
                      }
                    },
                    child: Text(
                      l10n.markAllRead,
                      style: const TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w600,
                        color: SchoolWayTheme.primary,
                      ),
                    ),
                  ),
                if (list.isNotEmpty)
                  PopupMenuButton<String>(
                    tooltip: l10n.moreOptionsTooltip,
                    icon: const Icon(
                      Icons.more_vert,
                      color: SchoolWayTheme.navy,
                    ),
                    onSelected: (value) {
                      if (value == 'clear_all') {
                        _confirmClearAll(uid);
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'clear_all',
                        child: Row(
                          children: [
                            const Icon(
                              Icons.delete_sweep_outlined,
                              color: SchoolWayTheme.danger,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              l10n.clearAllNotifications,
                              style: const TextStyle(
                                fontFamily: 'Lexend',
                                color: SchoolWayTheme.danger,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ],
          ),
          body: _buildBody(context, snap, list),
        );
      },
    );
  }

  Widget _buildBody(
    BuildContext context,
    AsyncSnapshot<List<InAppNotification>> snap,
    List<InAppNotification> list,
  ) {
    final l10n = AppLocalizations.of(context);

    if (snap.hasError) {
      final msg = ErrorReporter.userMessage(
        context,
        snap.error!,
        snap.stackTrace ?? StackTrace.current,
        category: 'notifications',
        message: 'Could not load notifications.',
      );
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            msg,
            style: const TextStyle(fontFamily: 'Lexend'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (!snap.hasData) {
      return const Center(
        child: CircularProgressIndicator(color: SchoolWayTheme.primary),
      );
    }
    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.notifications_none_rounded,
                size: 64,
                color: SchoolWayTheme.blueGrey,
              ),
              const SizedBox(height: 16),
              Text(
                l10n.noNotificationsYetYouLlSeeAlerts,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Lexend',
                  height: 1.4,
                  fontSize: 15,
                  color: SchoolWayTheme.blueGrey,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final grouped = _groupNotificationsByDate(list);
    final sortedDates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: sortedDates.length,
      itemBuilder: (context, sectionIndex) {
        final dateKey = sortedDates[sectionIndex];
        final sectionItems = grouped[dateKey]!;
        final headerTitle = _dateGroupTitle(dateKey, l10n);

        return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                  child: Row(
                    children: [
                      Text(
                        headerTitle,
                        style: const TextStyle(
                          fontFamily: 'Lexend',
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: SchoolWayTheme.navy,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: SchoolWayTheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${sectionItems.length}',
                          style: const TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: SchoolWayTheme.primary,
                          ),
                        ),
                      ),
                      const Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(left: 12),
                          child: Divider(
                            color: SchoolWayTheme.border,
                            thickness: 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                ...sectionItems.map((n) {
                  final typeColor = _typeColor(n.type);
                  final typeIcon = _typeIcon(n.type);

                  return Dismissible(
                    key: ValueKey('notification_${n.id}'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: SchoolWayTheme.danger,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            l10n.delete,
                            style: const TextStyle(
                              fontFamily: 'Lexend',
                              color: SchoolWayTheme.surface,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.delete_outline,
                            color: SchoolWayTheme.surface,
                          ),
                        ],
                      ),
                    ),
                    onDismissed: (_) {
                      FirebaseService.deleteNotification(n.id);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            l10n.notificationDeleted,
                            style: const TextStyle(fontFamily: 'Lexend'),
                          ),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Material(
                        color: n.read
                            ? SchoolWayTheme.surface
                            : SchoolWayTheme.infoSurface,
                        borderRadius: BorderRadius.circular(12),
                        elevation: n.read ? 0 : 1,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            if (!n.read) {
                              FirebaseService.markNotificationRead(n.id);
                            }
                            if (n.type == 'emergency') {
                              _openEmergencyMap(context, n);
                              return;
                            }
                            if (n.type == 'boarding' || n.type == 'dropoff') {
                              if (n.studentId != null &&
                                  n.studentId!.isNotEmpty) {
                                _closeInboxAndRun(
                                  context,
                                  () => widget.onBoardingTapOpenTripHistory
                                      ?.call(n.studentId!),
                                );
                              } else {
                                _closeInboxAndRun(context, null);
                              }
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: typeColor.withValues(alpha: 0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    typeIcon,
                                    color: typeColor,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              n.title,
                                              style: TextStyle(
                                                fontFamily: 'Lexend',
                                                fontWeight: n.read
                                                    ? FontWeight.w600
                                                    : FontWeight.bold,
                                                fontSize: 14,
                                                color: SchoolWayTheme.navy,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            DateFormat.jm().format(n.createdAt),
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: SchoolWayTheme.muted,
                                              fontFamily: 'Lexend',
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        n.body,
                                        style: const TextStyle(
                                          fontFamily: 'Lexend',
                                          fontSize: 13,
                                          color: SchoolWayTheme.blueGrey,
                                          height: 1.3,
                                        ),
                                      ),
                                      if (n.type == 'emergency') ...[
                                        const SizedBox(height: 6),
                                        TextButton.icon(
                                          onPressed: () =>
                                              _openEmergencyMap(context, n),
                                          icon: const Icon(
                                            Icons.map_outlined,
                                            size: 16,
                                          ),
                                          label: Text(
                                            l10n.openInMaps,
                                            style: const TextStyle(
                                              fontFamily: 'Lexend',
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          style: TextButton.styleFrom(
                                            padding: EdgeInsets.zero,
                                            minimumSize: const Size(0, 0),
                                            tapTargetSize: MaterialTapTargetSize
                                                .shrinkWrap,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.close,
                                    size: 18,
                                    color: SchoolWayTheme.muted,
                                  ),
                                  tooltip: l10n.delete,
                                  onPressed: () {
                                    FirebaseService.deleteNotification(n.id);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          l10n.notificationDeleted,
                                          style: const TextStyle(
                                            fontFamily: 'Lexend',
                                          ),
                                        ),
                                        duration: const Duration(seconds: 2),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ],
            )
            .animate(delay: (sectionIndex * 40).ms)
            .fade(duration: 250.ms)
            .slideY(begin: 0.05, end: 0, curve: Curves.easeOut);
      },
    );
  }
}
