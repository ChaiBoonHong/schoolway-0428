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
  });
}
