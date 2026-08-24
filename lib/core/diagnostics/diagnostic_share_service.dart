import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

import 'app_logger.dart';

abstract final class DiagnosticShareService {
  static String _fileName() {
    final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      RegExp(r'[:.]'),
      '-',
    );
    return 'schoolway-diagnostics-$timestamp.jsonl';
  }

  static Future<bool> exportAndShare() async {
    final path = await AppLogger.export();
    if (path == null) return false;
    await SharePlus.instance.share(
      ShareParams(files: [XFile(path)], subject: 'SchoolWay diagnostics'),
    );
    return true;
  }

  static Future<bool> saveOrDownload() async {
    final content = await AppLogger.read();
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save SchoolWay diagnostics',
      fileName: _fileName(),
      bytes: Uint8List.fromList(utf8.encode(content)),
    );
    return path != null;
  }
}
