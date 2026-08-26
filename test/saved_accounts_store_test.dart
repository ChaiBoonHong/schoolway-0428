import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:schoolway/models/linked_account_profile.dart';
import 'package:schoolway/services/saved_accounts_store.dart';

class FakeHiveBox implements Box<dynamic> {
  final Map<dynamic, dynamic> _data = {};

  @override
  bool get isOpen => true;

  @override
  Iterable<dynamic> get keys => _data.keys;

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      _data[key] ?? defaultValue;

  @override
  Future<void> put(dynamic key, dynamic value) async {
    _data[key] = value;
  }

  @override
  Future<void> delete(dynamic key) async {
    _data.remove(key);
  }

  @override
  Future<int> clear() async {
    final count = _data.length;
    _data.clear();
    return count;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('SavedAccountsStore Unit Tests', () {
    late FakeHiveBox fakeBox;

    setUp(() {
      fakeBox = FakeHiveBox();
      SavedAccountsStore.setMockBox(fakeBox);
    });

    tearDown(() {
      SavedAccountsStore.setMockBox(null);
    });

    test('saves and reads accounts successfully', () async {
      const p1 = LinkedAccountProfile(
        id: 'user_1',
        displayName: 'Alice User',
        email: 'alice@example.com',
        platform: AccountPlatform.email,
        isActive: true,
      );
      const p2 = LinkedAccountProfile(
        id: 'user_2',
        displayName: 'Bob Google',
        email: 'bob@gmail.com',
        platform: AccountPlatform.google,
        isActive: false,
      );

      await SavedAccountsStore.saveAccount(p1);
      await SavedAccountsStore.saveAccount(p2);

      final accounts = SavedAccountsStore.readAccounts();
      expect(accounts.length, 2);
      expect(accounts.any((a) => a.id == 'user_1' && a.isActive), isTrue);
      expect(accounts.any((a) => a.id == 'user_2' && !a.isActive), isTrue);
    });

    test('setActive updates active account state', () async {
      const p1 = LinkedAccountProfile(
        id: 'user_1',
        displayName: 'Alice User',
        email: 'alice@example.com',
        platform: AccountPlatform.email,
        isActive: true,
      );
      const p2 = LinkedAccountProfile(
        id: 'user_2',
        displayName: 'Bob Google',
        email: 'bob@gmail.com',
        platform: AccountPlatform.google,
        isActive: false,
      );

      await SavedAccountsStore.saveAccount(p1);
      await SavedAccountsStore.saveAccount(p2);

      await SavedAccountsStore.setActive('user_2');

      final accounts = SavedAccountsStore.readAccounts();
      final u1 = accounts.firstWhere((a) => a.id == 'user_1');
      final u2 = accounts.firstWhere((a) => a.id == 'user_2');

      expect(u1.isActive, isFalse);
      expect(u2.isActive, isTrue);
    });

    test('removeAccount deletes account from store', () async {
      const p1 = LinkedAccountProfile(
        id: 'user_1',
        displayName: 'Alice User',
        email: 'alice@example.com',
        platform: AccountPlatform.email,
        isActive: true,
      );

      await SavedAccountsStore.saveAccount(p1);
      expect(SavedAccountsStore.readAccounts().length, 1);

      await SavedAccountsStore.removeAccount('user_1');
      expect(SavedAccountsStore.readAccounts().isEmpty, isTrue);
    });

    test('clearAll removes all accounts from store', () async {
      const p1 = LinkedAccountProfile(
        id: 'user_1',
        displayName: 'Alice User',
        email: 'alice@example.com',
        platform: AccountPlatform.email,
      );
      const p2 = LinkedAccountProfile(
        id: 'user_2',
        displayName: 'Bob Google',
        email: 'bob@gmail.com',
        platform: AccountPlatform.google,
      );

      await SavedAccountsStore.saveAccount(p1);
      await SavedAccountsStore.saveAccount(p2);
      expect(SavedAccountsStore.readAccounts().length, 2);

      await SavedAccountsStore.clearAll();
      expect(SavedAccountsStore.readAccounts().isEmpty, isTrue);
    });
  });
}
