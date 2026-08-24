import 'diagnostic_store.dart';

DiagnosticStore createStore() => _MemoryDiagnosticStore();

class _MemoryDiagnosticStore implements DiagnosticStore {
  final _lines = <String>[];

  @override
  Future<void> initialize() async {}

  @override
  Future<void> append(String line) async => _lines.add(line);

  @override
  Future<void> clear() async => _lines.clear();

  @override
  Future<String?> export(String content, String fileName) async => null;

  @override
  Future<String> read() async => _lines.join('\n');
}
