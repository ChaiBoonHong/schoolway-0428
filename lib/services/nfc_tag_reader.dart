import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:nfc_manager/nfc_manager_ios.dart';
import 'package:ndef_record/ndef_record.dart';

String _bytesToHex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();

String? _decodeWellKnownText(NdefMessage? msg) {
  if (msg == null) return null;
  for (final r in msg.records) {
    if (r.typeNameFormat == TypeNameFormat.wellKnown &&
        r.type.length == 1 &&
        r.type[0] == 0x54) {
      final payload = r.payload;
      if (payload.length < 2) continue;
      final langLen = payload[0] & 0x3f;
      if (payload.length <= 1 + langLen) continue;
      try {
        return utf8.decode(payload.sublist(1 + langLen));
      } catch (_) {}
    }
  }
  return null;
}

/// Reads a stable identifier from an NFC tag (NDEF text, or hardware UID).
Future<String?> readNfcTagIdentifier(NfcTag tag) async {
  if (defaultTargetPlatform == TargetPlatform.android) {
    final androidTag = NfcTagAndroid.from(tag);
    if (androidTag != null) {
      return _bytesToHex(androidTag.id);
    }
    final ndef = NdefAndroid.from(tag);
    if (ndef != null) {
      final msg = ndef.cachedNdefMessage ?? await ndef.getNdefMessage();
      final text = _decodeWellKnownText(msg);
      if (text != null && text.trim().isNotEmpty) return text.trim();
    }
  } else if (defaultTargetPlatform == TargetPlatform.iOS) {
    final mi = MiFareIos.from(tag);
    if (mi != null) {
      return _bytesToHex(mi.identifier);
    }
    final ndef = NdefIos.from(tag);
    if (ndef != null) {
      final msg = ndef.cachedNdefMessage ?? await ndef.readNdef();
      final text = _decodeWellKnownText(msg);
      if (text != null && text.trim().isNotEmpty) return text.trim();
    }
  }
  return null;
}
