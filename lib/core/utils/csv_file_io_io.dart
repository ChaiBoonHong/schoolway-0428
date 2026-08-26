import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

Future<String?> pickCsvText() async {
  final picked = await FilePickerPlatform.instance.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['csv'],
  );

  if (picked.isEmpty) {
    return null;
  }

  final file = picked.single;
  final bytes = await file.readAsBytes();
  return utf8.decode(bytes, allowMalformed: true);
}

Future<void> downloadCsvTemplate({
  required String content,
  required String fileName,
}) async {
  await FilePickerPlatform.instance.saveFile(
    dialogTitle: 'Save CSV template',
    fileName: fileName,
    bytes: Uint8List.fromList(utf8.encode(content)),
    mimeType: 'text/csv',
  );
}

Future<void> downloadZipFile({
  required List<int> bytes,
  required String fileName,
}) async {
  await FilePickerPlatform.instance.saveFile(
    dialogTitle: 'Save ZIP export',
    fileName: fileName,
    bytes: bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
    mimeType: 'application/zip',
  );
}
