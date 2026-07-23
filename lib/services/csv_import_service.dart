import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csv/csv.dart';
import 'package:http/http.dart' as http;
import 'package:schoolway/core/schoolway_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../models/models.dart';
import 'firebase_service.dart';

enum CsvImportType { route, bus, user, student }
enum CsvExportType { users, students, plannedRoutes, buses }

class CsvImportProgress {
  final String phase;
  final int current;
  final int total;

  const CsvImportProgress({
    required this.phase,
    required this.current,
    required this.total,
  });
}

class CsvImportResult {
  final int imported;
  final int failed;
  final bool cancelled;
  final List<String> errors;

  const CsvImportResult({
    required this.imported,
    required this.failed,
    required this.cancelled,
    required this.errors,
  });
}

class OsrmRouteMigrationResult {
  final int scanned;
  final int migrated;
  final int skipped;
  final int failed;
  final bool cancelled;
  final List<String> errors;

  const OsrmRouteMigrationResult({
    required this.scanned,
    required this.migrated,
    required this.skipped,
    required this.failed,
    required this.cancelled,
    required this.errors,
  });
}

class CsvExportFile {
  final String fileName;
  final String content;

  const CsvExportFile({
    required this.fileName,
    required this.content,
  });
}

class CsvImportService {
  static const String _osrmRouteV1Base =
      'https://router.project-osrm.org/route/v1';

  /// Space out sign-up requests so Firebase Auth does not block the client
  /// (`firebase_auth/too-many-requests`) during bulk CSV imports.
  static const Duration _firebaseAuthCsvUserRowSpacing =
      Duration(milliseconds: 300);

  static const List<int> _firebaseAuthTooManyRequestsRetrySeconds = [
    25,
    45,
    75,
    110,
    150,
  ];

  /// Runs [action], retrying when Firebase returns `too-many-requests`.
  /// Use [shouldCancel] so long waits respect import cancellation.
  static Future<T> runWithFirebaseAuthRateLimitRetries<T>(
    Future<T> Function() action, {
    bool Function()? shouldCancel,
  }) async {
    for (var attempt = 0;; attempt++) {
      try {
        return await action();
      } on FirebaseAuthException catch (e) {
        if (e.code != 'too-many-requests') rethrow;
        if (attempt >= _firebaseAuthTooManyRequestsRetrySeconds.length) {
          rethrow;
        }
        await _delayWithCancelCheck(
          Duration(
            seconds: _firebaseAuthTooManyRequestsRetrySeconds[attempt],
          ),
          shouldCancel,
        );
      }
    }
  }

  /// Called between CSV user rows (after the first) during multi-file demo import.
  static Future<void> delayBetweenCsvUserImportRows(
    bool Function()? shouldCancel,
  ) async {
    await _delayWithCancelCheck(_firebaseAuthCsvUserRowSpacing, shouldCancel);
  }

  static Future<void> _delayWithCancelCheck(
    Duration total,
    bool Function()? shouldCancel,
  ) async {
    final end = DateTime.now().add(total);
    while (DateTime.now().isBefore(end)) {
      if (shouldCancel != null && shouldCancel()) {
        throw Exception(
          'Import cancelled while waiting for Firebase rate limit.',
        );
      }
      final remaining = end.difference(DateTime.now());
      if (remaining.isNegative) break;
      final waitTime = remaining > const Duration(seconds: 1)
          ? const Duration(seconds: 1)
          : remaining;
      await Future.delayed(waitTime);
    }
  }

  static String exportLabel(CsvExportType type) {
    switch (type) {
      case CsvExportType.users:
        return 'Users';
      case CsvExportType.students:
        return 'Students';
      case CsvExportType.plannedRoutes:
        return 'Planned Routes';
      case CsvExportType.buses:
        return 'Buses';
    }
  }

  static const Map<CsvImportType, List<String>> _requiredHeaders = {
    CsvImportType.route: ['routename', 'stops', 'assignedbusid'],
    CsvImportType.bus: [
      'busnumber',
      'licenseplate',
      'capacity',
      'status',
      'currentdriverusername',
    ],
    CsvImportType.user: [
      'username',
      'firstname',
      'lastname',
      'email',
      'password',
      'role',
    ],
    CsvImportType.student: [
      'studentid',
      'firstname',
      'lastname',
      'classid',
      'nfccardid',
    ],
  };

  static String label(CsvImportType type) {
    switch (type) {
      case CsvImportType.route:
        return 'Route';
      case CsvImportType.bus:
        return 'Bus';
      case CsvImportType.user:
        return 'User';
      case CsvImportType.student:
        return 'Student';
    }
  }

  static String templateFileName(CsvImportType type) {
    switch (type) {
      case CsvImportType.route:
        return 'route_import_template.csv';
      case CsvImportType.bus:
        return 'bus_import_template.csv';
      case CsvImportType.user:
        return 'user_import_template.csv';
      case CsvImportType.student:
        return 'student_import_template.csv';
    }
  }

  static String templateCsv(CsvImportType type) {
    switch (type) {
      case CsvImportType.route:
        return const ListToCsvConverter().convert([
          ['routeName', 'stops', 'assignedBusId'],
          [
            'UTAR-Westlake Loop',
            '4.33657,101.14195|4.33330,101.13890|4.33657,101.14195',
            'AKP 3201',
          ],
        ]);
      case CsvImportType.bus:
        return const ListToCsvConverter().convert([
          [
            'busNumber',
            'licensePlate',
            'capacity',
            'status',
            'currentDriverUsername',
          ],
          ['BUS-KPR-01', 'AKP 3201', '40', 'Idle', 'driver_utar_01'],
        ]);
      case CsvImportType.user:
        const role = 'Parent';
        return const ListToCsvConverter().convert([
          [
            'username',
            'firstName',
            'lastName',
            'email',
            'password',
            'role',
            'gender',
            'countryCode',
            'phoneNumber',
          ],
          [
            '${role.toLowerCase()}_001',
            'First',
            'Last',
            '${role.toLowerCase()}_001@example.com',
            'TempPass123',
            role,
            'Other',
            '+60',
            '123456789',
          ],
        ]);
      case CsvImportType.student:
        return const ListToCsvConverter().convert([
          [
            'studentId',
            'firstName',
            'lastName',
            'classId',
            'nfcCardId',
            'parentIds',
            'assignedBusId',
            'pickupStop',
            'dropoffStop',
            'status',
          ],
          [
            'STU-KPR-001',
            'Hani',
            'Aziz',
            'K1',
            'NFC-KPR-0001',
            'parent_utar_001|parent_utar_002',
            'AKP 3201',
            'Westlake',
            'UTAR Kampar Main Gate',
            'Active',
          ],
        ]);
    }
  }

