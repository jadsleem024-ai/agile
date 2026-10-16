class Trainee {
  final String id;
  final String name;
  final String code;
  final String? programId;
  final String? programName;
  final String? programStartDate;

  /// How many times the assigned rotation repeats before the block is finished.
  /// Null means it repeats indefinitely.
  final int? loopTarget;

  /// Sessions finished in the current block — drives the day and loop shown.
  final int blockPosition;

  Trainee({
    required this.id,
    required this.name,
    required this.code,
    this.programId,
    this.programName,
    this.programStartDate,
    this.loopTarget,
    this.blockPosition = 0,
  });

  factory Trainee.fromMap(Map<String, dynamic> map) {
    // programs is the joined table (nullable) -> { name: ... }
    final programs = map['programs'] as Map<String, dynamic>?;
    return Trainee(
      id: map['id'].toString(),
      name: map['name'] ?? '',
      code: map['code'] ?? '',
      programId: map['program_id']?.toString(),
      programName: programs?['name'],
      programStartDate: map['program_start_date'],
      loopTarget: (map['loop_target'] as num?)?.toInt(),
      blockPosition: (map['block_position'] as num?)?.toInt() ?? 0,
    );
  }

  Trainee copyWith({int? loopTarget, bool clearLoopTarget = false, int? blockPosition}) {
    return Trainee(
      id: id,
      name: name,
      code: code,
      programId: programId,
      programName: programName,
      programStartDate: programStartDate,
      loopTarget: clearLoopTarget ? null : (loopTarget ?? this.loopTarget),
      blockPosition: blockPosition ?? this.blockPosition,
    );
  }
}
