import 'package:flutter_test/flutter_test.dart';
import 'package:schoolway/services/csv_import_service.dart';

void main() {
  group('CSV type handling', () {
    test('detects users and buses from their headers', () {
      const usersCsv =
          'username,firstName,lastName,email,password,role\n'
          'driver_1,Aiman,Khalid,driver_1@schoolway.com,12345678,Driver';
      const busesCsv =
          'busNumber,licensePlate,capacity,status,currentDriverUsername\n'
          'BUS-SW-01,SWY 3001,30,Idle,driver_1';

      expect(CsvImportService.detectCsvType(usersCsv), CsvImportType.user);
      expect(CsvImportService.detectCsvType(busesCsv), CsvImportType.bus);
    });

    test('templates expose usernames instead of Auth UIDs', () {
      final busTemplate = CsvImportService.templateCsv(CsvImportType.bus);
      final studentTemplate = CsvImportService.templateCsv(
        CsvImportType.student,
      );

      expect(busTemplate, contains('currentDriverUsername'));
      expect(studentTemplate, contains('parentUsernames'));
      expect(studentTemplate, isNot(contains('parentAuthUids')));
    });

    test('result summary keeps the type that was actually imported', () {
      const result = CsvImportResult(
        imported: 20,
        failed: 0,
        cancelled: false,
        errors: [],
      );

      expect(result.summaryFor(CsvImportType.user), contains('Type: User'));
      expect(
        result.summaryFor(CsvImportType.user),
        isNot(contains('Type: Bus')),
      );
    });

    test(
      'result summary caps row errors without hiding the remaining count',
      () {
        const result = CsvImportResult(
          imported: 0,
          failed: 3,
          cancelled: false,
          errors: ['first', 'second', 'third'],
        );

        final summary = result.summaryFor(CsvImportType.bus, maximumErrors: 2);
        expect(summary, contains('first'));
        expect(summary, contains('second'));
        expect(summary, isNot(contains('third')));
        expect(summary, contains('... and 1 more error(s).'));
      },
    );

    test(
      'resolveEffectiveImportStops provides bidirectional stop fallback',
      () {
        // 1. Only pickupStop provided -> dropoff defaults to pickup
        final fromPickup = CsvImportService.resolveEffectiveImportStops(
          pickupRaw: 'Stop 1 (4.31538, 101.12307)',
        );
        expect(fromPickup.pickupStop, 'Stop 1 (4.31538, 101.12307)');
        expect(fromPickup.dropoffStop, 'Stop 1 (4.31538, 101.12307)');

        // 2. Only dropoffStop provided -> pickup defaults to dropoff
        final fromDropoff = CsvImportService.resolveEffectiveImportStops(
          dropoffRaw: 'Stop 3 (4.32272, 101.12506)',
        );
        expect(fromDropoff.pickupStop, 'Stop 3 (4.32272, 101.12506)');
        expect(fromDropoff.dropoffStop, 'Stop 3 (4.32272, 101.12506)');

        // 3. Only assignedStop provided -> both default to assignedStop
        final fromAssigned = CsvImportService.resolveEffectiveImportStops(
          assignedStopRaw: 'Stop 2 (4.32118, 101.12362)',
        );
        expect(fromAssigned.pickupStop, 'Stop 2 (4.32118, 101.12362)');
        expect(fromAssigned.dropoffStop, 'Stop 2 (4.32118, 101.12362)');

        // 4. Both pickup and dropoff provided -> keep independent
        final both = CsvImportService.resolveEffectiveImportStops(
          pickupRaw: 'Stop 1',
          dropoffRaw: 'Stop 4',
        );
        expect(both.pickupStop, 'Stop 1');
        expect(both.dropoffStop, 'Stop 4');
      },
    );
  });
}
