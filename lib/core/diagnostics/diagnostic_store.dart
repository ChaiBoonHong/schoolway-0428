import 'diagnostic_store_stub.dart'
    if (dart.library.io) 'diagnostic_store_io.dart'
    if (dart.library.html) 'diagnostic_store_web.dart'
    as implementation;

abstract interface class DiagnosticStore {
  Future<void> initialize();
  Future<void> append(String line);
  Future<String> read();
  Future<void> clear();
  Future<String?> export(String content, String fileName);
}

DiagnosticStore createDiagnosticStore() => implementation.createStore();
