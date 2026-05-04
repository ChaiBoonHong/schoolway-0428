import 'csv_file_io_stub.dart'
    if (dart.library.html) 'csv_file_io_web.dart'
    if (dart.library.io) 'csv_file_io_io.dart' as impl;

Future<String?> pickCsvText() => impl.pickCsvText();

Future<void> downloadCsvTemplate({
  required String content,
  required String fileName,
}) {
  return impl.downloadCsvTemplate(content: content, fileName: fileName);
}

Future<void> downloadZipFile({
  required List<int> bytes,
  required String fileName,
}) {
  return impl.downloadZipFile(bytes: bytes, fileName: fileName);
}