  static Future<List<CsvExportFile>> exportCurrentData() async {
    final usersSnap = await swFirestore.collection('users').get();
    final studentsSnap = await swFirestore.collection('students').get();
    final routesSnap = await swFirestore.collection('planned_routes').get();
    final busesSnap = await swFirestore.collection('buses').get();

    final usersRows = <List<dynamic>>[
      const [
        'username',
        'firstName',
        'lastName',
        'email',
        'password',
        'role',
        'gender',
        'countryCode',
        'phoneNumber',
      ],
    ];
    for (final doc in usersSnap.docs) {
      final d = doc.data();
      usersRows.add([
        doc.id,
        (d['firstName'] ?? '').toString(),
        (d['lastName'] ?? '').toString(),
        (d['email'] ?? '').toString(),
        '',
        (d['role'] ?? '').toString(),
        (d['gender'] ?? '').toString(),
        (d['countryCode'] ?? '').toString(),
        (d['phoneNumber'] ?? '').toString(),
      ]);
    }

    final routeToBus = <String, String>{};
    for (final doc in busesSnap.docs) {
      final d = doc.data();
      final assignedRouteId = (d['assignedRouteId'] ?? '').toString().trim();
      if (assignedRouteId.isEmpty) continue;
      routeToBus[assignedRouteId] = doc.id;
    }

    final routesRows = <List<dynamic>>[
      const ['routeName', 'stops', 'assignedBusId'],
    ];
    for (final doc in routesSnap.docs) {
      final route = PlannedRoute.fromFirestore(doc);
      final stops = route.editableStops;
      final stopsRaw = stops
          .map((s) => '${s.latitude},${s.longitude}')
          .join('|');
      routesRows.add([
        route.name,
        stopsRaw,
        routeToBus[route.id] ?? '',
      ]);
    }

    final busesRows = <List<dynamic>>[
      const [
        'busNumber',
        'licensePlate',
        'capacity',
        'status',
        'currentDriverUsername',
      ],
    ];
    for (final doc in busesSnap.docs) {
      final bus = Bus.fromFirestore(doc);
      String currentDriverUsername = '';
      final driverAuthUid = bus.currentDriverId?.trim();
      if (driverAuthUid != null && driverAuthUid.isNotEmpty) {
        final q = await swFirestore
            .collection('users')
            .where('authUid', isEqualTo: driverAuthUid)
            .limit(1)
            .get();
        if (q.docs.isNotEmpty) {
          currentDriverUsername = q.docs.first.id;
        }
      }
      busesRows.add([
        bus.busNumber,
        bus.licensePlate,
        bus.capacity,
        bus.status,
        currentDriverUsername,
      ]);
    }

    final studentsRows = <List<dynamic>>[
      const [
        'studentId',
        'firstName',
        'lastName',
        'classId',
        'nfcCardId',
        'parentIds',
        'assignedBusId',
        'pickupStop',
        'dropoffStop',
        'status',
      ],
    ];
    for (final doc in studentsSnap.docs) {
      final student = Student.fromFirestore(doc);
      studentsRows.add([
        student.studentId,
        student.firstName,
        student.lastName,
        student.classId,
        student.nfcCardId,
        student.parentIds.join('|'),
        student.assignedBusId ?? '',
        student.pickupStop ?? '',
        student.dropoffStop ?? '',
        student.status,
      ]);
    }

    final now = DateTime.now();
    final stamp =
        '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}'
        '_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';

    return [
      CsvExportFile(
        fileName: 'users_export_$stamp.csv',
        content: const ListToCsvConverter().convert(usersRows),
      ),
      CsvExportFile(
        fileName: 'students_export_$stamp.csv',
        content: const ListToCsvConverter().convert(studentsRows),
      ),
      CsvExportFile(
        fileName: 'planned_routes_export_$stamp.csv',
        content: const ListToCsvConverter().convert(routesRows),
      ),
      CsvExportFile(
        fileName: 'buses_export_$stamp.csv',
        content: const ListToCsvConverter().convert(busesRows),
      ),
    ];
  }

  static Future<CsvExportFile> exportCurrentDataByType(CsvExportType type) async {
    final files = await exportCurrentData();
    String prefix;
    switch (type) {
      case CsvExportType.users:
        prefix = 'users_export_';
        break;
      case CsvExportType.students:
        prefix = 'students_export_';
        break;
      case CsvExportType.plannedRoutes:
        prefix = 'planned_routes_export_';
        break;
      case CsvExportType.buses:
        prefix = 'buses_export_';
        break;
    }
    final match = files.where((f) => f.fileName.startsWith(prefix));
    if (match.isEmpty) {
      throw Exception('No export data found for ${exportLabel(type)}.');
    }
    return match.first;
  }

