import '../utils/format.dart';
class SetRow {
  double weight;
  int reps;
  int duration;
  String type; // 'reps' | 'time'

  SetRow({
    this.weight = 0,
    this.reps = 10,
    this.duration = 0,
    this.type = 'reps',
  });

  factory SetRow.fromMap(Map<String, dynamic> map) {
    return SetRow(
      weight: (map['weight'] ?? 0).toDouble(),
      reps: (map['reps'] ?? 10).toInt(),
      duration: (map['duration'] ?? 0).toInt(),
      type: map['type'] ?? 'reps',
    );
  }

  Map<String, dynamic> toMap() => {
        'weight': weight,
        'reps': reps,
        'duration': duration,
        'type': type,
      };

  SetRow copy() =>
      SetRow(weight: weight, reps: reps, duration: duration, type: type);
}

class Exercise {
  final String id;
  final String programId;
  String name;
  int sets;
  int reps;
  double weight;
  int restTime;
  String? videoUrl;
  bool eachSide;
  List<SetRow> setRows;
  int orderIndex;
  String? notes;

  // Grouping (superset / triset / circuit)
  String? groupId;
  String? groupType; // 'superset' | 'triset' | 'circuit'
  String? groupName;

  Exercise({
    required this.id,
    required this.programId,
    required this.name,
    this.sets = 3,
    this.reps = 10,
    this.weight = 0,
    this.restTime = 60,
    this.videoUrl,
    this.eachSide = false,
    List<SetRow>? setRows,
    this.orderIndex = 0,
    this.notes,
    this.groupId,
    this.groupType,
    this.groupName,
  }) : setRows = setRows ?? [];

  factory Exercise.fromMap(Map<String, dynamic> map) {
    final rawRows = map['set_rows'] as List<dynamic>?;
    return Exercise(
      id: map['id'].toString(),
      programId: map['program_id'].toString(),
      name: map['name'] ?? '',
      sets: (map['sets'] ?? 3).toInt(),
      reps: (map['reps'] ?? 10).toInt(),
      weight: (map['weight'] ?? 0).toDouble(),
      restTime: (map['rest_time'] ?? 60).toInt(),
      videoUrl: map['video_url'],
      eachSide: map['each_side'] ?? false,
      setRows: rawRows != null
          ? rawRows
              .map((r) => SetRow.fromMap(Map<String, dynamic>.from(r)))
              .toList()
          : [],
      orderIndex: (map['order_index'] ?? 0).toInt(),
      notes: map['notes'],
      groupId: map['group_id'],
      groupType: map['group_type'],
      groupName: map['group_name'],
    );
  }

  Map<String, dynamic> toInsertMap() => {
        'program_id': programId,
        'name': name,
        'sets': setRows.isNotEmpty ? setRows.length : sets,
        'reps': reps,
        'weight': weight,
        'rest_time': restTime,
        'order_index': orderIndex,
        'video_url': videoUrl,
        'each_side': eachSide,
        'set_rows': setRows.map((r) => r.toMap()).toList(),
        'notes': notes,
        if (groupId != null) 'group_id': groupId,
        if (groupType != null) 'group_type': groupType,
        if (groupName != null) 'group_name': groupName,
      };

  /// Human readable summary line, e.g. "20kg × 10 | 20kg × 8 • 60s rest"
  String setsSummary() {
    if (setRows.isNotEmpty) {
      final parts = setRows.map((r) {
        final line = setLine(r.weight,
            reps: r.reps, duration: r.duration, isTime: r.type == 'time');
        return r.type == 'time' ? '$line ⏱' : line;
      }).join(' | ');
      return '$parts • ${restTime}s rest';
    }
    return '$sets × $reps @ ${weightChip(weight)} • ${restTime}s rest';
  }
}

/// A UI-level grouping of exercises that share the same group_id
class ExerciseGroup {
  final String groupId;
  final String groupType;
  final String? groupName;
  final List<Exercise> exercises;

  ExerciseGroup({
    required this.groupId,
    required this.groupType,
    required this.exercises,
    this.groupName,
  });

  String get label {
    switch (groupType) {
      case 'superset':
        return 'SUPERSET';
      case 'triset':
        return 'TRISET';
      case 'circuit':
        return 'CIRCUIT';
      default:
        return '';
    }
  }
}

/// Either a single exercise or a group, used to render the ordered list
class ExerciseListItem {
  final Exercise? single;
  final ExerciseGroup? group;

  ExerciseListItem.single(this.single) : group = null;
  ExerciseListItem.group(this.group) : single = null;

  bool get isGroup => group != null;
}

List<ExerciseListItem> groupExercisesForDisplay(List<Exercise> exercises) {
  final items = <ExerciseListItem>[];
  final processed = <String>{};
  for (final ex in exercises) {
    if (ex.groupId != null && !processed.contains(ex.groupId)) {
      final members = exercises.where((e) => e.groupId == ex.groupId).toList();
      items.add(ExerciseListItem.group(ExerciseGroup(
        groupId: ex.groupId!,
        groupType: ex.groupType ?? 'superset',
        groupName: ex.groupName,
        exercises: members,
      )));
      processed.add(ex.groupId!);
    } else if (ex.groupId == null) {
      items.add(ExerciseListItem.single(ex));
    }
  }
  return items;
}

class GroupRequirement {
  final int min;
  final int max;
  final String label;
  GroupRequirement(this.min, this.max, this.label);
}

GroupRequirement getGroupRequirement(String groupType) {
  switch (groupType) {
    case 'superset':
      return GroupRequirement(2, 2, '2 exercises');
    case 'triset':
      return GroupRequirement(3, 3, '3 exercises');
    case 'circuit':
      return GroupRequirement(4, 10, '4-10 exercises');
    default:
      return GroupRequirement(1, 1, '');
  }
}

String groupTypeForCount(int count) {
  if (count == 2) return 'superset';
  if (count == 3) return 'triset';
  return 'circuit';
}
