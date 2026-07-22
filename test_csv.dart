import 'dart:io';
import 'package:csv/csv.dart';

void main() {
  var csvText = File('seed/users.csv').readAsStringSync();
  var content = csvText.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
  if (content.startsWith('\uFEFF')) content = content.substring(1);
  final rawRows = const CsvToListConverter(shouldParseNumbers: false, eol: '\n').convert(content);
  final rows = rawRows
      .where((r) => r.isNotEmpty && r.any((cell) => cell.toString().trim().isNotEmpty))
      .toList();
  stdout.writeln(rows.length);
  if (rows.length < 2) {
    stdout.writeln('Failed length: ${rows.length}');
  }
}