  static Future<CsvImportResult> importCsv({
    required CsvImportType type,
    required String csvText,
    required void Function(CsvImportProgress progress) onProgress,
    required bool Function() shouldCancel,
  }) async {
    var content = csvText.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
    if (content.startsWith('\uFEFF')) content = content.substring(1);
    final rawRows =
        const CsvToListConverter(shouldParseNumbers: false, eol: '\n').convert(content);
    final rows = rawRows
        .where((r) => r.isNotEmpty && r.any((cell) => cell.toString().trim().isNotEmpty))
        .toList();
    if (rows.length < 2) {
      throw Exception('CSV must contain a header and at least one data row.');
    }


    final header = _headerMap(rows.first);
    final requiredHeaders = _requiredHeaders[type]!;
    for (final h in requiredHeaders) {
      if (!header.containsKey(h)) {
        throw Exception('Wrong CSV type selected. Missing required column: $h');
      }
    }

    switch (type) {
      case CsvImportType.route:
        return _importRoutes(rows, header, onProgress, shouldCancel);
      case CsvImportType.bus:
        return _importBuses(rows, header, onProgress, shouldCancel);
      case CsvImportType.user:
        return _importUsers(rows, header, onProgress, shouldCancel);
      case CsvImportType.student:
        return _importStudents(rows, header, onProgress, shouldCancel);
    }
  }

  /// Rebuilds planned_routes.waypoints from OSRM using each route's editable stops.
  /// Useful for older routes saved before full OSRM geometry was persisted.
  static Future<OsrmRouteMigrationResult> migratePlannedRoutesToOsrm({
    required void Function(CsvImportProgress progress) onProgress,
    required bool Function() shouldCancel,
  }) async {
    final snap = await swFirestore.collection('planned_routes').get();
    final docs = snap.docs;
    final errors = <String>[];
    var migrated = 0;
    var skipped = 0;
    var failed = 0;
    var cancelled = false;

    for (var i = 0; i < docs.length; i++) {
      if (shouldCancel()) {
        cancelled = true;
        break;
      }
      onProgress(
        CsvImportProgress(
          phase: 'Rebuilding route geometry',
          current: i + 1,
          total: docs.length,
        ),
      );

      final doc = docs[i];
      final route = PlannedRoute.fromFirestore(doc);
      final stops = route.editableStops;
      if (stops.length < 2) {
        skipped++;
        continue;
      }
      try {
        final waypoints = await _resolveRouteWaypoints(stops);
        if (waypoints.length < 2) {
          skipped++;
          continue;
        }

        await swFirestore.collection('planned_routes').doc(route.id).update({
          'stops': stops.map((w) => w.toMap()).toList(),
          'waypoints': waypoints.map((w) => w.toMap()).toList(),
          'updatedAt': Timestamp.fromDate(DateTime.now()),
        });
        migrated++;
      } catch (e) {
        failed++;
        errors.add('Route "${route.name}": $e');
      }
    }

    return OsrmRouteMigrationResult(
      scanned: docs.length,
      migrated: migrated,
      skipped: skipped,
      failed: failed,
      cancelled: cancelled,
      errors: errors,
    );
  }

  static Map<String, int> _headerMap(List<dynamic> headerRow) {
    final out = <String, int>{};
    for (var i = 0; i < headerRow.length; i++) {
      final key = _cell(headerRow[i]).toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (key.isNotEmpty) out[key] = i;
    }
    return out;
  }

  static String _cell(dynamic value) => value?.toString().trim() ?? '';

  static String _value(List<dynamic> row, Map<String, int> header, String key) {
    final i = header[key];
    if (i == null || i >= row.length) return '';
    return _cell(row[i]);
  }

