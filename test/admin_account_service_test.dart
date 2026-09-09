import 'package:flutter_test/flutter_test.dart';
import 'package:schoolway/services/admin_account_service.dart';

void main() {
  test('new account passwords require eight characters', () {
    expect(
      () => AdminAccountService.validateNewPassword('1234567'),
      throwsArgumentError,
    );
    expect(
      () => AdminAccountService.validateNewPassword('12345678'),
      returnsNormally,
    );
  });
}
