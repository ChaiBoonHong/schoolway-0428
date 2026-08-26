import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:schoolway/core/diagnostics/app_logger.dart';
import 'package:schoolway/models/linked_account_profile.dart';

/// Local persistent storage for real authenticated accounts on this device.
abstract final class SavedAccountsStore {
  static const boxName = 'saved_accounts';
  static Box<dynamic>? _box;

  /// Initializes the Hive storage box for saved accounts.
  static Future<void> initialize() async {
    try {
      if (_box == null || !_box!.isOpen) {
        _box = await Hive.openBox<dynamic>(boxName);
      }
    } catch (e, st) {
      AppLogger.error(
        'saved_accounts',
        'Error opening saved_accounts box, deleting from disk and reopening',
        error: e,
        stackTrace: st,
      );
      try {
        await Hive.deleteBoxFromDisk(boxName);
        _box = await Hive.openBox<dynamic>(boxName);
      } catch (innerErr, innerSt) {
        AppLogger.error(
          'saved_accounts',
          'Failed recreating saved_accounts box',
          error: innerErr,
          stackTrace: innerSt,
        );
      }
    }
  }

  @visibleForTesting
  static void setMockBox(Box<dynamic>? box) {
    _box = box;
  }

  /// Returns all stored real user accounts from local storage.
  static List<LinkedAccountProfile> readAccounts() {
    final box = _box;
    if (box == null || !box.isOpen) {
      return const [];
    }
    final list = <LinkedAccountProfile>[];
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw is Map) {
        try {
          final map = Map<String, dynamic>.from(raw);
          list.add(LinkedAccountProfile.fromMap(map));
        } catch (e, st) {
          AppLogger.warning(
            'saved_accounts',
            'Failed parsing saved account map',
            error: e,
            stackTrace: st,
          );
        }
      } else if (raw is String) {
        try {
          final map = jsonDecode(raw) as Map<String, dynamic>;
          list.add(LinkedAccountProfile.fromMap(map));
        } catch (e, st) {
          AppLogger.warning(
            'saved_accounts',
            'Failed decoding saved account JSON',
            error: e,
            stackTrace: st,
          );
        }
      }
    }
    return list;
  }

  /// Persists a real account profile to local storage.
  static Future<void> saveAccount(LinkedAccountProfile profile) async {
    final box = _box;
    if (box == null || !box.isOpen) return;
    await box.put(profile.id, jsonEncode(profile.toMap()));
  }

  /// Removes an account profile from local storage upon removal/sign out.
  static Future<void> removeAccount(String accountId) async {
    final box = _box;
    if (box == null || !box.isOpen) return;
    await box.delete(accountId);
  }

  /// Sets the active account flag locally.
  static Future<void> setActive(String accountId) async {
    final box = _box;
    if (box == null || !box.isOpen) return;
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw == null) continue;
      Map<String, dynamic>? map;
      if (raw is Map) {
        map = Map<String, dynamic>.from(raw);
      } else if (raw is String) {
        try {
          map = jsonDecode(raw) as Map<String, dynamic>;
        } catch (e, st) {
          AppLogger.warning(
            'saved_accounts',
            'Failed decoding saved account during setActive',
            error: e,
            stackTrace: st,
          );
        }
      }
      if (map != null) {
        final prof = LinkedAccountProfile.fromMap(map);
        final updated = prof.copyWith(isActive: prof.id == accountId);
        await box.put(key, jsonEncode(updated.toMap()));
      }
    }
  }
}
