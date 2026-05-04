import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:schoolway/core/schoolway_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/models.dart';

/// Central Firebase service for all Firestore operations
class FirebaseService {
  static final FirebaseFirestore _firestore = swFirestore;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  // Collection references
  static CollectionReference get usersCollection => _firestore.collection('users');
  static CollectionReference get busesCollection => _firestore.collection('buses');
  static CollectionReference get studentsCollection => _firestore.collection('students');
  static CollectionReference get boardingEventsCollection => _firestore.collection('boarding_events');
  static CollectionReference get routeSessionsCollection => _firestore.collection('route_sessions');
  static CollectionReference get gpsTrackingCollection => _firestore.collection('gps_tracking');
  static CollectionReference get emergencyAlertsCollection => _firestore.collection('emergency_alerts');
  static CollectionReference get notificationsCollection => _firestore.collection('notifications');
  static CollectionReference get plannedRoutesCollection => _firestore.collection('planned_routes');

  // Current user
  static User? get currentUser => _auth.currentUser;
  static String? get currentUserId => _auth.currentUser?.uid;

  // ==================== BUS OPERATIONS ====================

  /// Get all buses
  static Stream<List<Bus>> getBuses() {
    return busesCollection.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => Bus.fromFirestore(doc)).toList();
    });
  }

  /// Get active buses only
  static Stream<List<Bus>> getActiveBuses() {
    return busesCollection
        .where('status', isEqualTo: 'Active')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => Bus.fromFirestore(doc)).toList();
    });
  }

  /// Get bus by ID
  static Future<Bus?> getBusById(String busId) async {
    final doc = await busesCollection.doc(busId).get();
    if (!doc.exists) return null;
    return Bus.fromFirestore(doc);
  }

  /// Live updates for one bus document (e.g. [Bus.lastLocation] fallback on maps).
  static Stream<Bus?> watchBusById(String busId) {
    return busesCollection.doc(busId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return Bus.fromFirestore(doc);
    });
  }

  /// Load several buses in parallel (e.g. parent with children on different buses).
  static Future<Map<String, Bus?>> getBusesByIds(Iterable<String> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return {};
    final entries = await Future.wait(
      list.map((id) async => MapEntry(id, await getBusById(id))),
    );
    return Map.fromEntries(entries);
  }

  /// Live stream of several bus documents keyed by bus id.
  /// Updates whenever any of the watched buses changes (e.g. lastLocation).
  /// [ids] must have ≤ 10 entries (Firestore whereIn limit).
  static Stream<Map<String, Bus?>> watchBusesByIds(Iterable<String> ids) {
    final idList = ids.toList();
    if (idList.isEmpty) return Stream.value({});
    return busesCollection
        .where(FieldPath.documentId, whereIn: idList)
        .snapshots()
        .map((snap) {
      final result = <String, Bus?>{for (final id in idList) id: null};
      for (final doc in snap.docs) {
        if (doc.exists) result[doc.id] = Bus.fromFirestore(doc);
      }
      return result;
    });
  }

  /// Create or update bus
  static Future<void> saveBus(Bus bus) async {
    await busesCollection.doc(bus.id).set(bus.toFirestore());
  }

  // ==================== STUDENT OPERATIONS ====================

  /// Get students by parent ID (username)
  static Stream<List<Student>> getStudentsByParentId(String parentId) {
    return studentsCollection
        .where('parentIds', arrayContains: parentId)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => Student.fromFirestore(doc)).toList();
    });
  }

  /// Get students by parent authUid (converts authUid to username first)
  static Stream<List<Student>> getStudentsByParentAuthUid(String authUid) async* {
    // First get the username from authUid
    final username = await getUsernameFromAuthUid(authUid);
    
    if (username == null) {
      yield [];
      return;
    }
    
    // Then stream students where parentIds contains this username
    yield* studentsCollection
        .where('parentIds', arrayContains: username)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => Student.fromFirestore(doc)).toList();
    });
  }

  /// Get all students
  static Stream<List<Student>> getAllStudents() {
    return studentsCollection.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => Student.fromFirestore(doc)).toList();
    });
  }

  /// Get student by ID
  static Future<Student?> getStudentById(String studentId) async {
    final doc = await studentsCollection.doc(studentId).get();
    if (!doc.exists) return null;
    return Student.fromFirestore(doc);
  }

  /// Maps student document IDs to kindergarten [classId] for report filtering.
  static Future<Map<String, String?>> getClassIdsForStudentDocIds(
    Iterable<String> studentDocIds,
  ) async {
    final unique = studentDocIds.where((id) => id.isNotEmpty).toSet().toList();
    if (unique.isEmpty) return {};
    final docs = await Future.wait(
      unique.map((id) => studentsCollection.doc(id).get()),
    );
    final map = <String, String?>{};
    for (var i = 0; i < unique.length; i++) {
      final doc = docs[i];
      if (!doc.exists) continue;
      final data = doc.data() as Map<String, dynamic>?;
      final raw = data?['classId'];
      final s = raw is String ? raw.trim() : '';
      map[unique[i]] = s.isEmpty ? null : s;
    }
    return map;
  }

  /// Get student by NFC card ID
  static Future<Student?> getStudentByNfcCard(String nfcCardId) async {
    final snapshot = await studentsCollection
        .where('nfcCardId', isEqualTo: nfcCardId)
        .limit(1)
        .get();
    
    if (snapshot.docs.isEmpty) return null;
    return Student.fromFirestore(snapshot.docs.first);
  }

  /// Create or update student
  static Future<void> saveStudent(Student student) async {
    await studentsCollection.doc(student.id).set(student.toFirestore());
  }

  /// Copies [Bus.assignedRouteId] onto the student when assigning a bus.
  static Future<void> applyStudentBusAssignment({
    required String studentId,
    required String? assignedBusId,
  }) async {
    if (assignedBusId == null) {
      await studentsCollection.doc(studentId).update({
        'assignedBusId': null,
        'assignedRouteId': null,
      });
      return;
    }
    final bus = await getBusById(assignedBusId);
    await studentsCollection.doc(studentId).update({
      'assignedBusId': assignedBusId,
      'assignedRouteId': bus?.assignedRouteId,
    });
  }

  /// Call after a bus’s planned route changes so all students on that bus stay in sync.
  static Future<void> syncAssignedRouteForStudentsOnBus(String busId) async {
    final bus = await getBusById(busId);
    if (bus == null) return;
    final rid = bus.assignedRouteId;
    final snapshot = await studentsCollection
        .where('assignedBusId', isEqualTo: busId)
        .get();
    if (snapshot.docs.isEmpty) return;

    const chunk = 500;
    for (var i = 0; i < snapshot.docs.length; i += chunk) {
      final batch = _firestore.batch();
      final end = (i + chunk > snapshot.docs.length)
          ? snapshot.docs.length
          : i + chunk;
      for (var j = i; j < end; j++) {
        batch.update(snapshot.docs[j].reference, {'assignedRouteId': rid});
      }
      await batch.commit();
    }
  }

  // ==================== BOARDING EVENT OPERATIONS ====================

  /// Get boarding events for a student
  static Stream<List<BoardingEvent>> getBoardingEventsByStudent(String studentId) {
    return boardingEventsCollection
        .where('studentId', isEqualTo: studentId)
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => BoardingEvent.fromFirestore(doc)).toList();
    });
  }

  /// Get boarding events for a session
  static Stream<List<BoardingEvent>> getBoardingEventsBySession(String sessionId) {
    return boardingEventsCollection
        .where('sessionId', isEqualTo: sessionId)
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => BoardingEvent.fromFirestore(doc)).toList();
    });
  }

  /// Create boarding event
  static Future<String> createBoardingEvent(BoardingEvent event) async {
    final docRef = await boardingEventsCollection.add(event.toFirestore());
    return docRef.id;
  }

  /// Latest boarding/alighting event for this student in the given route session.
  ///
  /// Uses a single-field query on [sessionId] then filters in memory so deploys
  /// work without a composite index (sessionId + studentId + timestamp).
  static Future<BoardingEvent?> getLastEventForStudentInSession(
    String studentId,
    String sessionId,
  ) async {
    final snapshot = await boardingEventsCollection
        .where('sessionId', isEqualTo: sessionId)
        .get();
    final matching = snapshot.docs.where((d) {
      final data = d.data() as Map<String, dynamic>?;
      return (data?['studentId'] as String?) == studentId;
    }).toList();
    if (matching.isEmpty) return null;
    matching.sort((a, b) {
      final ma = a.data() as Map<String, dynamic>?;
      final mb = b.data() as Map<String, dynamic>?;
      final ta = (ma?['timestamp'] as Timestamp?)?.toDate() ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final tb = (mb?['timestamp'] as Timestamp?)?.toDate() ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return tb.compareTo(ta);
    });
    return BoardingEvent.fromFirestore(matching.first);
  }

  // ==================== ROUTE SESSION OPERATIONS ====================

  /// Get active session for driver
  static Future<RouteSession?> getActiveSessionForDriver(String driverId) async {
    final snapshot = await routeSessionsCollection
        .where('driverId', isEqualTo: driverId)
        .where('status', isEqualTo: 'Active')
        .limit(1)
        .get();
    
    if (snapshot.docs.isEmpty) return null;
    return RouteSession.fromFirestore(snapshot.docs.first);
  }

  /// Get active session for a bus
  static Future<RouteSession?> getActiveSessionForBus(String busId) async {
    final snapshot = await routeSessionsCollection
        .where('busId', isEqualTo: busId)
        .where('status', isEqualTo: 'Active')
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return null;
    return RouteSession.fromFirestore(snapshot.docs.first);
  }

  /// Live updates when this bus starts or ends a route session (parent map “live” indicator).
  static Stream<RouteSession?> watchActiveSessionForBus(String busId) {
    return routeSessionsCollection
        .where('busId', isEqualTo: busId)
        .where('status', isEqualTo: 'Active')
        .limit(1)
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) return null;
      return RouteSession.fromFirestore(snapshot.docs.first);
    });
  }

  /// All active route sessions (e.g. parent with children on multiple buses).
  static Stream<List<RouteSession>> watchAllActiveRouteSessions() {
    return routeSessionsCollection
        .where('status', isEqualTo: 'Active')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map(RouteSession.fromFirestore).toList();
    });
  }

  /// Start route session. [routeId] defaults to the bus’s [Bus.assignedRouteId]
  /// (planned_routes document id) when omitted.
  static Future<String> startRouteSession({
    required String driverId,
    required String busId,
    String? routeId,
    TripDirection tripDirection = TripDirection.toSchool,
  }) async {
    var resolvedRouteId = routeId?.trim();
    if (resolvedRouteId == null || resolvedRouteId.isEmpty) {
      final bus = await getBusById(busId);
      resolvedRouteId = bus?.assignedRouteId;
    }

    final session = RouteSession(
      id: '', // Will be set by Firestore
      driverId: driverId,
      busId: busId,
      routeId: resolvedRouteId,
      startTime: DateTime.now(),
      status: 'Active',
      gpsTrackingEnabled: true,
      tripDirection: tripDirection,
    );

    final docRef = await routeSessionsCollection.add(session.toFirestore());
    
    // Update bus status
    await busesCollection.doc(busId).update({
      'status': 'Active',
      'currentDriverId': driverId,
    });

    return docRef.id;
  }

  /// End route session
  static Future<void> endRouteSession(String sessionId) async {
    final sessionDoc = await routeSessionsCollection.doc(sessionId).get();
    if (!sessionDoc.exists) return;

    final session = RouteSession.fromFirestore(sessionDoc);

    await routeSessionsCollection.doc(sessionId).update({
      'endTime': Timestamp.now(),
      'status': 'Completed',
    });

    // Update bus status back to Idle (keep driver assignment)
    await busesCollection.doc(session.busId).update({
      'status': 'Idle',
    });
  }

  // ==================== GPS TRACKING OPERATIONS ====================

  /// Get GPS tracking for bus
  static Stream<GpsTracking?> getGpsTrackingForBus(String busId) {
    return gpsTrackingCollection.doc(busId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return GpsTracking.fromFirestore(doc);
    });
  }

  /// Live positions for all buses (document id = bus id).
  static Stream<Map<String, GpsTracking>> getAllGpsTracking() {
    return gpsTrackingCollection.snapshots().map((snapshot) {
      final out = <String, GpsTracking>{};
      for (final doc in snapshot.docs) {
        out[doc.id] = GpsTracking.fromFirestore(doc);
      }
      return out;
    });
  }

  /// Update GPS location
  static Future<void> updateGpsLocation(GpsTracking tracking) async {
    await gpsTrackingCollection.doc(tracking.busId).set(tracking.toFirestore());
    
    // Also update bus's last location
    await busesCollection.doc(tracking.busId).update({
      'lastLocation': {
        'latitude': tracking.latitude,
        'longitude': tracking.longitude,
        'timestamp': Timestamp.fromDate(tracking.timestamp),
      },
    });
  }

  // ==================== PLANNED ROUTES (ADMIN) ====================

  /// Full-collection snapshot; sorted client-side to avoid a composite index on web.
  static Stream<List<PlannedRoute>> getPlannedRoutes() {
    return plannedRoutesCollection.snapshots().map((snapshot) {
      final list = snapshot.docs.map(PlannedRoute.fromFirestore).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  static Future<String> savePlannedRoute(PlannedRoute route) async {
    if (route.id.isEmpty) {
      final ref = await plannedRoutesCollection.add(route.toFirestore());
      return ref.id;
    }
    final data = route.toFirestore();
    data['updatedAt'] = Timestamp.fromDate(DateTime.now());
    await plannedRoutesCollection.doc(route.id).set(data, SetOptions(merge: true));
    return route.id;
  }

  static Future<void> deletePlannedRoute(String id) async {
    await plannedRoutesCollection.doc(id).delete();
  }

  static Future<PlannedRoute?> getPlannedRouteById(String id) async {
    final doc = await plannedRoutesCollection.doc(id).get();
    if (!doc.exists) return null;
    return PlannedRoute.fromFirestore(doc);
  }

  // ==================== EMERGENCY ALERT OPERATIONS ====================

  /// Create emergency alert
  static Future<String> createEmergencyAlert({
    required String driverId,
    required String busId,
    String? sessionId,
    required double latitude,
    required double longitude,
  }) async {
    final alert = EmergencyAlert(
      id: '', // Set to doc id below (web: set() avoids add() listener bugs)
      driverId: driverId,
      busId: busId,
      sessionId: sessionId,
      location: AlertLocation(latitude: latitude, longitude: longitude),
      timestamp: DateTime.now(),
      status: 'Active',
      parentsNotifiedCount: 0,
    );

    // Web: let active snapshot listeners settle before writing — reduces JS SDK
    // "INTERNAL ASSERTION" failures (WatchChangeAggregator) on localhost.
    if (kIsWeb) {
      await Future<void>.delayed(const Duration(milliseconds: 48));
    }

    final docRef = emergencyAlertsCollection.doc();
    await docRef.set(alert.toFirestore());

    final id = docRef.id;
    // Web: let the watch pipeline apply this write before more writes, or the JS
    // SDK can throw INTERNAL ASSERTION (WatchChangeAggregator / TargetState).
    if (kIsWeb) {
      await Future<void>.delayed(const Duration(milliseconds: 220));
    }
    await _notifyAdminsOfEmergency(alertId: id, busId: busId);
    await _yieldFirestoreWebAfterWrite();
    final parentCount = await _notifyParentsOfEmergency(alertId: id, busId: busId);
    await emergencyAlertsCollection.doc(id).update({
      'parentsNotifiedCount': parentCount,
    });
    return id;
  }

  /// Get active emergency alerts
  static Stream<List<EmergencyAlert>> getActiveEmergencyAlerts() {
    return emergencyAlertsCollection
        .where('status', isEqualTo: 'Active')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => EmergencyAlert.fromFirestore(doc)).toList();
    });
  }

  /// Resolve emergency alert
  static Future<void> resolveEmergencyAlert(String alertId, String adminUserId) async {
    await emergencyAlertsCollection.doc(alertId).update({
      'status': 'Resolved',
      'resolvedBy': adminUserId,
      'resolvedAt': Timestamp.now(),
    });
  }

  // ==================== IN-APP NOTIFICATIONS ====================

  /// Parent/admin inbox: newest first.
  ///
  /// Uses only `where('userId', …)` so no composite index is required. Newest-first
  /// and the 100-item cap are applied in memory. (If you deploy
  /// [firestore.indexes.json], you can switch to `orderBy('createdAt')` +
  /// `limit(100)` on the server for cheaper reads at very large inbox sizes.)
  static Stream<List<InAppNotification>> notificationsForAuthUid(String authUid) {
    return notificationsCollection
        .where('userId', isEqualTo: authUid)
        .snapshots()
        .map((snapshot) {
      final list =
          snapshot.docs.map(InAppNotification.fromFirestore).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (list.length <= 100) return list;
      return list.sublist(0, 100);
    });
  }

  static Future<void> markNotificationRead(String notificationId) async {
    await notificationsCollection.doc(notificationId).update({'read': true});
  }

  /// Marks every notification for [userId] as read (same `userId` as inbox query).
  /// Uses chunked batches (Firestore limit 500 ops per batch).
  static Future<void> markAllNotificationsReadForUser(String userId) async {
    final snapshot =
        await notificationsCollection.where('userId', isEqualTo: userId).get();
    WriteBatch? batch;
    var pending = 0;

    Future<void> flush() async {
      if (batch != null && pending > 0) {
        await batch!.commit();
        await _yieldFirestoreWebAfterWrite();
        batch = null;
        pending = 0;
      }
    }

    for (final doc in snapshot.docs) {
      final raw = doc.data();
      final data = raw is Map<String, dynamic> ? raw : null;
      if (data == null) continue;
      final read = data['read'] as bool? ?? false;
      if (read) continue;
      batch ??= _firestore.batch();
      batch!.update(doc.reference, {'read': true});
      pending++;
      if (pending >= 500) {
        await flush();
      }
    }
    await flush();
  }

  /// Web: spacing between writes avoids Firestore JS "INTERNAL ASSERTION" in the
  /// watch pipeline when listeners (e.g. inbox) are active.
  static Future<void> _yieldFirestoreWebAfterWrite() async {
    if (kIsWeb) {
      await Future<void>.delayed(const Duration(milliseconds: 72));
    }
  }

  static Future<void> _addInAppNotification({
    required String userId,
    required String title,
    required String body,
    String type = 'system',
    String? studentId,
    String? relatedAlertId,
    required bool toAdminInbox,
  }) async {
    final taggedBody =
        '${toAdminInbox ? '[Admin]' : '[Parent]'} $body';
    final map = <String, dynamic>{
      'userId': userId,
      'title': title,
      'body': taggedBody,
      'type': type,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    };
    if (studentId != null) map['studentId'] = studentId;
    if (relatedAlertId != null) map['relatedAlertId'] = relatedAlertId;
    final ref = notificationsCollection.doc();
    await ref.set(map);
    await _yieldFirestoreWebAfterWrite();
  }

  /// Called after a boarding event is stored — notifies each parent (by authUid).
  static Future<void> notifyParentsForBoardingEvent({
    required Student student,
    required String eventType,
    required String busId,
  }) async {
    if (student.parentIds.isEmpty) return;
    final bus = await getBusById(busId);
    final busLabel = bus?.busNumber ?? busId;
    final isAlight = eventType.toLowerCase().contains('alight');
    final title = '${student.firstName} ${student.lastName}';
    final body = isAlight
        ? 'Left bus $busLabel'
        : 'Boarded bus $busLabel';

    for (final parentUsername in student.parentIds) {
      final data = await getUserData(parentUsername);
      final authUid = data?['authUid'] as String?;
      if (authUid == null || authUid.isEmpty) continue;
      try {
        await _addInAppNotification(
          userId: authUid,
          title: title,
          body: body,
          type: 'boarding',
          studentId: student.id,
          toAdminInbox: false,
        );
      } catch (_) {}
    }
  }

  static Future<void> _notifyAdminsOfEmergency({
    required String alertId,
    required String busId,
  }) async {
    try {
      final bus = await getBusById(busId);
      final busLabel = bus?.busNumber ?? busId;
      final admins = await usersCollection
          .where('role', whereIn: ['Admin', 'admin']).limit(50).get();
      if (admins.docs.isEmpty) {
        final fallback = await usersCollection.limit(200).get();
        for (final doc in fallback.docs) {
          final d = doc.data() as Map<String, dynamic>;
          final role = (d['role'] as String?)?.toLowerCase();
          if (role != 'admin') continue;
          final uid = d['authUid'] as String?;
          if (uid == null || uid.isEmpty) continue;
          await _addInAppNotification(
            userId: uid,
            title: 'Emergency alert',
            body: 'Bus $busLabel — open Emergency alerts in Admin',
            type: 'emergency',
            relatedAlertId: alertId,
            toAdminInbox: true,
          );
        }
        return;
      }
      for (final doc in admins.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final uid = data['authUid'] as String?;
        if (uid == null || uid.isEmpty) continue;
        await _addInAppNotification(
          userId: uid,
          title: 'Emergency alert',
          body: 'Bus $busLabel — tap to review in Emergency alerts',
          type: 'emergency',
          relatedAlertId: alertId,
          toAdminInbox: true,
        );
      }
    } catch (_) {}
  }

  /// Parents of students on this bus — in-app emergency (same bus as alert).
  static Future<int> _notifyParentsOfEmergency({
    required String alertId,
    required String busId,
  }) async {
    try {
      final session = await getActiveSessionForBus(busId);
      if (session == null) return 0;

      final bus = await getBusById(busId);
      final busLabel = bus?.busNumber ?? busId;

      final eventsSnapshot = await boardingEventsCollection
          .where('sessionId', isEqualTo: session.id)
          .get();
      if (eventsSnapshot.docs.isEmpty) return 0;

      final latestEventByStudent = <String, BoardingEvent>{};
      for (final doc in eventsSnapshot.docs) {
        final event = BoardingEvent.fromFirestore(doc);
        final studentId = event.studentId.trim();
        if (studentId.isEmpty) continue;
        final current = latestEventByStudent[studentId];
        if (current == null || event.timestamp.isAfter(current.timestamp)) {
          latestEventByStudent[studentId] = event;
        }
      }

      final onBusStudentIds = latestEventByStudent.values
          .where((e) => _isBoardingEventType(e.eventType))
          .map((e) => e.studentId.trim())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      if (onBusStudentIds.isEmpty) return 0;

      final notified = <String>{};
      for (final doc in await _getStudentDocsByIds(onBusStudentIds)) {
        final student = Student.fromFirestore(doc);
        for (final parentUsername in student.parentIds) {
          final data = await getUserData(parentUsername);
          final uid = data?['authUid'] as String?;
          if (uid == null || uid.isEmpty) continue;
          if (!notified.add(uid)) continue;
          await _addInAppNotification(
            userId: uid,
            title: 'Emergency alert',
            body: 'Bus $busLabel — check Live Map and stay informed.',
            type: 'emergency',
            relatedAlertId: alertId,
            toAdminInbox: false,
          );
        }
      }
      return notified.length;
    } catch (_) {
      return 0;
    }
  }

  static bool _isBoardingEventType(String? eventType) {
    final s = (eventType ?? '').toLowerCase();
    return s == 'board' || s == 'boarded';
  }

  static Future<List<DocumentSnapshot>> _getStudentDocsByIds(
    List<String> studentIds,
  ) async {
    if (studentIds.isEmpty) return const [];
    const chunkSize = 10; // Firestore whereIn max
    final docs = <DocumentSnapshot>[];
    for (var i = 0; i < studentIds.length; i += chunkSize) {
      final end = (i + chunkSize > studentIds.length)
          ? studentIds.length
          : i + chunkSize;
      final chunk = studentIds.sublist(i, end);
      final snap = await studentsCollection
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      docs.addAll(snap.docs);
    }
    return docs;
  }

  /// Saves FCM device token on the user profile (merge).
  static Future<void> updateFcmTokenForUsername(
    String username,
    String? token,
  ) async {
    if (token == null || token.isEmpty) return;
    await usersCollection.doc(username).set(
      {
        'fcmToken': token,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  // ==================== USER OPERATIONS ====================

  /// Get username from authUid
  static Future<String?> getUsernameFromAuthUid(String authUid) async {
    final snapshot = await usersCollection
        .where('authUid', isEqualTo: authUid)
        .limit(1)
        .get();
    
    if (snapshot.docs.isEmpty) return null;
    return snapshot.docs.first.id; // Document ID is the username
  }

  /// Get user data by username
  static Future<Map<String, dynamic>?> getUserData(String username) async {
    final doc = await usersCollection.doc(username).get();
    if (!doc.exists) return null;
    return doc.data() as Map<String, dynamic>?;
  }

  /// Get user data by authUid
  static Future<Map<String, dynamic>?> getUserDataByAuthUid(String authUid) async {
    final username = await getUsernameFromAuthUid(authUid);
    if (username == null) return null;
    return getUserData(username);
  }

  /// Get user role by username
  static Future<String?> getUserRole(String username) async {
    final userData = await getUserData(username);
    return userData?['role'] as String?;
  }

  /// Get user role by authUid
  static Future<String?> getUserRoleByAuthUid(String authUid) async {
    final userData = await getUserDataByAuthUid(authUid);
    return userData?['role'] as String?;
  }

  /// Get driver name by username
  static Future<String> getDriverName(String username) async {
    final userData = await getUserData(username);
    if (userData == null) return 'Unknown Driver';
    final firstName = userData['firstName'] ?? '';
    final lastName = userData['lastName'] ?? '';
    return '$firstName $lastName'.trim();
  }
}

