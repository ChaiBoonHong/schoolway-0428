import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

Future<String?> pickCsvText() async {
  final picked = await FilePickerPlatform.instance.pickFiles(
    // Android DocumentsUI reports CSV files with several valid MIME types
    // (for example `text/comma-separated-values`), while FilePicker's custom
    // CSV filter only asks for `text/csv` on some devices. Browse documents
    // without that MIME restriction and validate the selected filename below.
    type: FileType.any,
  );

  if (picked.isEmpty) {
    return null;
  }

  final file = picked.single;
  if (!file.name.toLowerCase().endsWith('.csv')) {
    throw FormatException('Please select a CSV (.csv) file.');
  }
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
