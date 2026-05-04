import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';

Future<String?> pickCsvText() async {
  final picked = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['csv'],
    withData: true,
  );

  if (picked == null || picked.files.isEmpty) {
    return null;
  }

  final file = picked.files.single;
  if (file.bytes != null) {
    return utf8.decode(file.bytes!, allowMalformed: true);
  }

  if (file.path == null) {
    throw Exception('Unable to read selected file.');
  }

  return File(file.path!).readAsString();
}

Future<void> downloadCsvTemplate({
  required String content,
  required String fileName,
}) async {
  final savePath = await FilePicker.platform.saveFile(
    dialogTitle: 'Save CSV template',
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: const ['csv'],
  );

  if (savePath == null) {
    return;
  }

  await File(savePath).writeAsString(content);
}

Future<void> downloadZipFile({
  required List<int> bytes,
  required String fileName,
}) async {
  final savePath = await FilePicker.platform.saveFile(
    dialogTitle: 'Save ZIP export',
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: const ['zip'],
  );

  if (savePath == null) {
    return;
  }

  await File(savePath).writeAsBytes(bytes, flush: true);
}
