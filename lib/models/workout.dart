import '../utils/format.dart';
import 'exercise.dart';

class Workout {
  final String id;
  final String name;
  final int sets;
  final List<SetRow> setRows;
  final int restTime;
  List<int> completedSets;
  String notes;
  final String? coachNotes;
  final String? groupType;
  final String? groupId;
  final String? groupName;
  final String? videoUrl;
  final bool eachSide;

  Workout({
    required this.id,
    required this.name,
    required this.sets,
    required this.setRows,
    required this.restTime,
    List<int>? completedSets,
    this.notes = '',
    this.coachNotes,   
    this.groupType,
    this.groupId,
    this.groupName,
    this.videoUrl,
    this.eachSide = false,
  }) : completedSets = completedSets ?? [];

  factory Workout.fromExerciseMap(Map<String, dynamic> ex) {
    final rawRows = ex['set_rows'] as List<dynamic>?;
    final rowsFromDb = rawRows != null && rawRows.isNotEmpty
        ? rawRows
            .map((r) => SetRow.fromMap(Map<String, dynamic>.from(r)))
            .toList()
        : null;
    final sets = (ex['sets'] ?? 3) as int;
    final setRows = rowsFromDb ??
        List.generate(
          sets,
          (_) => SetRow(
              weight: ((ex['weight'] ?? 0) as num).toDouble(),
              reps: (ex['reps'] ?? 10) as int),
        );

    return Workout(
      id: ex['id'].toString(),
      name: ex['name'] ?? '',
      sets: setRows.length,
      setRows: setRows,
      restTime: (ex['rest_time'] ?? 60) as int,
      coachNotes: ex['notes'],
      groupType: ex['group_type'],
      groupId: ex['group_id'],
      groupName: ex['group_name'],
      videoUrl: ex['video_url'],
      eachSide: ex['each_side'] ?? false,
    );
  }

  String setsSummaryLine() {
    return setRows.map((r) {
      final line = setLine(r.weight,
          reps: r.reps, duration: r.duration, isTime: r.type == 'time');
      return r.type == 'time' ? '$line ⏱' : line;
    }).join(' | ');
  }
}

/// Either a single workout or a group of workouts sharing a group_id,
/// used to build the paginated exercise flow.
class WorkoutPage {
  final Workout? single;
  final List<Workout>? group;
  final String? groupType;
  final String? groupId;

  WorkoutPage.single(this.single)
      : group = null,
        groupType = null,
        groupId = null;

  WorkoutPage.group(this.group, this.groupType, this.groupId) : single = null;

  bool get isGroup => group != null;

  bool get isComplete => isGroup
      ? group!.every((w) => w.completedSets.length == w.sets)
      : single!.completedSets.length == single!.sets;
}

List<WorkoutPage> buildWorkoutPages(List<Workout> workouts) {
  final pages = <WorkoutPage>[];
  final processed = <String>{};
  for (final w in workouts) {
    if (w.groupId != null && !processed.contains(w.groupId)) {
      final members = workouts.where((x) => x.groupId == w.groupId).toList();
      pages.add(WorkoutPage.group(members, w.groupType, w.groupId));
      processed.add(w.groupId!);
    } else if (w.groupId == null) {
      pages.add(WorkoutPage.single(w));
    }
  }
  return pages;
}
