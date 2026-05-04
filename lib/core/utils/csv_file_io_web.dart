import 'dart:async';
import 'dart:js_interop';
import 'dart:convert';

import 'package:web/web.dart' as web;

Future<String?> pickCsvText() async {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = '.csv,text/csv'
    ..multiple = false;

  final changeCompleter = Completer<void>();
  late JSFunction onChange;
  onChange = ((web.Event _) {
    input.removeEventListener('change', onChange);
    if (!changeCompleter.isCompleted) {
      changeCompleter.complete();
    }
  }).toJS;

  input.addEventListener('change', onChange);
  input.click();
  await changeCompleter.future;

  final files = input.files;
  if (files == null || files.length == 0) {
    return null;
  }

  final file = files.item(0);
  if (file == null) {
    return null;
  }

  final text = await file.text().toDart;
  return text.toDart;
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
