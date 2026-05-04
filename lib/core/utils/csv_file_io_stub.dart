Future<String?> pickCsvText() {
  throw UnsupportedError('CSV import is not supported on this platform.');
}

Future<void> downloadCsvTemplate({
  required String content,
  required String fileName,
}) {
  throw UnsupportedError('CSV template download is not supported on this platform.');
}

Future<void> downloadZipFile({
  required List<int> bytes,
  required String fileName,
}) {
  throw UnsupportedError('ZIP download is not supported on this platform.');
}
