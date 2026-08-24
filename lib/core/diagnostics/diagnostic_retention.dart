import 'dart:convert';

String retainDiagnosticLines(
  String content, {
  required DateTime now,
  required Duration maximumAge,
  required int maximumBytes,
}) {
  final cutoff = now.toUtc().subtract(maximumAge);
  final retained = <String>[];
  for (final line in const LineSplitter().convert(content)) {
    if (line.trim().isEmpty) continue;
    try {
      final event = jsonDecode(line) as Map<String, dynamic>;
      final timestamp = DateTime.parse(event['timestamp'] as String).toUtc();
      if (!timestamp.isBefore(cutoff)) retained.add(line);
    } catch (_) {
      // Malformed entries are discarded rather than exported.
    }
  }

  var bytes = retained.fold<int>(
    0,
    (total, line) => total + utf8.encode(line).length + 1,
  );
  while (bytes > maximumBytes && retained.isNotEmpty) {
    bytes -= utf8.encode(retained.removeAt(0)).length + 1;
  }
  return retained.isEmpty ? '' : '${retained.join('\n')}\n';
}
