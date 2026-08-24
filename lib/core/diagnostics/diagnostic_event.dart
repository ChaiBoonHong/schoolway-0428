import 'dart:convert';

enum AppLogLevel { debug, info, warning, error, fatal }

class DiagnosticEvent {
  const DiagnosticEvent({
    required this.timestamp,
    required this.level,
    required this.category,
    required this.message,
    required this.sessionId,
    required this.appVersion,
    required this.platform,
    this.incidentId,
    this.errorType,
    this.stackTrace,
  });

  final DateTime timestamp;
  final AppLogLevel level;
  final String category;
  final String message;
  final String sessionId;
  final String appVersion;
  final String platform;
  final String? incidentId;
  final String? errorType;
  final String? stackTrace;

  Map<String, Object?> toJson() => {
    'timestamp': timestamp.toUtc().toIso8601String(),
    'level': level.name,
    'category': category,
    'message': message,
    'sessionId': sessionId,
    'appVersion': appVersion,
    'platform': platform,
    if (incidentId != null) 'incidentId': incidentId,
    if (errorType != null) 'errorType': errorType,
    if (stackTrace != null) 'stackTrace': stackTrace,
  };

  String toJsonLine() => jsonEncode(toJson());
}

class DiagnosticSummary {
  const DiagnosticSummary({
    required this.bytes,
    required this.eventCount,
    this.oldest,
    this.newest,
    this.latestIncidentId,
  });

  final int bytes;
  final int eventCount;
  final DateTime? oldest;
  final DateTime? newest;
  final String? latestIncidentId;
}
