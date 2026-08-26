import 'package:flutter/foundation.dart';

/// Supported authentication platforms for linked profiles.
enum AccountPlatform {
  email,
  google;

  String get id => name;

  static AccountPlatform fromString(String? value) {
    final lower = (value ?? '').toLowerCase();
    if (lower == 'google' || lower.contains('google')) {
      return AccountPlatform.google;
    }
    return AccountPlatform.email;
  }
}

/// Immutable domain model representing a linked user account/profile.
@immutable
class LinkedAccountProfile {
  final String id;
  final String displayName;
  final String email;
  final String? avatarUrl;
  final AccountPlatform platform;
  final bool isActive;
  final int unreadCount;
  final String? sessionToken;
  final DateTime? lastActiveAt;
  final Map<String, dynamic> metadata;

  const LinkedAccountProfile({
    required this.id,
    required this.displayName,
    required this.email,
    this.avatarUrl,
    required this.platform,
    this.isActive = false,
    this.unreadCount = 0,
    this.sessionToken,
    this.lastActiveAt,
    this.metadata = const <String, dynamic>{},
  });

  /// Derives 1-2 character uppercase initials for avatar monogram fallback.
  String get initials {
    final clean = displayName.replaceAll(RegExp(r'[^a-zA-Z0-9\s]'), ' ').trim();
    final parts = clean
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      final cleanEmail = email.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
      return cleanEmail.isNotEmpty
          ? cleanEmail.substring(0, 1).toUpperCase()
          : '?';
    }
    if (parts.length == 1) {
      final part = parts.first;
      return part.length >= 2
          ? part.substring(0, 2).toUpperCase()
          : part.substring(0, 1).toUpperCase();
    }
    return '${parts.first[0]}${parts[1][0]}'.toUpperCase();
  }

  LinkedAccountProfile copyWith({
    String? id,
    String? displayName,
    String? email,
    String? avatarUrl,
    AccountPlatform? platform,
    bool? isActive,
    int? unreadCount,
    String? sessionToken,
    DateTime? lastActiveAt,
    Map<String, dynamic>? metadata,
  }) {
    return LinkedAccountProfile(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      platform: platform ?? this.platform,
      isActive: isActive ?? this.isActive,
      unreadCount: unreadCount ?? this.unreadCount,
      sessionToken: sessionToken ?? this.sessionToken,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'displayName': displayName,
      'email': email,
      'avatarUrl': avatarUrl,
      'platform': platform.name,
      'isActive': isActive,
      'unreadCount': unreadCount,
      'sessionToken': sessionToken,
      'lastActiveAt': lastActiveAt?.toIso8601String(),
      'metadata': metadata,
    };
  }

  factory LinkedAccountProfile.fromMap(Map<String, dynamic> map) {
    return LinkedAccountProfile(
      id: map['id'] as String? ?? '',
      displayName: map['displayName'] as String? ?? '',
      email: map['email'] as String? ?? '',
      avatarUrl: map['avatarUrl'] as String?,
      platform: AccountPlatform.fromString(map['platform'] as String?),
      isActive: map['isActive'] as bool? ?? false,
      unreadCount: (map['unreadCount'] as num?)?.toInt() ?? 0,
      sessionToken: map['sessionToken'] as String?,
      lastActiveAt: map['lastActiveAt'] != null
          ? DateTime.tryParse(map['lastActiveAt'] as String)
          : null,
      metadata: map['metadata'] is Map
          ? Map<String, dynamic>.from(map['metadata'] as Map)
          : const <String, dynamic>{},
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LinkedAccountProfile &&
        other.id == id &&
        other.displayName == displayName &&
        other.email == email &&
        other.avatarUrl == avatarUrl &&
        other.platform == platform &&
        other.isActive == isActive &&
        other.unreadCount == unreadCount &&
        other.sessionToken == sessionToken &&
        other.lastActiveAt == lastActiveAt &&
        mapEquals(other.metadata, metadata);
  }

  @override
  int get hashCode => Object.hash(
    id,
    displayName,
    email,
    avatarUrl,
    platform,
    isActive,
    unreadCount,
    sessionToken,
    lastActiveAt,
  );
}
