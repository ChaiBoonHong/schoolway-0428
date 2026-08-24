import 'package:schoolway/l10n/app_localizations.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:schoolway/models/models.dart';
import 'package:schoolway/services/firebase_service.dart';

class ParentChildrenTab extends StatelessWidget {
  const ParentChildrenTab({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // My Children Section
          if (currentUserId != null) ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: SchoolWayTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: SchoolWayTheme.accent.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.family_restroom,
                        color: SchoolWayTheme.accent,
                        size: 24,
                      ),
                      SizedBox(width: 8),
                      Text(
                        AppLocalizations.of(context).myChildren,
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontWeight: FontWeight.w600,
                          fontSize: 18,
                          color: SchoolWayTheme.navy,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  StreamBuilder<List<Student>>(
                    stream: FirebaseService.getStudentsByParentAuthUid(
                      currentUserId,
                    ),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return Center(
                          child: Padding(
                            padding: EdgeInsets.all(16.0),
                            child: CircularProgressIndicator(
                              color: SchoolWayTheme.primary,
                            ),
                          ),
                        );
                      }

                      if (snapshot.hasError) {
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: SchoolWayTheme.danger.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Error loading children: ${snapshot.error}',
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              color: SchoolWayTheme.danger,
                              fontSize: 14,
                            ),
                          ),
                        );
                      }

                      final students = snapshot.data ?? [];

                      if (students.isEmpty) {
                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: SchoolWayTheme.accent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              AppLocalizations.of(
                                context,
                              ).noChildrenAssignedYetContactKindergartenAdmin,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                color: SchoolWayTheme.primary,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        );
                      }

                      return Column(
                        children: students.map((student) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: SchoolWayTheme.background,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: SchoolWayTheme.primary.withValues(
                                  alpha: 0.3,
                                ),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: SchoolWayTheme.primary,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Center(
                                        child: Text(
                                          '${student.firstName[0]}${student.lastName[0]}',
                                          style: TextStyle(
                                            fontFamily: 'Lexend',
                                            color: SchoolWayTheme.surface,
                                            fontSize: 18,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${student.firstName} ${student.lastName}',
                                            style: TextStyle(
                                              fontFamily: 'Lexend',
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: SchoolWayTheme.navy,
                                            ),
                                          ),
                                          SizedBox(height: 4),
                                          Text(
                                            'Student ID: ${student.studentId}',
                                            style: TextStyle(
                                              fontFamily: 'Lexend',
                                              fontSize: 14,
                                              color: SchoolWayTheme.primary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    _LiveStatusBadge(status: student.status),
                                  ],
                                ),
                                if (student.assignedBusId != null ||
                                    student.pickupStop != null) ...[
                                  SizedBox(height: 12),
                                  Divider(height: 1),
                                  SizedBox(height: 12),
                                  if (student.assignedBusId != null)
                                    _StudentInfoRow(
                                      icon: Icons.directions_bus,
                                      label: AppLocalizations.of(
                                        context,
                                      ).assignedBus,
                                      value: student.assignedBusId!,
                                    ),
                                  if (student.pickupStop != null) ...[
                                    SizedBox(height: 8),
                                    _StudentInfoRow(
                                      icon: Icons.location_on,
                                      label: AppLocalizations.of(
                                        context,
                                      ).assignedStop,
                                      value: student.pickupStop!,
                                    ),
                                  ],
                                ],
                              ],
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
              ),
            ),
            SizedBox(height: 24),
          ],
        ],
      ),
    );
  }
}

class _StudentInfoRow extends StatelessWidget {
  const _StudentInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: SchoolWayTheme.primary),
        SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(
            fontFamily: 'Lexend',
            fontSize: 13,
            color: SchoolWayTheme.primary,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: SchoolWayTheme.navy,
            ),
          ),
        ),
      ],
    );
  }
}

class _LiveStatusBadge extends StatefulWidget {
  final String status;

  const _LiveStatusBadge({required this.status});

  @override
  State<_LiveStatusBadge> createState() => _LiveStatusBadgeState();
}

class _LiveStatusBadgeState extends State<_LiveStatusBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 1500),
    );
    if (widget.status == 'Active') {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(_LiveStatusBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.status == 'Active' && oldWidget.status != 'Active') {
      _pulseController.repeat(reverse: true);
    } else if (widget.status != 'Active' && oldWidget.status == 'Active') {
      _pulseController.stop();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isActive = widget.status == 'Active';
    final color = isActive ? SchoolWayTheme.success : SchoolWayTheme.muted;

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final scale = isActive ? 1.0 + _pulseController.value * 0.05 : 1.0;
        final opacity = isActive ? 0.1 + _pulseController.value * 0.15 : 0.1;

        return Transform.scale(
          scale: scale,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: opacity),
              borderRadius: BorderRadius.circular(12),
              border: isActive
                  ? Border.all(color: color.withValues(alpha: 0.3))
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isActive) ...[
                  Icon(Icons.circle, color: color, size: 8),
                  SizedBox(width: 6),
                ],
                Text(
                  widget.status,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
