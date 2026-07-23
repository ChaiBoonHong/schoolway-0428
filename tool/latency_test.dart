import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:schoolway/core/schoolway_firestore.dart';

/// A utility to measure the round-trip latency of Firestore writes and reads.
/// Run this in a test environment or during a real route to ensure the parent
/// app meets the real-time latency requirements.
Future<void> runLatencyTest() async {
  debugPrint('--- Starting Firestore Latency Test ---');

  if (Firebase.apps.isEmpty) {
    debugPrint('Firebase not initialized. Initialize Firebase first.');
    return;
  }

  final testDoc = swFirestore.collection('latency_tests').doc('test_node');
  final latencies = <int>[];
  const testCount = 5;

  for (int i = 0; i < testCount; i++) {
    final start = DateTime.now();
    await testDoc.set({
      'timestamp': FieldValue.serverTimestamp(),
      'test_id': i,
    });
    
    // Listen for the update
    final snapshot = await testDoc.get();
    final end = DateTime.now();
    
    if (snapshot.exists) {
       final diff = end.difference(start).inMilliseconds;
       latencies.add(diff);
       debugPrint('Test $i: $diff ms');
    }
    
    await Future.delayed(const Duration(seconds: 1));
  }

  if (latencies.isNotEmpty) {
    latencies.sort();
    final median = latencies[latencies.length ~/ 2];
    final maxLatency = latencies.last;
    final minLatency = latencies.first;
    debugPrint('--- Latency Test Results ---');
    debugPrint('Min: $minLatency ms');
    debugPrint('Max: $maxLatency ms');
    debugPrint('Median: $median ms');
  }
}