  static List<_CsvRow> _effectiveRows(
    List<List<dynamic>> rows,
    Map<String, int> header,
    List<String> keys,
  ) {
    final out = <_CsvRow>[];
    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      var hasData = false;
      for (final key in keys) {
        if (_value(row, header, key).isNotEmpty) {
          hasData = true;
          break;
        }
      }
      if (hasData) out.add(_CsvRow(row: row, rowNumber: i + 1));
    }
    return out;
  }

  static Future<CsvImportResult> _importRoutes(
    List<List<dynamic>> rows,
    Map<String, int> header,
    void Function(CsvImportProgress progress) onProgress,
    bool Function() shouldCancel,
  ) async {
    final dataRows = _effectiveRows(rows, header, const ['routename']);
    final errors = <String>[];
    var imported = 0;
    var cancelled = false;

    for (var i = 0; i < dataRows.length; i++) {
      if (shouldCancel()) {
        cancelled = true;
        break;
      }
      onProgress(CsvImportProgress(phase: 'Routes', current: i + 1, total: dataRows.length));
      final row = dataRows[i];
      try {
        final routeName = _value(row.row, header, 'routename');
        final stopsRaw = _value(row.row, header, 'stops');
        final assignedBusRaw = _value(row.row, header, 'assignedbusid');
        if (routeName.isEmpty || stopsRaw.isEmpty || assignedBusRaw.isEmpty) {
          throw Exception('routeName, stops, and assignedBusId are required');
        }
        final stops = _parseStopPairs(stopsRaw);
        final existing = await swFirestore
            .collection('planned_routes')
            .where('name', isEqualTo: routeName)
            .limit(1)
            .get();
        final route = PlannedRoute(
          id: existing.docs.isEmpty ? '' : existing.docs.first.id,
          name: routeName,
          stops: stops,
          waypoints: await _resolveRouteWaypoints(stops),
          createdAt: existing.docs.isEmpty
              ? DateTime.now()
              : PlannedRoute.fromFirestore(existing.docs.first).createdAt,
          updatedAt: existing.docs.isEmpty ? null : DateTime.now(),
        );
        await FirebaseService.savePlannedRoute(route);
        final routeId = await _resolveRouteIdByName(routeName);
        final busId = await _resolveBusId(assignedBusRaw);
        if (busId == null) {
          throw Exception('assignedBusId "$assignedBusRaw" not found.');
        }
        await swFirestore.collection('buses').doc(busId).update({
          'assignedRouteId': routeId,
          'currentRoute': routeName,
        });
        await FirebaseService.syncAssignedRouteForStudentsOnBus(busId);
        imported++;
      } catch (e) {
        errors.add('Row ${row.rowNumber}: $e');
      }
    }

    return CsvImportResult(
      imported: imported,
      failed: errors.length,
      cancelled: cancelled,
      errors: errors,
    );
  }

  static List<RouteWaypoint> _parseStopPairs(String raw) {
    final pairs = raw.split('|').map((e) => e.trim()).where((e) => e.isNotEmpty);
    final out = <RouteWaypoint>[];
    for (final p in pairs) {
      final parts = p.split(',');
      if (parts.length != 2) {
        throw Exception('Invalid stop "$p". Use format lat,lng');
      }
      final lat = double.tryParse(parts[0].trim());
      final lng = double.tryParse(parts[1].trim());
      if (lat == null || lng == null) {
        throw Exception('Invalid coordinates in "$p".');
      }
      out.add(RouteWaypoint(latitude: lat, longitude: lng));
    }
    return out;
  }

  static Future<List<RouteWaypoint>> _resolveRouteWaypoints(
    List<RouteWaypoint> stops,
  ) async {
    if (stops.length < 2) return stops;
    try {
      final coords = stops.map((w) => '${w.longitude},${w.latitude}').join(';');
      final radiuses = List<String>.filled(stops.length, 'unlimited').join(';');

      final uri = Uri.parse('$_osrmRouteV1Base/driving/$coords').replace(
        queryParameters: {
          'overview': 'full',
          'geometries': 'geojson',
          'steps': 'false',
          'continue_straight': 'false',
          'radiuses': radiuses,
        },
      );

      final res = await http.get(uri, headers: const {
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 25));
      if (res.statusCode != 200) return stops;

      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final code = decoded['code'] as String?;
      if (code != null && code != 'Ok') return stops;

      final routes = decoded['routes'] as List<dynamic>? ?? const [];
      if (routes.isEmpty) return stops;
      final geometry = (routes.first as Map<String, dynamic>)['geometry']
          as Map<String, dynamic>?;
      final rawCoords = geometry?['coordinates'] as List<dynamic>?;
      if (rawCoords == null || rawCoords.length < 2) return stops;

      return rawCoords.map<RouteWaypoint>((p) {
        final pair = p as List<dynamic>;
        final lon = (pair[0] as num).toDouble();
        final lat = (pair[1] as num).toDouble();
        return RouteWaypoint(latitude: lat, longitude: lon);
      }).toList();
    } catch (_) {
      return stops;
    }
  }

  static Future<CsvImportResult> _importBuses(
    List<List<dynamic>> rows,
    Map<String, int> header,
    void Function(CsvImportProgress progress) onProgress,
    bool Function() shouldCancel,
  ) async {
    final dataRows = _effectiveRows(rows, header, const ['busnumber', 'licenseplate']);
    final errors = <String>[];
    var imported = 0;
    var cancelled = false;

    for (var i = 0; i < dataRows.length; i++) {
      if (shouldCancel()) {
        cancelled = true;
        break;
      }
      onProgress(CsvImportProgress(phase: 'Buses', current: i + 1, total: dataRows.length));
      final row = dataRows[i];
      try {
        final busNumber = _value(row.row, header, 'busnumber');
        final licensePlate = _value(row.row, header, 'licenseplate');
        final status = _value(row.row, header, 'status').isEmpty
            ? 'Idle'
            : _capitalizeName(_value(row.row, header, 'status'));
        final capacity = int.tryParse(_value(row.row, header, 'capacity')) ?? 40;
        final driverUsername = _value(row.row, header, 'currentdriverusername');
        if (busNumber.isEmpty || licensePlate.isEmpty) {
          throw Exception('busNumber and licensePlate are required');
        }

        String? driverAuthUid;
        if (driverUsername.isNotEmpty) {
          final userDoc = await swFirestore
              .collection('users')
              .doc(driverUsername)
              .get();
          if (!userDoc.exists) throw Exception('Driver "$driverUsername" not found.');
          final data = userDoc.data();
          final role = (data?['role'] as String?)?.toLowerCase() ?? '';
          if (role != 'driver') throw Exception('"$driverUsername" is not Driver.');
          driverAuthUid = data?['authUid'] as String?;
        }

        final busId = _busDocIdFromPlate(licensePlate);
        final existingDoc =
            await swFirestore.collection('buses').doc(busId).get();
        final existing = existingDoc.exists ? Bus.fromFirestore(existingDoc) : null;
        final bus = Bus(
          id: busId,
          busNumber: busNumber,
          licensePlate: licensePlate,
          status: status,
          currentDriverId: driverAuthUid ?? existing?.currentDriverId,
          currentRoute: existing?.currentRoute,
          assignedRouteId: existing?.assignedRouteId,
          capacity: capacity,
          lastLocation: existing?.lastLocation,
          createdAt: existing?.createdAt ?? DateTime.now(),
        );
        await FirebaseService.saveBus(bus);
        imported++;
      } catch (e) {
        errors.add('Row ${row.rowNumber}: $e');
      }
    }

    return CsvImportResult(
      imported: imported,
      failed: errors.length,
      cancelled: cancelled,
      errors: errors,
    );
  }

  static String _busDocIdFromPlate(String plate) {
    return plate.replaceAll(RegExp(r'[^a-zA-Z0-9\-_~!*()]'), '_');
  }

  static Future<CsvImportResult> _importUsers(
    List<List<dynamic>> rows,
    Map<String, int> header,
    void Function(CsvImportProgress progress) onProgress,
    bool Function() shouldCancel,
  ) async {
    final dataRows = _effectiveRows(rows, header, const [
      'username',
      'firstname',
      'lastname',
      'email',
    ]);
    final errors = <String>[];
    var imported = 0;
    var cancelled = false;

    FirebaseApp? secondaryApp;
    try {
      secondaryApp = await Firebase.initializeApp(
        name: 'CsvTypeImport_${DateTime.now().microsecondsSinceEpoch}',
        options: Firebase.app().options,
      );
      final auth = FirebaseAuth.instanceFor(app: secondaryApp);

      for (var i = 0; i < dataRows.length; i++) {
        if (shouldCancel()) {
          cancelled = true;
          break;
        }
        if (i > 0) {
          await _delayWithCancelCheck(_firebaseAuthCsvUserRowSpacing, shouldCancel);
        }
        onProgress(CsvImportProgress(
          phase: 'Users',
          current: i + 1,
          total: dataRows.length,
        ));

        final row = dataRows[i];
        try {
          final username = _value(row.row, header, 'username');
          final firstName = _capitalizeName(_value(row.row, header, 'firstname'));
          final lastName = _capitalizeName(_value(row.row, header, 'lastname'));
          final email = _value(row.row, header, 'email');
          final password = _value(row.row, header, 'password');
          final role = _normalizeRole(_value(row.row, header, 'role'));
          final gender = _capitalizeName(_value(row.row, header, 'gender'));
          final phone = _value(row.row, header, 'phonenumber');
          final countryCode = _value(row.row, header, 'countrycode');

          if (role.isEmpty) {
            throw Exception(
              'Invalid role. Use Admin, Driver, or Parent.',
            );
          }

          await _upsertUserRecord(
            auth: auth,
            username: username,
            firstName: firstName,
            lastName: lastName,
            email: email,
            password: password,
            role: role,
            gender: gender,
            phone: phone,
            countryCode: countryCode,
            status: _value(row.row, header, 'status'),
            shouldCancel: shouldCancel,
          );
          imported++;
        } catch (e) {
          errors.add('Row ${row.rowNumber}: $e');
        }
      }
    } finally {
      if (secondaryApp != null) await secondaryApp.delete();
    }

    return CsvImportResult(
      imported: imported,
      failed: errors.length,
      cancelled: cancelled,
      errors: errors,
    );
  }

  static String _normalizeRole(String role) {
    switch (role.trim().toLowerCase()) {
      case 'driver':
        return 'Driver';
      case 'parent':
        return 'Parent';
      case 'admin':
        return 'Admin';
      default:
        return '';
    }
  }

  static String _normalizeEmail(String email) => email.trim().toLowerCase();

  static Future<String?> _resolveExistingAuthUidByEmail({
    required FirebaseAuth auth,
    required String email,
    required String password,
    bool Function()? shouldCancel,
  }) async {
    if (password.isEmpty) {
      throw Exception(
        'Email "$email" already exists in Firebase Auth. Provide the correct password in CSV to link Firestore user.',
      );
    }

    try {
      final credential =
          await runWithFirebaseAuthRateLimitRetries<UserCredential>(
        () => auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        ),
        shouldCancel: shouldCancel,
      );
      final uid = credential.user?.uid;
      if (uid == null) {
        throw Exception(
          'Failed to read Firebase Auth UID for "$email".',
        );
      }
      return uid;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') return null;
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        throw Exception(
          'Email "$email" already exists in Firebase Auth, but password does not match. Provide the existing password to reuse UID.',
        );
      }
      rethrow;
    } finally {
      if (auth.currentUser != null) await auth.signOut();
    }
  }

  static bool? _parseStatusToIsActive(String rawStatus) {
    final normalized = rawStatus.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    if (['active', 'yes', 'y', 'true', '1', 'on'].contains(normalized)) return true;
    if (['inactive', 'no', 'n', 'false', '0', 'off'].contains(normalized)) return false;
    throw Exception('Status "$rawStatus" is unrecognized. Use Active or Inactive.');
  }

  static String _capitalizeName(String text) {
    if (text.isEmpty) return text;
    return text.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  static Future<void> _upsertUserRecord({
    required FirebaseAuth auth,
    required String username,
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    required String role,
    required String gender,
    required String phone,
    required String countryCode,
    required String status,
    bool Function()? shouldCancel,
  }) async {
    final trimmedUsername = username.trim();
    final trimmedEmail = email.trim();
    if (trimmedUsername.isEmpty ||
        firstName.trim().isEmpty ||
        lastName.trim().isEmpty ||
        trimmedEmail.isEmpty) {
      throw Exception('Please fill all required fields');
    }
    final normalizedEmail = _normalizeEmail(trimmedEmail);
    final isActive = _parseStatusToIsActive(status);

    final usernameDoc = await swFirestore.collection('users').doc(trimmedUsername).get();
    final emailDoc = await _findUserDocByNormalizedEmail(normalizedEmail);

    final usernameExists = usernameDoc.exists;
    final emailExists = emailDoc != null;
    final usernameDocId = usernameDoc.id;
    final emailDocId = emailDoc?.id;

    if (usernameExists && emailExists && usernameDocId != emailDocId) {
      throw Exception(
        'Conflict: username "$trimmedUsername" and email "$trimmedEmail" belong to different users.',
      );
    }

    final targetDocId = usernameExists ? usernameDocId : emailDocId;
    if (targetDocId != null) {
      await _updateExistingUserRecord(
        docId: targetDocId,
        firstName: firstName,
        lastName: lastName,
        email: trimmedEmail,
        role: role,
        gender: gender,
        phone: phone,
        countryCode: countryCode,
        isActive: isActive,
      );
      return;
    }

    if (password.isEmpty) {
      throw Exception('Password is required for new users.');
    }

    UserCredential? credential;
    var createdNewAuth = false;
    try {
      String? existingAuthUid;
      try {
        credential =
            await runWithFirebaseAuthRateLimitRetries<UserCredential>(
          () => auth.createUserWithEmailAndPassword(
            email: trimmedEmail,
            password: password,
          ),
          shouldCancel: shouldCancel,
        );
        createdNewAuth = true;
      } on FirebaseAuthException catch (e) {
        if (e.code == 'email-already-in-use') {
          existingAuthUid = await _resolveExistingAuthUidByEmail(
            auth: auth,
            email: trimmedEmail,
            password: password,
            shouldCancel: shouldCancel,
          );
        } else {
          rethrow;
        }
      }
      final uid = existingAuthUid ?? credential?.user?.uid;
      if (uid == null) throw Exception('Failed to create user account');
      await swFirestore.collection('users').doc(trimmedUsername).set({
        'authUid': uid,
        'firstName': firstName.trim(),
        'lastName': lastName.trim(),
        'email': trimmedEmail,
        'phoneNumber': phone.trim(),
        'countryCode': countryCode.trim().isEmpty ? '+60' : countryCode.trim(),
        'gender': gender.trim().isEmpty ? 'Other' : gender.trim(),
        'role': role,
        'emailVerified': false,
        'isActive': isActive ?? true,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      if (createdNewAuth && credential?.user != null) {
        try {
          await credential!.user!.delete();
        } catch (_) {}
      }
      rethrow;
    } finally {
      if (auth.currentUser != null) await auth.signOut();
    }
  }

  static Future<QueryDocumentSnapshot<Map<String, dynamic>>?>
  _findUserDocByNormalizedEmail(String normalizedEmail) async {
    final users = await swFirestore.collection('users').get();
    QueryDocumentSnapshot<Map<String, dynamic>>? match;
    for (final doc in users.docs) {
      final userEmail = (doc.data()['email'] as String?) ?? '';
      if (_normalizeEmail(userEmail) != normalizedEmail) continue;
      match = doc;
      break;
    }
    return match;
  }

  static Future<void> _updateExistingUserRecord({
    required String docId,
    required String firstName,
    required String lastName,
    required String email,
    required String role,
    required String gender,
    required String phone,
    required String countryCode,
    required bool? isActive,
  }) async {
    final updateMap = <String, dynamic>{
      'firstName': firstName.trim(),
      'lastName': lastName.trim(),
      'email': email.trim(),
      'phoneNumber': phone.trim(),
      'countryCode': countryCode.trim().isEmpty ? '+60' : countryCode.trim(),
      'gender': gender.trim().isEmpty ? 'Other' : gender.trim(),
      'role': role,
    };
    if (isActive != null) {
      updateMap['isActive'] = isActive;
    }
    await swFirestore.collection('users').doc(docId).update(updateMap);
  }

  static Future<CsvImportResult> _importStudents(
    List<List<dynamic>> rows,
    Map<String, int> header,
    void Function(CsvImportProgress progress) onProgress,
    bool Function() shouldCancel,
  ) async {
    final dataRows = _effectiveRows(rows, header, const [
      'studentid',
      'firstname',
      'lastname',
    ]);
    final parentCounts = await _loadParentStudentCounts();
    final parentPickupStops = await _loadParentPickupStops();
    final errors = <String>[];
    var imported = 0;
    var cancelled = false;

    for (var i = 0; i < dataRows.length; i++) {
      if (shouldCancel()) {
        cancelled = true;
        break;
      }
      onProgress(CsvImportProgress(
        phase: 'Students',
        current: i + 1,
        total: dataRows.length,
      ));
      final row = dataRows[i];
      try {
        await _createStudentWithRules(
          row: row,
          header: header,
          parentStudentCounts: parentCounts,
          parentPickupStops: parentPickupStops,
        );
        imported++;
      } catch (e) {
        errors.add('Row ${row.rowNumber}: $e');
      }
    }

    return CsvImportResult(
      imported: imported,
      failed: errors.length,
      cancelled: cancelled,
      errors: errors,
    );
  }

  static Future<Map<String, int>> _loadParentStudentCounts() async {
    final snapshot = await swFirestore.collection('students').get();
    final counts = <String, int>{};
    for (final doc in snapshot.docs) {
      final student = Student.fromFirestore(doc);
      for (final parent in student.parentIds) {
        counts[parent] = (counts[parent] ?? 0) + 1;
      }
    }
    return counts;
  }

  static Future<Map<String, String>> _loadParentPickupStops() async {
    final snapshot = await swFirestore.collection('students').get();
    final stops = <String, String>{};
    for (final doc in snapshot.docs) {
      final student = Student.fromFirestore(doc);
      final stop = (student.pickupStop ?? '').trim();
      if (stop.isEmpty) continue;
      for (final parent in student.parentIds) {
        stops[parent] ??= stop;
      }
    }
    return stops;
  }

  /// Resolves [pickupRaw] against [parentPickupStops] (Firestore + earlier import rows).
  /// An established household stop always wins over a conflicting CSV cell so imports
  /// stay consistent with siblings without manual CSV edits.
  static String reconcileImportedPickupStop({
    required String pickupRaw,
    required List<String> parentIds,
    required Map<String, String> parentPickupStops,
  }) {
    final trimmed = pickupRaw.trim();
    final established = <String>{};
    for (final parent in parentIds) {
      final s = parentPickupStops[parent];
      if (s != null && s.isNotEmpty) established.add(s);
    }
    if (established.length > 1) {
      throw Exception(
        'Parents ${parentIds.join(", ")} are linked to different pickup stops '
        '(${established.join("; ")}).',
      );
    }
    if (established.isEmpty) return trimmed;
    final house = established.single;
    if (trimmed.isEmpty) return house;
    return house;
  }

  static Future<void> _createStudentWithRules({
    required _CsvRow row,
    required Map<String, int> header,
    required Map<String, int> parentStudentCounts,
    required Map<String, String> parentPickupStops,
  }) async {
    final studentId = _value(row.row, header, 'studentid');
    final firstName = _capitalizeName(_value(row.row, header, 'firstname'));
    final lastName = _capitalizeName(_value(row.row, header, 'lastname'));
    final classId = _value(row.row, header, 'classid');
    final nfcCardId = _value(row.row, header, 'nfccardid');
    final parentIds = _value(row.row, header, 'parentids')
        .split('|')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final assignedBusRaw = _value(row.row, header, 'assignedbusid');
    final pickupRaw = _value(row.row, header, 'pickupstop');
    final dropoffStop = _value(row.row, header, 'dropoffstop');
    final statusRaw = _value(row.row, header, 'status').toLowerCase();
    final status = ['inactive', 'no', 'n', 'false', '0', 'off'].contains(statusRaw)
        ? 'Inactive'
        : 'Active';

    if (studentId.isEmpty ||
        firstName.isEmpty ||
        lastName.isEmpty ||
        classId.isEmpty ||
        nfcCardId.isEmpty) {
      throw Exception('Required fields missing.');
    }
    if (parentIds.isEmpty || parentIds.length > 2) {
      throw Exception('Each student must link to 1 or 2 parents.');
    }

    final documentId = studentId.replaceAll('/', '_');

    final futures = await Future.wait([
      swFirestore.collection('students').doc(documentId).get(),
      swFirestore.collection('students').where('nfcCardId', isEqualTo: nfcCardId).limit(1).get(),
      for (final parent in parentIds) swFirestore.collection('users').doc(parent).get(),
    ]);

    final existingStudent = futures[0] as DocumentSnapshot;
    if (existingStudent.exists) return;

    final existingNfc = futures[1] as QuerySnapshot;
    if (existingNfc.docs.isNotEmpty) {
      throw Exception('nfcCardId "$nfcCardId" already exists.');
    }

    final parentDocs = futures.sublist(2).cast<DocumentSnapshot>();
    for (int i = 0; i < parentIds.length; i++) {
      final parentDoc = parentDocs[i];
      final parent = parentIds[i];
      if (!parentDoc.exists) throw Exception('Parent "$parent" does not exist.');
      final role = (parentDoc.data() as Map<String, dynamic>?)?['role']?.toString().toLowerCase() ?? '';
      if (role != 'parent') throw Exception('User "$parent" is not Parent.');
    }

    final pickupStop = reconcileImportedPickupStop(
      pickupRaw: pickupRaw,
      parentIds: parentIds,
      parentPickupStops: parentPickupStops,
    );

    final assignedBusId = await _resolveBusId(assignedBusRaw);
    String? assignedRouteId;
    if (assignedBusId != null) {
      assignedRouteId = (await FirebaseService.getBusById(assignedBusId))?.assignedRouteId;
    }

    final student = Student(
      id: documentId,
      studentId: studentId,
      firstName: firstName,
      lastName: lastName,
      nfcCardId: nfcCardId,
      parentIds: parentIds,
      assignedBusId: assignedBusId,
      assignedRouteId: assignedRouteId,
      pickupStop: pickupStop.isEmpty ? null : pickupStop,
      dropoffStop: dropoffStop.isEmpty ? null : dropoffStop,
      status: status,
      classId: classId,
      createdAt: DateTime.now(),
    );
    await swFirestore
        .collection('students')
        .doc(documentId)
        .set(student.toFirestore());

    for (final parent in parentIds) {
      parentStudentCounts[parent] = (parentStudentCounts[parent] ?? 0) + 1;
      if (pickupStop.isNotEmpty) parentPickupStops[parent] = pickupStop;
    }
  }

  static Future<String?> _resolveBusId(String raw) async {
    final value = raw.trim();
    if (value.isEmpty) return null;
    final byDoc = await swFirestore.collection('buses').doc(value).get();
    if (byDoc.exists) return byDoc.id;
    final byPlateDoc = await swFirestore
        .collection('buses')
        .doc(_busDocIdFromPlate(value))
        .get();
    if (byPlateDoc.exists) return byPlateDoc.id;
    final byPlate = await swFirestore
        .collection('buses')
        .where('licensePlate', isEqualTo: value)
        .limit(1)
        .get();
    if (byPlate.docs.isNotEmpty) return byPlate.docs.first.id;
    final byBusNumber = await swFirestore
        .collection('buses')
        .where('busNumber', isEqualTo: value)
        .limit(1)
        .get();
    if (byBusNumber.docs.isNotEmpty) return byBusNumber.docs.first.id;
    return null;
  }

  static Future<String> _resolveRouteIdByName(String routeName) async {
    final snap = await swFirestore
        .collection('planned_routes')
        .where('name', isEqualTo: routeName)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) {
      throw Exception('Route "$routeName" not found after save.');
    }
    return snap.docs.first.id;
  }

  // ==================== CSV PRE-COMMIT VALIDATION & ERROR REPORTING ====================

  /// Intelligently detects the CSV import type based on the headers in the first row.
  static CsvImportType? detectCsvType(String csvContent) {
    var content = csvContent.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
    if (content.startsWith('\uFEFF')) content = content.substring(1);
    final rawRows = const CsvToListConverter(eol: '\n').convert(content);
    if (rawRows.isEmpty || rawRows.first.isEmpty) return null;

    final headers = rawRows.first.map((e) => e.toString().trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')).toSet();

    if (headers.contains('studentid') || headers.contains('nfccardid') || headers.contains('parentids')) {
      return CsvImportType.student;
    }
    if (headers.contains('busnumber') || headers.contains('licenseplate')) {
      return CsvImportType.bus;
    }
    if ((headers.contains('name') || headers.contains('routename')) && headers.contains('stops')) {
      return CsvImportType.route;
    }
    if (headers.contains('username') || headers.contains('email') || headers.contains('role')) {
      return CsvImportType.user;
    }
    return null;
  }

  /// Validates raw CSV content before committing, detecting field-level errors and duplicates.
  static Future<CsvValidationReport> validateCsvPreCommit(
    String csvContent,
    CsvImportType type,
  ) async {
    var content = csvContent.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
    if (content.startsWith('\uFEFF')) content = content.substring(1);
    final rawRows = const CsvToListConverter(eol: '\n').convert(content);

    final validRawRows = rawRows
        .where((r) => r.isNotEmpty && r.any((cell) => cell.toString().trim().isNotEmpty))
        .toList();
    if (validRawRows.isEmpty) {
      return const CsvValidationReport(totalRows: 0, validRows: 0, invalidRows: 0, duplicateRows: 0, existingInFirestore: 0, rows: []);
    }

    final headers = validRawRows.first.map((e) => e.toString().trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')).toList();
    final dataRows = validRawRows.skip(1).toList();

    final seenKeys = <String>{};
    final validationRows = <CsvValidationRow>[];

    int validCount = 0;
    int invalidCount = 0;
    int duplicateCount = 0;
    int existingCount = 0;

    final Set<String> firestoreKeys = {};
    try {
      if (type == CsvImportType.user) {
        final snap = await swFirestore.collection('users').get();
        for (var doc in snap.docs) {
          firestoreKeys.add(doc.id.toLowerCase());
          final email = doc.data()['email'] as String?;
          if (email != null && email.isNotEmpty) firestoreKeys.add(email.toLowerCase());
        }
      } else if (type == CsvImportType.student) {
        final snap = await swFirestore.collection('students').get();
        for (var doc in snap.docs) {
          firestoreKeys.add(doc.id.toLowerCase());
        }
      } else if (type == CsvImportType.bus) {
        final snap = await swFirestore.collection('buses').get();
        for (var doc in snap.docs) {
          final busNum = doc.data()['busNumber'] as String?;
          final plate = doc.data()['licensePlate'] as String?;
          if (busNum != null && busNum.isNotEmpty) firestoreKeys.add(busNum.toLowerCase());
          if (plate != null && plate.isNotEmpty) firestoreKeys.add(plate.toLowerCase());
        }
      } else if (type == CsvImportType.route) {
        final snap = await swFirestore.collection('planned_routes').get();
        for (var doc in snap.docs) {
          final name = doc.data()['name'] as String?;
          if (name != null && name.isNotEmpty) firestoreKeys.add(name.toLowerCase());
        }
      }
    } catch (_) {}

    for (var i = 0; i < dataRows.length; i++) {
      final rowNumber = i + 2;
      final row = dataRows[i];
      final rowMap = <String, String>{};
      for (var j = 0; j < headers.length; j++) {
        if (j < row.length) {
          rowMap[headers[j]] = row[j].toString().trim();
        }
      }

      final errors = <String>[];
      bool isDuplicate = false;
      bool existsInFirestore = false;
      String uniqueKey = '';

      if (type == CsvImportType.student) {
        final id = rowMap['studentid'] ?? rowMap['id'] ?? '';
        final nfc = rowMap['nfccardid'] ?? rowMap['nfc'] ?? '';
        if (id.isEmpty) errors.add('Missing Student ID');
        if (nfc.isNotEmpty && nfc.length < 4) errors.add('Invalid NFC Card ID length');
        uniqueKey = id.toLowerCase();
      } else if (type == CsvImportType.user) {
        final username = rowMap['username'] ?? rowMap['id'] ?? '';
        final email = rowMap['email'] ?? '';
        if (username.isEmpty) errors.add('Missing Username');
        if (email.isNotEmpty && !email.contains('@')) errors.add('Invalid Email format');
        uniqueKey = username.toLowerCase();
      } else if (type == CsvImportType.bus) {
        final busNum = rowMap['busnumber'] ?? rowMap['id'] ?? '';
        final plate = rowMap['licenseplate'] ?? '';
        if (busNum.isEmpty && plate.isEmpty) errors.add('Missing Bus Number/License Plate');
        uniqueKey = (busNum.isNotEmpty ? busNum : plate).toLowerCase();
      } else if (type == CsvImportType.route) {
        final name = rowMap['name'] ?? rowMap['routename'] ?? '';
        if (name.isEmpty) errors.add('Missing Route Name');
        uniqueKey = name.toLowerCase();
      }

      if (uniqueKey.isNotEmpty) {
        if (seenKeys.contains(uniqueKey)) {
          isDuplicate = true;
          errors.add('Duplicate record in file ($uniqueKey)');
          duplicateCount++;
        } else {
          seenKeys.add(uniqueKey);
        }

        if (firestoreKeys.contains(uniqueKey)) {
          existsInFirestore = true;
        }
        if (type == CsvImportType.user) {
          final email = rowMap['email'] ?? '';
          if (email.isNotEmpty && firestoreKeys.contains(email.toLowerCase())) {
            existsInFirestore = true;
          }
        }
        if (existsInFirestore) {
          existingCount++;
        }
      }

      final hasErrors = errors.isNotEmpty;
      if (hasErrors) {
        invalidCount++;
      } else {
        validCount++;
      }

      validationRows.add(CsvValidationRow(
        rowNumber: rowNumber,
        rowData: rowMap,
        errors: errors,
        hasErrors: hasErrors,
        isDuplicate: isDuplicate,
        existsInFirestore: existsInFirestore,
      ));
    }

    return CsvValidationReport(
      totalRows: dataRows.length,
      validRows: validCount,
      invalidRows: invalidCount,
      duplicateRows: duplicateCount,
      existingInFirestore: existingCount,
      rows: validationRows,
    );
  }

  /// Generates downloadable CSV content containing invalid rows and error diagnostics.
  static String generateErrorReportCsv(CsvValidationReport report) {
    final outputRows = <List<dynamic>>[];
    outputRows.add(['Row Number', 'Status', 'Errors', 'Data Details']);

    for (final row in report.rows) {
      if (row.hasErrors) {
        outputRows.add([
          row.rowNumber,
          row.isDuplicate ? 'DUPLICATE' : 'INVALID',
          row.errors.join('; '),
          jsonEncode(row.rowData),
        ]);
      }
    }

    return const ListToCsvConverter().convert(outputRows);
  }
}

class CsvValidationRow {
  final int rowNumber;
  final Map<String, dynamic> rowData;
  final List<String> errors;
  final bool hasErrors;
  final bool isDuplicate;
  final bool existsInFirestore;

  const CsvValidationRow({
    required this.rowNumber,
    required this.rowData,
    required this.errors,
    required this.hasErrors,
    required this.isDuplicate,
    required this.existsInFirestore,
  });
}

class CsvValidationReport {
  final int totalRows;
  final int validRows;
  final int invalidRows;
  final int duplicateRows;
  final int existingInFirestore;
  final List<CsvValidationRow> rows;

  const CsvValidationReport({
    required this.totalRows,
    required this.validRows,
    required this.invalidRows,
    required this.duplicateRows,
    required this.existingInFirestore,
    required this.rows,
  });
}

class _CsvRow {
  final List<dynamic> row;
  final int rowNumber;

  const _CsvRow({
    required this.row,
    required this.rowNumber,
  });
}

