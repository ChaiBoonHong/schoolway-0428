import 'package:schoolway/l10n/app_localizations.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:schoolway/core/diagnostics/error_reporter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:schoolway/core/schoolway_firestore.dart';
import 'package:schoolway/models/models.dart';
import 'package:schoolway/services/firebase_service.dart';

class AttendanceCorrectionScreen extends StatefulWidget {
  const AttendanceCorrectionScreen({super.key});

  @override
  State<AttendanceCorrectionScreen> createState() =>
      _AttendanceCorrectionScreenState();
}

class _AttendanceCorrectionScreenState
    extends State<AttendanceCorrectionScreen> {
  DateTime _selectedDate = DateTime.now();
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  List<BoardingEvent> _events = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      _loadEvents();
    }
  }

  Future<void> _loadEvents() async {
    setState(() => _isLoading = true);
    try {
      final startOfDay = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
      );
      final endOfDay = startOfDay.add(Duration(days: 1));

      final snap = await swFirestore
          .collection('boarding_events')
          .where(
            'timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
          )
          .where('timestamp', isLessThan: Timestamp.fromDate(endOfDay))
          .orderBy('timestamp', descending: true)
          .get();

      final events = snap.docs
          .map((d) => BoardingEvent.fromFirestore(d))
          .toList();

      if (mounted) {
        setState(() {
          _events = events;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ErrorReporter.userMessage(
                context,
                e,
                StackTrace.current,
                category: 'attendance',
                message: 'Attendance events failed to load.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _deleteEvent(BoardingEvent event) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          AppLocalizations.of(context).deleteRecord,
          style: TextStyle(fontFamily: 'Lexend'),
        ),
        content: Text(
          AppLocalizations.of(context).areYouSureYouWantToDelete,
          style: TextStyle(fontFamily: 'Lexend'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              AppLocalizations.of(context).cancel,
              style: TextStyle(fontFamily: 'Lexend'),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: SchoolWayTheme.danger,
            ),
            child: Text(
              AppLocalizations.of(context).delete,
              style: TextStyle(
                fontFamily: 'Lexend',
                color: SchoolWayTheme.surface,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await swFirestore.collection('boarding_events').doc(event.id).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).recordDeletedSuccessfully,
            ),
          ),
        );
        _loadEvents();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ErrorReporter.userMessage(
                context,
                e,
                StackTrace.current,
                category: 'attendance',
                message: 'Attendance record deletion failed.',
              ),
            ),
          ),
        );
      }
    }
  }

  Future<void> _editEvent(BoardingEvent event) async {
    String newType = event.eventType;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            AppLocalizations.of(context).editRecord,
            style: TextStyle(fontFamily: 'Lexend'),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppLocalizations.of(context).selectNewEventType,
                style: TextStyle(fontFamily: 'Lexend'),
              ),
              SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: Text(AppLocalizations.of(context).board),
                      selected: newType == 'board',
                      onSelected: (val) {
                        if (val) setDialogState(() => newType = 'board');
                      },
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: Text(AppLocalizations.of(context).alight),
                      selected: newType == 'alight',
                      onSelected: (val) {
                        if (val) setDialogState(() => newType = 'alight');
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                AppLocalizations.of(context).cancel,
                style: TextStyle(fontFamily: 'Lexend'),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                AppLocalizations.of(context).save,
                style: TextStyle(fontFamily: 'Lexend'),
              ),
            ),
          ],
        ),
      ),
    );

    if (result == true && newType != event.eventType) {
      try {
        await swFirestore.collection('boarding_events').doc(event.id).update({
          'eventType': newType,
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context).recordUpdatedSuccessfully,
              ),
            ),
          );
          _loadEvents();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                ErrorReporter.userMessage(
                  context,
                  e,
                  StackTrace.current,
                  category: 'attendance',
                  message: 'Attendance record update failed.',
                ),
              ),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).attendanceCorrections),
        elevation: 0,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) {
                      setState(() {
                        _searchQuery = val.toLowerCase();
                      });
                    },
                    decoration: InputDecoration(
                      hintText: AppLocalizations.of(context).filterEvents,
                      hintStyle: TextStyle(fontFamily: 'Lexend'),
                      prefixIcon: Icon(Icons.search),
                      filled: true,
                      fillColor: SchoolWayTheme.surface,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: SchoolWayTheme.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: SchoolWayTheme.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: SchoolWayTheme.navy),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 12),
                InkWell(
                  onTap: () => _selectDate(context),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: SchoolWayTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.calendar_month,
                          color: SchoolWayTheme.primary,
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Text(
                          '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontWeight: FontWeight.w600,
                            color: SchoolWayTheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator())
                : _events.isEmpty
                ? Center(
                    child: Text(
                      AppLocalizations.of(
                        context,
                      ).noBoardingEventsFoundForThisDate,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        color: SchoolWayTheme.muted,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _events.length,
                    itemBuilder: (context, index) {
                      final event = _events[index];
                      final isBoarding =
                          event.eventType == 'board' ||
                          event.eventType == 'boarded';

                      // Very basic filtering since we'd need to resolve students to filter by name.
                      // Realistically, you'd want to join this data or pre-fetch it, but for demo:
                      if (_searchQuery.isNotEmpty &&
                          !event.eventType.toLowerCase().contains(
                            _searchQuery,
                          )) {
                        // We'll just show all for now if they type student name unless we do a complex query
                        // Ideally, we resolve student name in a FutureBuilder like driver nfc tab
                      }

                      return FutureBuilder<Student?>(
                        future: FirebaseService.getStudentById(event.studentId),
                        builder: (context, snapshot) {
                          final student = snapshot.data;
                          final studentName = student != null
                              ? '${student.firstName} ${student.lastName}'
                              : 'Unknown Student';

                          if (_searchQuery.isNotEmpty &&
                              !studentName.toLowerCase().contains(
                                _searchQuery,
                              ) &&
                              !event.eventType.toLowerCase().contains(
                                _searchQuery,
                              )) {
                            return const SizedBox.shrink();
                          }

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color:
                                          (isBoarding
                                                  ? SchoolWayTheme.success
                                                  : SchoolWayTheme.warning)
                                              .withValues(alpha: 0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      isBoarding ? Icons.login : Icons.logout,
                                      color: isBoarding
                                          ? SchoolWayTheme.success
                                          : SchoolWayTheme.warning,
                                    ),
                                  ),
                                  SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          studentName,
                                          style: TextStyle(
                                            fontFamily: 'Lexend',
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        SizedBox(height: 4),
                                        Text(
                                          '${event.eventType.toUpperCase()} at ${_formatTime(event.timestamp)}',
                                          style: TextStyle(
                                            fontFamily: 'Lexend',
                                            color: SchoolWayTheme.muted,
                                            fontSize: 13,
                                          ),
                                        ),
                                        if (event.manualNote != null &&
                                            event.manualNote!.isNotEmpty) ...[
                                          SizedBox(height: 4),
                                          Text(
                                            'Note: ${event.manualNote}',
                                            style: TextStyle(
                                              fontFamily: 'Lexend',
                                              color: SchoolWayTheme.blueGrey,
                                              fontSize: 12,
                                              fontStyle: FontStyle.italic,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      Icons.edit,
                                      color: SchoolWayTheme.info,
                                    ),
                                    onPressed: () => _editEvent(event),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      Icons.delete,
                                      color: SchoolWayTheme.danger,
                                    ),
                                    onPressed: () => _deleteEvent(event),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
