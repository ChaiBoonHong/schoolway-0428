import 'package:flutter/material.dart';
import 'package:schoolway/core/schoolway_firestore.dart';
import 'package:schoolway/models/models.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _activeBusesCount = 0;
  int _totalCheckedIn = 0;
  List<IncidentReport> _recentIncidents = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);

    try {
      // 1. Active Buses Count
      final sessionsSnap = await swFirestore
          .collection('route_sessions')
          .where('endTime', isNull: true)
          .get();
      _activeBusesCount = sessionsSnap.docs.length;

      // 2. Total Checked-in Students (currently on board)
      // This is an approximation: board events minus alight events for active sessions.
      int checkedIn = 0;
      for (var doc in sessionsSnap.docs) {
        final eventsSnap = await swFirestore
            .collection('boarding_events')
            .where('sessionId', isEqualTo: doc.id)
            .get();
        final boardCount = eventsSnap.docs.where((e) => e['eventType'] == 'board').length;
        final alightCount = eventsSnap.docs.where((e) => e['eventType'] == 'alight').length;
        checkedIn += (boardCount - alightCount);
      }
      _totalCheckedIn = checkedIn;

      // 3. Recent Incidents (limit to 5)
      final incidentsSnap = await swFirestore
          .collection('incident_reports')
          .orderBy('timestamp', descending: true)
          .limit(5)
          .get();
      
      _recentIncidents = incidentsSnap.docs
          .map((d) => IncidentReport.fromFirestore(d))
          .toList();

    } catch (e) {
      debugPrint('Error loading dashboard data: $e');
    }

    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        title: const Text(
          'Operational Dashboard',
          style: TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.bold, color: Color(0xFF03045E)),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF03045E)),
            onPressed: _loadDashboardData,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadDashboardData,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildMetricsGrid(),
            const SizedBox(height: 24),
            _buildPerformanceMetric(),
            const SizedBox(height: 24),
            _buildIncidentsSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricsGrid() {
    return Row(
      children: [
        Expanded(
          child: _buildMetricCard(
            title: 'Active Buses',
            value: '$_activeBusesCount',
            icon: Icons.directions_bus,
            color: const Color(0xFF0077B6),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildMetricCard(
            title: 'Students On Board',
            value: '$_totalCheckedIn',
            icon: Icons.groups,
            color: const Color(0xFF4CAF50),
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard({required String title, required String value, required IconData icon, required Color color}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Lexend',
              fontSize: 14,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPerformanceMetric() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF00B4D8), Color(0xFF0077B6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0077B6).withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'On-Time Performance',
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 16,
                  color: Colors.white70,
                ),
              ),
              SizedBox(height: 4),
              Text(
                '94.2%',
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const Icon(Icons.trending_up, color: Colors.white, size: 48),
        ],
      ),
    );
  }

  Widget _buildIncidentsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recent Incidents & Reports',
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF03045E),
          ),
        ),
        const SizedBox(height: 12),
        if (_recentIncidents.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('No recent incidents.', style: TextStyle(color: Colors.grey, fontFamily: 'Lexend')),
          )
        else
          ..._recentIncidents.map((incident) => _buildIncidentTile(incident)),
      ],
    );
  }

  Widget _buildIncidentTile(IncidentReport incident) {
    Color getSeverityColor(String severity) {
      switch (severity.toLowerCase()) {
        case 'high':
          return Colors.red;
        case 'medium':
          return Colors.orange;
        case 'low':
          return Colors.green;
        default:
          return Colors.grey;
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: getSeverityColor(incident.severity).withValues(alpha: 0.2),
          child: Icon(Icons.warning_amber_rounded, color: getSeverityColor(incident.severity)),
        ),
        title: Text(
          incident.category,
          style: const TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(incident.description, style: const TextStyle(fontFamily: 'Lexend', fontSize: 13)),
            const SizedBox(height: 4),
            Text(
              'Bus: ${incident.busId} • ${_formatTime(incident.timestamp)}',
              style: const TextStyle(fontFamily: 'Lexend', fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
           '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
