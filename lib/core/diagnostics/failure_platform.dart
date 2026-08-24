import 'failure_platform_stub.dart'
    if (dart.library.io) 'failure_platform_io.dart'
    as implementation;

bool isNetworkFailure(Object error) => implementation.isNetworkFailure(error);
bool isStorageFailure(Object error) => implementation.isStorageFailure(error);
