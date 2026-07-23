import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:schoolway/models/models.dart';
import 'package:schoolway/services/firebase_service.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// In-app notification inbox (boarding events, system messages).
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

  void _closeInboxAndRun(BuildContext context, VoidCallback? action) {
    if (action == null) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      Future<void>.microtask(action);
      return;
    }
    action();
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(
        body: Center(
          child: Text('Please sign in', style: TextStyle(fontFamily: 'Lexend')),
        ),
      );
    }

    return StreamBuilder<List<InAppNotification>>(
      stream: FirebaseService.notificationsForAuthUid(uid),
      builder: (context, snap) {
        final list = snap.hasData ? snap.data! : const <InAppNotification>[];
        final unread = list.where((n) => !n.read).length;

        return Scaffold(
          backgroundColor: const Color(0xFFCAF0F8),
          appBar: AppBar(
            title: const Text(
              'Notifications',
              style: TextStyle(
                fontFamily: 'Lexend',
                fontWeight: FontWeight.w600,
                color: Color(0xFF03045E),
              ),
            ),
            backgroundColor: const Color(0xFFCAF0F8),
            elevation: 0,
            foregroundColor: const Color(0xFF03045E),
            actions: [
              if (_markingAll)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF0077B6),
                      ),
                    ),
                  ),
                )
              else if (unread > 0 && snap.hasData)
                TextButton(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    setState(() => _markingAll = true);
                    try {
                      await FirebaseService.markAllNotificationsReadForUser(uid);
                      if (!mounted) return;
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text(
                            'All notifications marked as read',
                            style: TextStyle(fontFamily: 'Lexend'),
                          ),
                        ),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            '$e',
                            style: const TextStyle(fontFamily: 'Lexend'),
                          ),
                          backgroundColor: Colors.red,
                        ),
                      );
                    } finally {
                      if (mounted) {
                        setState(() => _markingAll = false);
                      }
                    }
                  },
                  child: const Text(
                    'Mark all read',
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0077B6),
                    ),
                  ),
                ),
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
    if (snap.hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '${snap.error}',
            style: const TextStyle(fontFamily: 'Lexend'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (!snap.hasData) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF0077B6)),
      );
    }
    if (list.isEmpty) {
      return const Center(
        child: Text(
          'No notifications yet.\nYou’ll see alerts when your child boards or leaves the bus.',
          textAlign: TextAlign.center,
          style: TextStyle(fontFamily: 'Lexend', height: 1.4),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final n = list[i];
        return Material(
          color: n.read ? Colors.white : const Color(0xFFE3F2FD),
          borderRadius: BorderRadius.circular(12),
          child: ListTile(
            title: Text(
              n.title,
              style: const TextStyle(
                fontFamily: 'Lexend',
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              n.body,
              style: const TextStyle(fontFamily: 'Lexend', fontSize: 14),
            ),
            trailing: Text(
              DateFormat.MMMd().add_jm().format(n.createdAt),
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade700,
                fontFamily: 'Lexend',
              ),
            ),
            onTap: () {
              if (!n.read) {
                FirebaseService.markNotificationRead(n.id);
              }
              if (n.type == 'emergency') {
                _closeInboxAndRun(context, widget.onEmergencyTapOpenLiveMap);
                return;
              }
              if (n.type == 'boarding') {
                if (n.studentId != null && n.studentId!.isNotEmpty) {
                  _closeInboxAndRun(
                    context,
                    () => widget.onBoardingTapOpenTripHistory?.call(n.studentId!),
                  );
                } else {
                  _closeInboxAndRun(context, null);
                }
              }
            },
          ),
        ).animate(delay: (i * 30).ms).fade(duration: 300.ms).slideY(begin: 0.1, end: 0, curve: Curves.easeOut);
      },
    );
  }
}
