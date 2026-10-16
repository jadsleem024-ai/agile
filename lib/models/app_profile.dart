enum AppRole { pending, admin, coach, trainee }

/// What the current app session is allowed to do.
///
/// Deliberately **not** persisted. The stored profile role is only a record of
/// what someone once redeemed; access itself is granted by entering a valid
/// code each time the app opens. That is what makes deleting a code actually
/// revoke access — otherwise a coach removed from the system would keep working
/// indefinitely on the strength of a role claimed months ago.
class SessionAccess {
  final AppRole role;

  /// True when a coach or the admin opened a trainee's programme to look at it.
  /// Nothing is written back in this mode.
  final bool preview;

  final String? traineeCode;
  final String? traineeName;

  const SessionAccess({
    required this.role,
    this.preview = false,
    this.traineeCode,
    this.traineeName,
  });

  factory SessionAccess.fromRpc(Map<String, dynamic> map) {
    return SessionAccess(
      role: roleFromString(map['role']?.toString()),
      preview: map['preview'] == true,
      traineeCode: map['trainee_code']?.toString(),
      traineeName: map['trainee_name']?.toString(),
    );
  }
}

AppRole roleFromString(String? value) {
  switch (value) {
    case 'admin':
      return AppRole.admin;
    case 'coach':
      return AppRole.coach;
    case 'trainee':
      return AppRole.trainee;
    default:
      return AppRole.pending;
  }
}

/// The signed-in account, plus the trainee record it is linked to when the
/// account is a trainee. Resolved once after sign-in and passed down.
class AppProfile {
  final String id;
  final String email;
  final String? fullName;
  final AppRole role;
  final String? traineeId;

  /// Only populated for [AppRole.trainee] — the workout screen keys off these.
  final String? traineeCode;
  final String? traineeName;

  const AppProfile({
    required this.id,
    required this.email,
    required this.role,
    this.fullName,
    this.traineeId,
    this.traineeCode,
    this.traineeName,
  });

  bool get isAdmin => role == AppRole.admin;

  /// Admins manage their own roster in addition to issuing codes, so they get
  /// the coach panel too.
  bool get canCoach => role == AppRole.admin || role == AppRole.coach;

  AppProfile copyWith({
    AppRole? role,
    String? traineeId,
    String? traineeCode,
    String? traineeName,
  }) {
    return AppProfile(
      id: id,
      email: email,
      fullName: fullName,
      role: role ?? this.role,
      traineeId: traineeId ?? this.traineeId,
      traineeCode: traineeCode ?? this.traineeCode,
      traineeName: traineeName ?? this.traineeName,
    );
  }

  factory AppProfile.fromMap(Map<String, dynamic> map, {Map<String, dynamic>? trainee}) {
    return AppProfile(
      id: map['id'].toString(),
      email: map['email'] ?? '',
      fullName: map['full_name'],
      role: roleFromString(map['role']),
      traineeId: map['trainee_id']?.toString(),
      traineeCode: trainee?['code'],
      traineeName: trainee?['name'],
    );
  }
}
