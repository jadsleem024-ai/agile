import 'exercise.dart';

class ProgressEntry {
  final String id;
  final String traineeCode;
  final String date;
  final String? programId;
  final List<int> completedSets;

  /// Weight recorded per set, indexed by set number.
  ///
  /// The trainee app writes this as a JSON array, but older rows may hold an
  /// object keyed by index — [weightForSet] reads both.
  final List<dynamic> setWeights;
  final String? notes;
  final bool sessionFinished;

  /// Which attempt within the block this row belongs to. Two rows can share a
  /// date and program and differ only here.
  final int sessionSeq;
  final String? updatedAt;
  final Exercise? exercise; // joined exercise data

  ProgressEntry({
    required this.id,
    required this.traineeCode,
    required this.date,
    this.programId,
    required this.completedSets,
    required this.setWeights,
    this.notes,
    this.updatedAt,
    this.exercise,
    this.sessionFinished = false,
    this.sessionSeq = 0,
  });

  factory ProgressEntry.fromMap(Map<String, dynamic> map) {
    final exMap = map['exercises'] as Map<String, dynamic>?;
    return ProgressEntry(
      id: map['id'].toString(),
      traineeCode: map['trainee_code'] ?? '',
      date: map['date'] ?? '',
      programId: map['program_id']?.toString(),
      completedSets: (map['completed_sets'] as List<dynamic>? ?? [])
          .map((e) => (e as num).toInt())
          .toList(),
      setWeights: _parseSetWeights(map['set_weights']),
      notes: map['notes'],
      updatedAt: map['updated_at'],
      sessionFinished: map['session_finished'] == true,
      sessionSeq: (map['session_seq'] as num?)?.toInt() ?? 0,
      exercise: exMap != null ? Exercise.fromMap({...exMap, 'id': '', 'program_id': ''}) : null,
    );
  }

  /// set_weights is written as an array by the trainee app. Reading it as a Map
  /// threw on every row that had weights, which is what left the coach's
  /// Progress tab permanently empty. Both shapes are normalised to a list here.
  static List<dynamic> _parseSetWeights(dynamic raw) {
    if (raw == null) return const [];
    if (raw is List) return List<dynamic>.from(raw);
    if (raw is Map) {
      // Keys are set indices; place each value at its own position.
      final entries = <int, dynamic>{};
      raw.forEach((key, value) {
        final idx = int.tryParse(key.toString());
        if (idx != null && idx >= 0) entries[idx] = value;
      });
      if (entries.isEmpty) return const [];
      final size = entries.keys.reduce((a, b) => a > b ? a : b) + 1;
      return List<dynamic>.generate(size, (i) => entries[i]);
    }
    return const [];
  }

  /// Weight logged for [setIdx], or null when the trainee left it blank.
  dynamic weightForSet(int setIdx) {
    if (setIdx < 0 || setIdx >= setWeights.length) return null;
    final value = setWeights[setIdx];
    if (value == null || value == '') return null;
    return value;
  }

  int get totalSets =>
      exercise?.setRows.isNotEmpty == true ? exercise!.setRows.length : (exercise?.sets ?? 0);

  double get completionRate => totalSets > 0 ? (completedSets.length / totalSets) * 100 : 0;

  bool get hasNotes => notes != null && notes!.trim().isNotEmpty;
}

class WorkoutSession {
  final String date;
  final String programId;
  final String programName;
  int totalSets;
  int completedSets;
  int exercises;

  WorkoutSession({
    required this.date,
    required this.programId,
    required this.programName,
    this.totalSets = 0,
    this.completedSets = 0,
    this.exercises = 0,
  });

  int get completionRate => totalSets > 0 ? ((completedSets / totalSets) * 100).round() : 0;
}

class ProgramHistory {
  final String programName;
  final String programId;
  int count;
  final List<WorkoutSession> sessions;

  ProgramHistory({
    required this.programName,
    required this.programId,
    this.count = 0,
    List<WorkoutSession>? sessions,
  }) : sessions = sessions ?? [];

  String get lastSession => sessions.isNotEmpty ? sessions.first.date : '';
}
