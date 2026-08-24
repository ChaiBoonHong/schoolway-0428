import 'package:schoolway/l10n/app_localizations.dart';

import 'app_failure.dart';

extension AppFailureLocalization on AppFailure {
  String localizedMessage(AppLocalizations strings) => switch (messageKey) {
    'authentication' => strings.authenticationError,
    'authorization' => strings.authorizationError,
    'validation' => strings.validationError,
    'network' => strings.networkError,
    'timeout' => strings.timeoutError,
    'unavailable' => strings.unavailableError,
    'storage' => strings.storageError,
    'location' => strings.locationError,
    'nfc' => strings.nfcError,
    'notification' => strings.notificationError,
    'conflict' => strings.conflictError,
    'notFound' => strings.notFoundError,
    _ => strings.unknownError,
  };
}
