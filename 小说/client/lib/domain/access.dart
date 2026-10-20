/// Local self-declaration, discovery preference and concealment are independent.
enum RatingLevel { general, mature, restricted, unknown, prohibited }

enum SourceAccess {
  notRequired,
  allowed,
  loginRequired,
  ageRequired,
  paid,
  expired,
  unknown,
}

final class ContentRating {
  const ContentRating({
    required this.level,
    this.raw,
    this.minimumAge,
    this.originalRegions = const [],
    this.evidence,
    this.policyVersion = 'local-v1',
    this.sourceAccess = SourceAccess.unknown,
  });
  final RatingLevel level;
  final String? raw, evidence;
  final int? minimumAge;
  final List<String> originalRegions;
  final String policyVersion;
  final SourceAccess sourceAccess;
  bool get protected =>
      level == RatingLevel.mature ||
      level == RatingLevel.restricted ||
      (minimumAge ?? 0) >= 18;
}

final class AccessState {
  const AccessState({
    this.acknowledged = false,
    this.includeAdultSources = false,
    this.privacyLocked = false,
    this.revision = 0,
    this.visibilityRevision = 0,
  });
  final bool acknowledged, includeAdultSources, privacyLocked;
  final int revision, visibilityRevision;
  bool get adultVisible => acknowledged && !privacyLocked;
  bool get adultDiscovery => adultVisible && includeAdultSources;
  AccessState copy({
    bool? acknowledged,
    bool? includeAdultSources,
    bool? privacyLocked,
    int? revision,
    int? visibilityRevision,
  }) => AccessState(
    acknowledged: acknowledged ?? this.acknowledged,
    includeAdultSources: includeAdultSources ?? this.includeAdultSources,
    privacyLocked: privacyLocked ?? this.privacyLocked,
    revision: revision ?? this.revision,
    visibilityRevision: visibilityRevision ?? this.visibilityRevision,
  );
  Map<String, Object> toLocalJson() => {
    'schema_version': 1,
    'statement_version': 'adult-v1',
    'acknowledged': acknowledged,
    'include_adult_sources': includeAdultSources,
    'privacy_locked': privacyLocked,
  };
  factory AccessState.fromLocalJson(Map<String, dynamic> json) {
    const keys = {
      'schema_version',
      'statement_version',
      'acknowledged',
      'include_adult_sources',
      'privacy_locked',
    };
    if (json.keys.toSet().difference(keys).isNotEmpty ||
        json.length != keys.length ||
        json['schema_version'] != 1 ||
        json['statement_version'] != 'adult-v1' ||
        json['acknowledged'] is! bool ||
        json['include_adult_sources'] is! bool ||
        json['privacy_locked'] is! bool) {
      throw const FormatException('local_access_schema');
    }
    final ack = json['acknowledged']! as bool;
    return AccessState(
      acknowledged: ack,
      includeAdultSources: ack && (json['include_adult_sources']! as bool),
      privacyLocked: json['privacy_locked']! as bool,
    );
  }
}

abstract interface class DeviceAccessStore {
  Future<AccessState> read();
  Future<void> write(AccessState state);
}

bool mayRead(ContentRating rating, AccessState state) {
  if (rating.sourceAccess != SourceAccess.notRequired &&
      rating.sourceAccess != SourceAccess.allowed) {
    return false;
  }
  if (rating.level == RatingLevel.unknown ||
      rating.level == RatingLevel.prohibited) {
    return false;
  }
  if ((rating.minimumAge ?? 0) > 18 &&
      rating.sourceAccess != SourceAccess.allowed) {
    return false;
  }
  // An upstream age/login condition must be completed upstream; this declaration
  // does not certify a source-specific minimum age or account permission.
  if (rating.minimumAge != null &&
      rating.minimumAge! >= 18 &&
      !state.adultVisible) {
    return false;
  }
  return !rating.protected || state.adultVisible;
}

enum SourceMode { normal, adult, mixed, unknown }

final class DiscoverySource {
  const DiscoverySource(
    this.id,
    this.mode, {
    this.enabled = false,
    this.approved = false,
    this.accessible = false,
    this.chinese = true,
    this.reliableNormalPath = false,
  });
  final String id;
  final SourceMode mode;
  final bool enabled, approved, accessible, chinese, reliableNormalPath;
}

bool mayDiscover(DiscoverySource source, AccessState state) {
  if (!source.enabled ||
      !source.approved ||
      !source.accessible ||
      !source.chinese) {
    return false;
  }
  return switch (source.mode) {
    SourceMode.normal => true,
    SourceMode.adult => state.adultDiscovery,
    SourceMode.mixed => state.adultDiscovery || source.reliableNormalPath,
    SourceMode.unknown => false,
  };
}

/// No local permission is an export field. Future backup/sync must use this
/// whitelist, never serialize AccessState or copy the sibling device directory.
const portableAccessFields = <String>{};
void validatePortableAccess(Map<String, Object?> payload) {
  if (payload.keys.any((key) => !portableAccessFields.contains(key))) {
    throw const FormatException('device_access_not_portable');
  }
}
