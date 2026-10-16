import 'workout.dart';
import 'assigned_program.dart';

class TraineeProgramData {
  final String traineeId;
  final String programId;
  final String programName;
  final List<Workout> workouts;
  final List<AssignedProgram> assignedPrograms;

  /// Where the trainee is in the rotation, 0-based (0 = first day of a loop).
  final int dayIndex;

  /// Which pass through the rotation they are on, 1-based.
  final int currentLoop;

  /// How many passes the coach asked for. Null means repeat indefinitely.
  final int? loopTarget;

  /// True once every loop has been finished — the workout screen locks.
  final bool blockComplete;

  /// The trainee's position in the block, and the key progress rows are filed
  /// under. Keeps a repeat of the same program later in the block separate from
  /// the earlier attempt.
  final int sessionSeq;

  TraineeProgramData({
    required this.traineeId,
    required this.programId,
    required this.programName,
    required this.workouts,
    required this.assignedPrograms,
    this.dayIndex = 0,
    this.currentLoop = 1,
    this.loopTarget,
    this.blockComplete = false,
    this.sessionSeq = 0,
  });

  int get dayCount => assignedPrograms.length;
}

/// Returned instead of a program when the trainee has finished every loop.
class BlockCompleteData {
  final String traineeId;
  final int loopsDone;
  final int loopTarget;
  final int dayCount;

  BlockCompleteData({
    required this.traineeId,
    required this.loopsDone,
    required this.loopTarget,
    required this.dayCount,
  });
}

class ProgressLoadResult {
  final Map<String, List<dynamic>> setWeights; // exerciseId -> list of weights (by set index)
  final Map<String, List<dynamic>> lastWeights; // exerciseId -> most recent weights from any date
  final Map<String, List<int>> completedSets; // exerciseId -> completed set indices
  final Map<String, String> notes; // exerciseId -> notes

  /// True once the trainee has tapped "Save & Done" for today's session.
  final bool sessionFinished;

  ProgressLoadResult({
    required this.setWeights,
    required this.lastWeights,
    required this.completedSets,
    required this.notes,
    this.sessionFinished = false,
  });
}
