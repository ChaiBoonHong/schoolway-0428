import 'dart:io';

bool isNetworkFailure(Object error) => error is SocketException;
bool isStorageFailure(Object error) => error is FileSystemException;
