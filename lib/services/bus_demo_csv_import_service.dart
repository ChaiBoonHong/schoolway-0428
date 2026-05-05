import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csv/csv.dart';
import 'package:schoolway/core/schoolway_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../models/models.dart';
import 'csv_import_service.dart';
import 'firebase_service.dart';

class DemoImportProgress {
  final String phase;
  final int current;
  final int total;

  const DemoImportProgress({
    required this.phase,
    required this.current,
    required this.total,
  });
}

class DemoImportSummary {
  final int usersImported;
  final int routesImported;
  final int busesImported;
  final int assignmentsImported;
  final int studentsImported;
  final List<String> errors;
  final bool cancelled;

  const DemoImportSummary({
    required this.usersImported,
    required this.routesImported,
    required this.busesImported,
    required this.assignmentsImported,
    required this.studentsImported,
    required this.errors,
    required this.cancelled,
  });
}

class BusDemoCsvImportService {
  static const String usersHeader =
      'username,firstName,lastName,email,password,role,gender,countryCode,phoneNumber';
  static const String routesHeader = 'routeName,stops,assignedBusId';
  static const String busesHeader =
      'busNumber,licensePlate,capacity,status,currentDriverUsername';
  static const String assignmentsHeader = 'licensePlate,routeName';
  static const String studentsHeader =
      'studentId,firstName,lastName,classId,nfcCardId,parentIds,assignedBusId,pickupStop,dropoffStop,status';

