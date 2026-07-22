import 'dart:async';
import 'dart:js_interop';
import 'dart:convert';

import 'package:web/web.dart' as web;

Future<String?> pickCsvText() async {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = '.csv,text/csv'
    ..multiple = false;

  final completer = Completer<String?>();

  late JSFunction onChange;
  late JSFunction onCancel;

  void cleanup() {
    input.removeEventListener('change', onChange);
    input.removeEventListener('cancel', onCancel);
  }

  onChange = ((web.Event _) {
    cleanup();
    final files = input.files;
    if (files == null || files.length == 0) {
      if (!completer.isCompleted) completer.complete(null);
      return;
    }

    final file = files.item(0);
    if (file == null) {
      if (!completer.isCompleted) completer.complete(null);
      return;
    }

    final reader = web.FileReader();
    reader.onloadend = ((web.Event _) {
      final result = reader.result;
      if (!completer.isCompleted) {
        if (result != null) {
          try {
            final dartObj = result.dartify();
            if (dartObj is String) {
              completer.complete(dartObj);
            } else {
              completer.complete((result as JSString).toDart);
            }
          } catch (_) {
            completer.complete(result.toString());
          }
        } else {
          completer.complete(null);
        }
      }
    }).toJS;

    reader.onerror = ((web.Event _) {
      if (!completer.isCompleted) completer.complete(null);
    }).toJS;

    reader.readAsText(file);
  }).toJS;

  onCancel = ((web.Event _) {
    cleanup();
    if (!completer.isCompleted) {
      completer.complete(null);
    }
  }).toJS;

  input.addEventListener('change', onChange);
  input.addEventListener('cancel', onCancel);

  // Focus fallback for browsers that don't emit 'cancel' event
  late JSFunction onFocus;
  onFocus = ((web.Event _) {
    web.window.removeEventListener('focus', onFocus);
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!completer.isCompleted) {
        final files = input.files;
        if (files == null || files.length == 0) {
          cleanup();
          completer.complete(null);
        }
      }
    });
  }).toJS;
  web.window.addEventListener('focus', onFocus);

  input.click();
  return await completer.future;
}

Future<void> downloadCsvTemplate({
  required String content,
  required String fileName,
}) async {
  final encodedContent = Uri.encodeComponent(content);
  final href = 'data:text/csv;charset=utf-8,$encodedContent';

  final anchor = web.HTMLAnchorElement()
    ..href = href
    ..download = fileName
    ..style.display = 'none';

  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
}

Future<void> downloadZipFile({
  required List<int> bytes,
  required String fileName,
}) async {
  final b64 = base64Encode(bytes);
  final href = 'data:application/zip;base64,$b64';

  final anchor = web.HTMLAnchorElement()
    ..href = href
    ..download = fileName
    ..style.display = 'none';

  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
}
