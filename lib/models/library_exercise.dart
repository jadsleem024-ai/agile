import '../utils/format.dart';
import 'exercise.dart';

class LibraryExercise {
  final String id;
  String name;
  List<SetRow> setRows;
  int restTime;
  String? videoUrl;
  bool eachSide;
  String? notes;

  /// Admin-authored entry from the shared default library. Visible to every
  /// coach, editable only by the admin.
  final bool isGlobal;

  LibraryExercise({
    required this.id,
    required this.name,
    List<SetRow>? setRows,
    this.restTime = 60,
    this.videoUrl,
    this.eachSide = false,
    this.notes,
    this.isGlobal = false,
  }) : setRows = setRows ?? [];

  factory LibraryExercise.fromMap(Map<String, dynamic> map) {
    final rawRows = map['set_rows'] as List<dynamic>?;
    return LibraryExercise(
      id: map['id'].toString(),
      name: map['name'] ?? '',
      setRows: rawRows != null
          ? rawRows.map((r) => SetRow.fromMap(Map<String, dynamic>.from(r))).toList()
          : [],
      restTime: (map['rest_time'] ?? 60).toInt(),
      videoUrl: map['video_url'],
      eachSide: map['each_side'] ?? false,
      notes: map['notes'],
      isGlobal: map['is_global'] == true,
    );
  }

  Map<String, dynamic> toInsertMap() => {
        'name': name,
        'set_rows': setRows.map((r) => r.toMap()).toList(),
        'rest_time': restTime,
        'video_url': videoUrl,
        'each_side': eachSide,
        'notes': notes,
      };

  String setsSummary() {
    if (setRows.isEmpty) return 'No sets configured';
    final parts = setRows.map((r) {
      return setLine(r.weight,
          reps: r.reps, duration: r.duration, isTime: r.type == 'time');
    }).join(' | ');
    return '$parts • ${restTime}s rest';
  }
}