  static String usersTemplateCsv() => const ListToCsvConverter().convert([
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
          'driver_utar_01',
          'Aiman',
          'Khalid',
          'driver_utar_01@example.com',
          'TempPass123',
          'Driver',
          'Male',
          '+60',
          '123456789',
        ],
        [
          'parent_utar_001',
          'Siti',
          'Aziz',
          'parent_utar_001@example.com',
          'TempPass123',
          'Parent',
          'Female',
          '+60',
          '123456780',
        ],
      ]);

  static String routesTemplateCsv() => const ListToCsvConverter().convert([
        ['routeName', 'stops', 'assignedBusId'],
        [
          'UTAR-Westlake Loop',
          '4.33657,101.14195|4.33280,101.13860|4.32790,101.13120|4.33657,101.14195',
          'AKP 3201',
        ],
      ]);

  static String busesTemplateCsv() => const ListToCsvConverter().convert([
        ['busNumber', 'licensePlate', 'capacity', 'status', 'currentDriverUsername'],
        ['BUS-KPR-01', 'AKP 3201', '40', 'Idle', 'driver_utar_01'],
      ]);

  static String assignmentsTemplateCsv() => const ListToCsvConverter().convert([
        ['licensePlate', 'routeName'],
        ['AKP 3201', 'UTAR-Westlake Loop'],
      ]);

  static String studentsTemplateCsv() => const ListToCsvConverter().convert([
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

  static Future<DemoImportSummary> importAll({
    required String usersCsv,
    required String routesCsv,
    required String busesCsv,
    required String assignmentsCsv,
    required String studentsCsv,
    required void Function(DemoImportProgress progress) onProgress,
    required bool Function() shouldCancel,
  }) async {
    if (shouldCancel()) {
      return const DemoImportSummary(
        usersImported: 0,
        routesImported: 0,
        busesImported: 0,
        assignmentsImported: 0,
        studentsImported: 0,
        errors: [],
        cancelled: true,
      );
    }

    var usersImported = 0;
    var routesImported = 0;
    var busesImported = 0;
    var assignmentsImported = 0;
    var studentsImported = 0;
    final errors = <String>[];

    final usersRows = _parseCsv(usersCsv);
    if (shouldCancel()) {
      return const DemoImportSummary(
        usersImported: 0,
        routesImported: 0,
        busesImported: 0,
        assignmentsImported: 0,
        studentsImported: 0,
        errors: [],
        cancelled: true,
      );
    }
    final routesRows = _parseCsv(routesCsv);
    if (shouldCancel()) {
      return const DemoImportSummary(
        usersImported: 0,
        routesImported: 0,
        busesImported: 0,
        assignmentsImported: 0,
        studentsImported: 0,
        errors: [],
        cancelled: true,
      );
    }
    final busesRows = _parseCsv(busesCsv);
    if (shouldCancel()) {
      return const DemoImportSummary(
        usersImported: 0,
        routesImported: 0,
        busesImported: 0,
        assignmentsImported: 0,
        studentsImported: 0,
        errors: [],
        cancelled: true,
      );
    }
    final assignmentRows = _parseCsv(assignmentsCsv);
    if (shouldCancel()) {
      return const DemoImportSummary(
        usersImported: 0,
        routesImported: 0,
        busesImported: 0,
        assignmentsImported: 0,
        studentsImported: 0,
        errors: [],
        cancelled: true,
      );
    }
    final studentsRows = _parseCsv(studentsCsv);

    final userHeader = _headerMap(usersRows.first);
    if (shouldCancel()) {
      return const DemoImportSummary(
        usersImported: 0,
        routesImported: 0,
        busesImported: 0,
        assignmentsImported: 0,
        studentsImported: 0,
        errors: [],
        cancelled: true,
      );
    }
    final routeHeader = _headerMap(routesRows.first);
    final busHeader = _headerMap(busesRows.first);
    final assignHeader = _headerMap(assignmentRows.first);
    final studentHeader = _headerMap(studentsRows.first);

    _ensureHeaders(
      userHeader,
      const ['username', 'firstname', 'lastname', 'email', 'password', 'role'],
      'users',
    );
    if (shouldCancel()) {
      return const DemoImportSummary(
        usersImported: 0,
        routesImported: 0,
        busesImported: 0,
        assignmentsImported: 0,
        studentsImported: 0,
        errors: [],
        cancelled: true,
      );
    }
    _ensureHeaders(routeHeader, const ['routename', 'stops'], 'routes');
    _ensureHeaders(
      busHeader,
      const ['busnumber', 'licenseplate', 'capacity'],
      'buses',
    );
    _ensureHeaders(
      assignHeader,
      const ['licenseplate', 'routename'],
      'assignments',
    );
    _ensureHeaders(
      studentHeader,
      const ['studentid', 'firstname', 'lastname', 'classid', 'nfccardid'],
      'students',
    );

    var cancelled = false;

    FirebaseApp? secondaryApp;
    try {
      secondaryApp = await Firebase.initializeApp(
        name: 'BusDemoImport_${DateTime.now().microsecondsSinceEpoch}',
        options: Firebase.app().options,
      );
      final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);

      final userDataRows = _effectiveRows(usersRows, userHeader, const [
        'username',
        'firstname',
        'lastname',
        'email'
      ]);
      for (var i = 0; i < userDataRows.length; i++) {
        if (shouldCancel()) {
          cancelled = true;
          break;
        }
        if (i > 0) {
          await CsvImportService.delayBetweenCsvUserImportRows(shouldCancel);
        }
        onProgress(DemoImportProgress(
          phase: 'Users',
          current: i + 1,
          total: userDataRows.length,
        ));
        final row = userDataRows[i];
        try {
          await _createUserFromRow(
            row,
            userHeader,
            secondaryAuth,
            shouldCancel: shouldCancel,
          );
          usersImported++;
        } catch (e) {
          errors.add('Users row ${row.rowNumber}: $e');
        }
      }
    } finally {
      if (secondaryApp != null) {
        await secondaryApp.delete();
      }
    }

    if (!cancelled) {
      if (shouldCancel()) {
        cancelled = true;
      }
    }

    if (!cancelled) {
      final routeDataRows =
          _effectiveRows(routesRows, routeHeader, const ['routename']);
      for (var i = 0; i < routeDataRows.length; i++) {
        if (shouldCancel()) {
          cancelled = true;
          break;
        }
        onProgress(DemoImportProgress(
          phase: 'Routes',
          current: i + 1,
          total: routeDataRows.length,
        ));
        final row = routeDataRows[i];
        try {
          await _createOrUpdateRoute(row, routeHeader);
          routesImported++;
        } catch (e) {
          errors.add('Routes row ${row.rowNumber}: $e');
        }
      }
    }

    if (!cancelled) {
      if (shouldCancel()) {
        cancelled = true;
      }
    }

    if (!cancelled) {
      final busDataRows =
          _effectiveRows(busesRows, busHeader, const ['busnumber', 'licenseplate']);
      for (var i = 0; i < busDataRows.length; i++) {
        if (shouldCancel()) {
          cancelled = true;
          break;
        }
        onProgress(DemoImportProgress(
          phase: 'Buses',
          current: i + 1,
          total: busDataRows.length,
        ));
        final row = busDataRows[i];
        try {
          await _createOrUpdateBus(row, busHeader);
          busesImported++;
        } catch (e) {
          errors.add('Buses row ${row.rowNumber}: $e');
        }
      }
    }

    if (!cancelled) {
      if (shouldCancel()) {
        cancelled = true;
      }
    }

    if (!cancelled) {
      final assignmentDataRows = _effectiveRows(
        assignmentRows,
        assignHeader,
        const ['licenseplate', 'routename'],
      );
      for (var i = 0; i < assignmentDataRows.length; i++) {
        if (shouldCancel()) {
          cancelled = true;
          break;
        }
        onProgress(DemoImportProgress(
          phase: 'Assignments',
          current: i + 1,
          total: assignmentDataRows.length,
        ));
        final row = assignmentDataRows[i];
        try {
          await _assignRouteToBus(row, assignHeader);
          assignmentsImported++;
        } catch (e) {
          errors.add('Assignments row ${row.rowNumber}: $e');
        }
      }
    }

    if (!cancelled) {
      if (shouldCancel()) {
        cancelled = true;
      }
    }

    if (!cancelled) {
      final studentDataRows = _effectiveRows(
        studentsRows,
        studentHeader,
        const ['studentid', 'firstname', 'lastname'],
      );
      final parentStudentCounts = await _loadParentStudentCounts();
      final parentPickupStop = await _loadParentPickupStops();

      for (var i = 0; i < studentDataRows.length; i++) {
        if (shouldCancel()) {
          cancelled = true;
          break;
        }
        onProgress(DemoImportProgress(
          phase: 'Students',
          current: i + 1,
          total: studentDataRows.length,
        ));
        final row = studentDataRows[i];
        try {
          await _createStudentWithRules(
            row,
            studentHeader,
            parentStudentCounts,
            parentPickupStop,
          );
          studentsImported++;
        } catch (e) {
          errors.add('Students row ${row.rowNumber}: $e');
        }
      }
    }

    return DemoImportSummary(
      usersImported: usersImported,
      routesImported: routesImported,
      busesImported: busesImported,
      assignmentsImported: assignmentsImported,
      studentsImported: studentsImported,
      errors: errors,
      cancelled: cancelled,
    );
  }

  static List<List<dynamic>> _parseCsv(String content) {
    var text = content;
    if (text.startsWith('\uFEFF')) {
      text = text.substring(1);
    }
    final rows = const CsvToListConverter(shouldParseNumbers: false).convert(text);
    if (rows.length < 2) {
      throw Exception('CSV must contain header and at least one data row.');
    }
    return rows;
  }

  static Map<String, int> _headerMap(List<dynamic> headerRow) {
    final map = <String, int>{};
    for (var i = 0; i < headerRow.length; i++) {
      final key = _cell(headerRow[i]).toLowerCase();
      if (key.isNotEmpty) map[key] = i;
    }
    return map;
  }

  static void _ensureHeaders(
    Map<String, int> headerIndex,
    List<String> required,
    String label,
  ) {
    for (final key in required) {
      if (!headerIndex.containsKey(key)) {
        throw Exception('Missing required column "$key" in $label CSV.');
      }
    }
  }

  static List<_CsvRow> _effectiveRows(
    List<List<dynamic>> rows,
    Map<String, int> headerIndex,
    List<String> keys,
  ) {
    final out = <_CsvRow>[];
    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      var hasData = false;
      for (final key in keys) {
        if (_value(row, headerIndex, key).isNotEmpty) {
          hasData = true;
          break;
        }
      }
      if (!hasData) continue;
      out.add(_CsvRow(row: row, rowNumber: i + 1));
    }
    return out;
  }

  static String _cell(dynamic value) => value?.toString().trim() ?? '';

  static String _value(List<dynamic> row, Map<String, int> header, String key) {
    final index = header[key];
    if (index == null || index >= row.length) return '';
    return _cell(row[index]);
  }

  static Future<void> _createUserFromRow(
    _CsvRow csvRow,
    Map<String, int> header,
    FirebaseAuth secondaryAuth, {
    bool Function()? shouldCancel,
  }) async {
    final username = _value(csvRow.row, header, 'username');
    final firstName = _value(csvRow.row, header, 'firstname');
    final lastName = _value(csvRow.row, header, 'lastname');
    final email = _value(csvRow.row, header, 'email');
    final password = _value(csvRow.row, header, 'password');
    final role = _normalizeRole(_value(csvRow.row, header, 'role'));
    final gender = _value(csvRow.row, header, 'gender');
    final phone = _value(csvRow.row, header, 'phonenumber');
    final countryCode = _value(csvRow.row, header, 'countrycode');

    if (username.isEmpty ||
        firstName.isEmpty ||
        lastName.isEmpty ||
        email.isEmpty ||
        password.isEmpty) {
      throw Exception('Required fields missing.');
    }
    if (role.isEmpty) {
      throw Exception('Role must be Parent, Driver, or Admin.');
    }

    final usernameDoc = await swFirestore
        .collection('users')
        .doc(username)
        .get();
    if (usernameDoc.exists) {
      return;
    }

    UserCredential? credential;
    var createdAuthUser = false;
    try {
      try {
        credential =
            await CsvImportService.runWithFirebaseAuthRateLimitRetries<
                UserCredential>(
          () => secondaryAuth.createUserWithEmailAndPassword(
            email: email,
            password: password,
          ),
          shouldCancel: shouldCancel,
        );
        createdAuthUser = true;
      } on FirebaseAuthException catch (e) {
        if (e.code != 'email-already-in-use') rethrow;
        credential =
            await CsvImportService.runWithFirebaseAuthRateLimitRetries<
                UserCredential>(
          () => secondaryAuth.signInWithEmailAndPassword(
            email: email,
            password: password,
          ),
          shouldCancel: shouldCancel,
        );
      }

      final authUid = credential.user?.uid;
      if (authUid == null) throw Exception('Unable to create auth account.');

      await swFirestore.collection('users').doc(username).set({
        'authUid': authUid,
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'phoneNumber': phone,
        'countryCode': countryCode.isEmpty ? '+60' : countryCode,
        'gender': gender.isEmpty ? 'Other' : gender,
        'role': role,
        'emailVerified': false,
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      if (createdAuthUser && credential?.user != null) {
        try {
          await credential!.user!.delete();
        } catch (_) {}
      }
      rethrow;
    } finally {
      if (secondaryAuth.currentUser != null) {
        await secondaryAuth.signOut();
      }
    }
  }

  static String _normalizeRole(String raw) {
    switch (raw.trim().toLowerCase()) {
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

  static Future<void> _createOrUpdateRoute(
    _CsvRow csvRow,
    Map<String, int> header,
  ) async {
    final routeName = _value(csvRow.row, header, 'routename');
    final stopsRaw = _value(csvRow.row, header, 'stops');
    if (routeName.isEmpty || stopsRaw.isEmpty) {
      throw Exception('routeName and stops are required.');
    }
    final stops = _parseStopPairs(stopsRaw);
    if (stops.isEmpty) {
      throw Exception('At least one stop is required.');
    }

    final existing = await swFirestore
        .collection('planned_routes')
        .where('name', isEqualTo: routeName)
        .limit(1)
        .get();

    final route = PlannedRoute(
      id: existing.docs.isEmpty ? '' : existing.docs.first.id,
      name: routeName,
      stops: stops,
      waypoints: stops,
      createdAt: existing.docs.isEmpty
          ? DateTime.now()
          : PlannedRoute.fromFirestore(existing.docs.first).createdAt,
      updatedAt: existing.docs.isEmpty ? null : DateTime.now(),
    );
    await FirebaseService.savePlannedRoute(route);
  }

  static List<RouteWaypoint> _parseStopPairs(String raw) {
    final pairs = raw.split('|').map((e) => e.trim()).where((e) => e.isNotEmpty);
    final out = <RouteWaypoint>[];
    for (final p in pairs) {
      final parts = p.split(',');
      if (parts.length != 2) {
        throw Exception('Invalid stop pair "$p". Expected "lat,lng".');
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

  static Future<void> _createOrUpdateBus(
    _CsvRow csvRow,
    Map<String, int> header,
  ) async {
    final busNumber = _value(csvRow.row, header, 'busnumber');
    final licensePlate = _value(csvRow.row, header, 'licenseplate');
    final capacity = int.tryParse(_value(csvRow.row, header, 'capacity')) ?? 40;
    final status = _value(csvRow.row, header, 'status').isEmpty
        ? 'Idle'
        : _value(csvRow.row, header, 'status');
    final driverUsername = _value(csvRow.row, header, 'currentdriverusername');

    if (busNumber.isEmpty || licensePlate.isEmpty) {
      throw Exception('busNumber and licensePlate are required.');
    }

    final busId = _busDocIdFromPlate(licensePlate);
    String? driverAuthUid;
    if (driverUsername.isNotEmpty) {
      final driverDoc = await swFirestore
          .collection('users')
          .doc(driverUsername)
          .get();
      if (!driverDoc.exists) {
        throw Exception('Driver "$driverUsername" not found.');
      }
      final data = driverDoc.data();
      if ((data?['role'] as String?)?.toLowerCase() != 'driver') {
        throw Exception('User "$driverUsername" is not a driver.');
      }
      driverAuthUid = data?['authUid'] as String?;
    }

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
  }

  static String _busDocIdFromPlate(String plate) {
    return plate.replaceAll(RegExp(r'[^a-zA-Z0-9\-_~!*()]'), '_');
  }

  static Future<void> _assignRouteToBus(
    _CsvRow csvRow,
    Map<String, int> header,
  ) async {
    final plate = _value(csvRow.row, header, 'licenseplate');
    final routeName = _value(csvRow.row, header, 'routename');
    if (plate.isEmpty || routeName.isEmpty) {
      throw Exception('licensePlate and routeName are required.');
    }

    final busId = _busDocIdFromPlate(plate);
    final busDoc =
        await swFirestore.collection('buses').doc(busId).get();
    if (!busDoc.exists) {
      throw Exception('Bus "$plate" not found.');
    }

    final routeSnap = await swFirestore
        .collection('planned_routes')
        .where('name', isEqualTo: routeName)
        .limit(1)
        .get();
    if (routeSnap.docs.isEmpty) {
      throw Exception('Route "$routeName" not found.');
    }
    final route = PlannedRoute.fromFirestore(routeSnap.docs.first);

    await swFirestore.collection('buses').doc(busId).update({
      'assignedRouteId': route.id,
      'currentRoute': route.name,
    });
    await FirebaseService.syncAssignedRouteForStudentsOnBus(busId);
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
    final map = <String, String>{};
    for (final doc in snapshot.docs) {
      final student = Student.fromFirestore(doc);
      if (student.pickupStop == null || student.pickupStop!.trim().isEmpty) {
        continue;
      }
      final stop = student.pickupStop!.trim();
      for (final parent in student.parentIds) {
        map[parent] ??= stop;
      }
    }
    return map;
  }

  static Future<void> _createStudentWithRules(
    _CsvRow csvRow,
    Map<String, int> header,
    Map<String, int> parentStudentCounts,
    Map<String, String> parentPickupStops,
  ) async {
    final studentId = _value(csvRow.row, header, 'studentid');
    final firstName = _value(csvRow.row, header, 'firstname');
    final lastName = _value(csvRow.row, header, 'lastname');
    final classId = _value(csvRow.row, header, 'classid');
    final nfcCardId = _value(csvRow.row, header, 'nfccardid');
    final parentIds = _value(csvRow.row, header, 'parentids')
        .split('|')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final assignedBusRaw = _value(csvRow.row, header, 'assignedbusid');
    final pickupRaw = _value(csvRow.row, header, 'pickupstop');
    final dropoffStop = _value(csvRow.row, header, 'dropoffstop');
    final status = _value(csvRow.row, header, 'status').toLowerCase() == 'inactive'
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

    for (final parent in parentIds) {
      final parentDoc =
          await swFirestore.collection('users').doc(parent).get();
      if (!parentDoc.exists) {
        throw Exception('Parent "$parent" does not exist.');
      }
      final role = (parentDoc.data()?['role'] as String?)?.toLowerCase() ?? '';
      if (role != 'parent') {
        throw Exception('User "$parent" is not a parent.');
      }
    }

    final pickupStop = CsvImportService.reconcileImportedPickupStop(
      pickupRaw: pickupRaw,
      parentIds: parentIds,
      parentPickupStops: parentPickupStops,
    );

    final documentId = studentId.replaceAll('/', '_');
    final existingStudent = await swFirestore
        .collection('students')
        .doc(documentId)
        .get();
    if (existingStudent.exists) return;

    final existingNfc = await swFirestore
        .collection('students')
        .where('nfcCardId', isEqualTo: nfcCardId)
        .limit(1)
        .get();
    if (existingNfc.docs.isNotEmpty) {
      throw Exception('nfcCardId "$nfcCardId" already exists.');
    }

    final assignedBusId = await _resolveBusId(assignedBusRaw);
    String? assignedRouteId;
    if (assignedBusId != null) {
      final bus = await FirebaseService.getBusById(assignedBusId);
      assignedRouteId = bus?.assignedRouteId;
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
      if (pickupStop.isNotEmpty) {
        parentPickupStops[parent] = pickupStop;
      }
    }
  }

  static Future<String?> _resolveBusId(String raw) async {
    final value = raw.trim();
    if (value.isEmpty) return null;

    final byDoc =
        await swFirestore.collection('buses').doc(value).get();
    if (byDoc.exists) return byDoc.id;

    final byPlateDocId =
        await swFirestore.collection('buses').doc(_busDocIdFromPlate(value)).get();
    if (byPlateDocId.exists) return byPlateDocId.id;

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
}

class _CsvRow {
  final List<dynamic> row;
  final int rowNumber;

  const _CsvRow({required this.row, required this.rowNumber});
}
