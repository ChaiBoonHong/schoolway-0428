import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'diagnostic_store.dart';
import 'diagnostic_retention.dart';

DiagnosticStore createStore() => _WebDiagnosticStore();

class _WebDiagnosticStore implements DiagnosticStore {
  static const _key = 'schoolway.diagnostics.v1';
  static const _maximumBytes = 5 * 1024 * 1024;

  @override
  Future<void> initialize() async => _trim();

  @override
  Future<void> append(String line) async {
    final existing = web.window.localStorage.getItem(_key) ?? '';
    web.window.localStorage.setItem(_key, '$existing$line\n');
    _trim();
  }

  void _trim() {
    final content = retainDiagnosticLines(
      web.window.localStorage.getItem(_key) ?? '',
      now: DateTime.now(),
      maximumAge: const Duration(days: 7),
      maximumBytes: _maximumBytes,
    );
    web.window.localStorage.setItem(_key, content);
  }

  @override
  Future<String> read() async => web.window.localStorage.getItem(_key) ?? '';

  @override
  Future<void> clear() async => web.window.localStorage.removeItem(_key);

  @override
  Future<String?> export(String content, String fileName) async {
    final bytes = utf8.encode(content).toJS;
    final blob = web.Blob(
      [bytes].toJS,
      web.BlobPropertyBag(type: 'application/x-ndjson'),
    );
    final url = web.URL.createObjectURL(blob);
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = fileName
      ..style.display = 'none';
    web.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    web.URL.revokeObjectURL(url);
    return null;
  }
}
