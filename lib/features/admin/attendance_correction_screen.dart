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
          _selectedDate.year, _selectedDate.month, _selectedDate.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final snap = await swFirestore
          .collection('boarding_events')
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('timestamp', isLessThan: Timestamp.fromDate(endOfDay))
          .orderBy('timestamp', descending: true)
          .get();

      final events = snap.docs.map((d) => BoardingEvent.fromFirestore(d)).toList();

      if (mounted) {
        setState(() {
          _events = events;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading events: $e')),
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
        title: const Text('Delete Record', style: TextStyle(fontFamily: 'Lexend')),
        content: const Text('Are you sure you want to delete this boarding record? This action cannot be undone.', style: TextStyle(fontFamily: 'Lexend')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(fontFamily: 'Lexend')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(fontFamily: 'Lexend', color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await swFirestore.collection('boarding_events').doc(event.id).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Record deleted successfully.')),
        );
        _loadEvents();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete record: $e')),
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
          title: const Text('Edit Record', style: TextStyle(fontFamily: 'Lexend')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Select new event type:', style: TextStyle(fontFamily: 'Lexend')),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('board'),
                      selected: newType == 'board',
                      onSelected: (val) {
                        if (val) setDialogState(() => newType = 'board');
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('alight'),
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
              child: const Text('Cancel', style: TextStyle(fontFamily: 'Lexend')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save', style: TextStyle(fontFamily: 'Lexend')),
            ),
          ],
        ),
      ),
    );

    if (result == true && newType != event.eventType) {
      try {
        await swFirestore
            .collection('boarding_events')
            .doc(event.id)
            .update({'eventType': newType});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Record updated successfully.')),
          );
          _loadEvents();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to update record: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFCAF0F8),
      appBar: AppBar(
        title: const Text(
          'Attendance Corrections',
          style: TextStyle(
            fontFamily: 'Lexend',
            color: Color(0xFF03045E),
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: const Color(0xFFCAF0F8),
        iconTheme: const IconThemeData(color: Color(0xFF03045E)),
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
                      hintText: 'Filter events...',
                      hintStyle: const TextStyle(fontFamily: 'Lexend'),
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: const BorderSide(color: Color(0xFFE4E9F0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: const BorderSide(color: Color(0xFFE4E9F0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: const BorderSide(color: Color(0xFF03045E)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                InkWell(
                  onTap: () => _selectDate(context),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0077B6).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_month,
                            color: Color(0xFF0077B6), size: 20),
                        const SizedBox(width: 8),
                        Text(
                          '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                          style: const TextStyle(
                            fontFamily: 'Lexend',
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF0077B6),
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
                ? const Center(child: CircularProgressIndicator())
                : _events.isEmpty
                    ? const Center(
                        child: Text(
                          'No boarding events found for this date.',
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            color: Colors.grey,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _events.length,
                        itemBuilder: (context, index) {
                          final event = _events[index];
                          final isBoarding = event.eventType == 'board' || event.eventType == 'boarded';
                          
                          // Very basic filtering since we'd need to resolve students to filter by name.
                          // Realistically, you'd want to join this data or pre-fetch it, but for demo:
                          if (_searchQuery.isNotEmpty && !event.eventType.toLowerCase().contains(_searchQuery)) {
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

                              if (_searchQuery.isNotEmpty && !studentName.toLowerCase().contains(_searchQuery) && !event.eventType.toLowerCase().contains(_searchQuery)) {
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
                                          color: (isBoarding ? Colors.green : Colors.orange).withValues(alpha: 0.1),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          isBoarding ? Icons.login : Icons.logout,
                                          color: isBoarding ? Colors.green : Colors.orange,
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              studentName,
                                              style: const TextStyle(
                                                fontFamily: 'Lexend',
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '${event.eventType.toUpperCase()} at ${_formatTime(event.timestamp)}',
                                              style: TextStyle(
                                                fontFamily: 'Lexend',
                                                color: Colors.grey[600],
                                                fontSize: 13,
                                              ),
                                            ),
                                            if (event.manualNote != null && event.manualNote!.isNotEmpty) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                'Note: ${event.manualNote}',
                                                style: const TextStyle(
                                                  fontFamily: 'Lexend',
                                                  color: Colors.blueGrey,
                                                  fontSize: 12,
                                                  fontStyle: FontStyle.italic,
                                                ),
                                              ),
                                            ]
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.edit, color: Colors.blue),
                                        onPressed: () => _editEvent(event),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete, color: Colors.red),
                                        onPressed: () => _deleteEvent(event),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }
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
