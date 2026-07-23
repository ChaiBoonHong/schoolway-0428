import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:schoolway/models/models.dart';
import 'package:schoolway/services/firebase_service.dart';

class NotificationPrefsScreen extends StatefulWidget {
  const NotificationPrefsScreen({super.key});

  @override
  State<NotificationPrefsScreen> createState() => _NotificationPrefsScreenState();
}

class _NotificationPrefsScreenState extends State<NotificationPrefsScreen> {
  bool _quietHoursEnabled = false;
  TimeOfDay _quietStart = const TimeOfDay(hour: 22, minute: 0);
  TimeOfDay _quietEnd = const TimeOfDay(hour: 6, minute: 0);

  // Map of studentId -> { type -> bool }
  final Map<String, Map<String, bool>> _studentPrefs = {};
  
  bool _isLoading = true;
  String? _uid;
  List<Student> _children = [];

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid;
    if (_uid != null) {
      _loadData();
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    // Fetch children
    final username = await FirebaseService.getUsernameFromAuthUid(_uid!);
    if (username != null) {
      final snap = await FirebaseService.studentsCollection
          .where('parentIds', arrayContains: username)
          .get();
      _children = snap.docs.map((d) => Student.fromFirestore(d)).toList();
    }

    // Initialize defaults
    for (var child in _children) {
      _studentPrefs[child.id] = {
        'boarding': true,
        'dropoff': true,
        'delay': true,
        'route_change': true,
        'emergency': true,
      };
    }

    // Load from Firestore
    try {
      final prefsDoc = await FirebaseService.usersCollection
          .doc(_uid)
          .collection('notification_prefs')
          .doc('settings')
          .get();
          
      if (prefsDoc.exists) {
        final data = prefsDoc.data()!;
        _quietHoursEnabled = data['quietHoursEnabled'] ?? false;
        
        final startMap = data['quietStart'] as Map<String, dynamic>?;
        if (startMap != null) {
          _quietStart = TimeOfDay(hour: startMap['hour'] ?? 22, minute: startMap['minute'] ?? 0);
        }
        
        final endMap = data['quietEnd'] as Map<String, dynamic>?;
        if (endMap != null) {
          _quietEnd = TimeOfDay(hour: endMap['hour'] ?? 6, minute: endMap['minute'] ?? 0);
        }

        final studentsMap = data['students'] as Map<String, dynamic>?;
        if (studentsMap != null) {
          for (var child in _children) {
            if (studentsMap.containsKey(child.id)) {
              final sPrefs = studentsMap[child.id] as Map<String, dynamic>;
              _studentPrefs[child.id] = {
                'boarding': sPrefs['boarding'] ?? true,
                'dropoff': sPrefs['dropoff'] ?? true,
                'delay': sPrefs['delay'] ?? true,
                'route_change': sPrefs['route_change'] ?? true,
                'emergency': sPrefs['emergency'] ?? true,
              };
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading prefs: $e');
    }

    setState(() => _isLoading = false);
  }

  Future<void> _savePrefs() async {
    if (_uid == null) return;
    
    final data = {
      'quietHoursEnabled': _quietHoursEnabled,
      'quietStart': {'hour': _quietStart.hour, 'minute': _quietStart.minute},
      'quietEnd': {'hour': _quietEnd.hour, 'minute': _quietEnd.minute},
      'students': _studentPrefs,
    };

    try {
      await FirebaseService.usersCollection
          .doc(_uid)
          .collection('notification_prefs')
          .doc('settings')
          .set(data, SetOptions(merge: true));
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Preferences saved successfully.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    }
  }

  Future<void> _pickTime(bool isStart) async {
    final initialTime = isStart ? _quietStart : _quietEnd;
    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _quietStart = picked;
        } else {
          _quietEnd = picked;
        }
      });
      _savePrefs();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        title: const Text(
          'Notification Preferences',
          style: TextStyle(
            fontFamily: 'Lexend',
            color: Color(0xFF03045E),
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Color(0xFF03045E)),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionHeader('Quiet Hours'),
          _buildSwitchTile(
            title: 'Enable Quiet Hours',
            subtitle: 'Mute non-emergency notifications during these hours.',
            value: _quietHoursEnabled,
            onChanged: (val) {
              setState(() => _quietHoursEnabled = val);
              _savePrefs();
            },
          ),
          if (_quietHoursEnabled) ...[
            ListTile(
              title: const Text('Start Time', style: TextStyle(fontFamily: 'Lexend')),
              trailing: Text(_quietStart.format(context), style: const TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.bold, color: Color(0xFF0077B6))),
              onTap: () => _pickTime(true),
            ),
            ListTile(
              title: const Text('End Time', style: TextStyle(fontFamily: 'Lexend')),
              trailing: Text(_quietEnd.format(context), style: const TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.bold, color: Color(0xFF0077B6))),
              onTap: () => _pickTime(false),
            ),
          ],
          const SizedBox(height: 24),
          
          if (_children.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'No children found to manage preferences.',
                style: TextStyle(fontFamily: 'Lexend', color: Colors.grey),
              ),
            ),
            
          for (var child in _children) ...[
            _buildSectionHeader('${child.firstName} ${child.lastName}'),
            _buildChildPrefTile(child.id, 'boarding', 'Boarding', 'When child boards the bus'),
            _buildChildPrefTile(child.id, 'dropoff', 'Drop-off', 'When child leaves the bus'),
            _buildChildPrefTile(child.id, 'delay', 'Delay', 'Route delays & ETA changes'),
            _buildChildPrefTile(child.id, 'route_change', 'Route Change', 'Bus re-assignments'),
            _buildChildPrefTile(child.id, 'emergency', 'Emergency', 'Critical alerts from driver'),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontFamily: 'Lexend',
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.grey.shade600,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildChildPrefTile(String studentId, String key, String title, String subtitle) {
    final value = _studentPrefs[studentId]?[key] ?? true;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: SwitchListTile(
        title: Text(title, style: const TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(subtitle, style: const TextStyle(fontFamily: 'Lexend', fontSize: 12)),
        value: value,
        onChanged: (val) {
          setState(() {
            _studentPrefs[studentId]![key] = val;
          });
          _savePrefs();
        },
        activeThumbColor: const Color(0xFF0077B6),
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SwitchListTile(
        title: Text(title, style: const TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: const TextStyle(fontFamily: 'Lexend', fontSize: 13)),
        value: value,
        onChanged: onChanged,
        activeThumbColor: const Color(0xFF0077B6),
      ),
    );
  }
}
