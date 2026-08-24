import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'diagnostic_store.dart';
import 'diagnostic_retention.dart';

DiagnosticStore createStore() => _IoDiagnosticStore();

class _IoDiagnosticStore implements DiagnosticStore {
  static const _fileCount = 5;
  static const _fileLimit = 1024 * 1024;
  late Directory _directory;

  File _file(int index) => File('${_directory.path}/diagnostics-$index.jsonl');

  @override
  Future<void> initialize() async {
    final support = await getApplicationSupportDirectory();
    _directory = Directory('${support.path}/diagnostics');
    await _directory.create(recursive: true);
    final compacted = retainDiagnosticLines(
      await read(),
      now: DateTime.now(),
      maximumAge: const Duration(days: 7),
      maximumBytes: _fileCount * _fileLimit,
    );
    await clear();
    if (compacted.isNotEmpty) {
      final lines = compacted.trimRight().split('\n');
      for (final line in lines) {
        await append(line);
      }
    }
  }

  @override
  Future<void> append(String line) async {
    final active = _file(0);
    if (await active.exists() && await active.length() >= _fileLimit) {
      final oldest = _file(_fileCount - 1);
      if (await oldest.exists()) await oldest.delete();
      for (var index = _fileCount - 2; index >= 0; index--) {
        final source = _file(index);
        if (await source.exists()) await source.rename(_file(index + 1).path);
      }
    }
    await _file(0).writeAsString('$line\n', mode: FileMode.append, flush: true);
  }

  @override
  Future<String> read() async {
    final parts = <String>[];
    for (var index = _fileCount - 1; index >= 0; index--) {
      final file = _file(index);
      if (await file.exists()) parts.add(await file.readAsString());
    }
    return parts.join();
  }

  @override
  Future<void> clear() async {
    for (var index = 0; index < _fileCount; index++) {
      final file = _file(index);
      if (await file.exists()) await file.delete();
    }
  }

  @override
  Future<String?> export(String content, String fileName) async {
    final cache = await getTemporaryDirectory();
    final file = File('${cache.path}/$fileName');
    await file.writeAsString(content, flush: true);
    return file.path;
  }
}
