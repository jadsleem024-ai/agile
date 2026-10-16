import '../supabase_config.dart';
import '../models/workout.dart';
import '../models/assigned_program.dart';
import '../models/trainee_program_data.dart';

class TraineeService {
  static String get _today => DateTime.now().toIso8601String().split('T').first;

  /// Loads the trainee's current program.
  ///
  /// Position is a counter stored on the trainee (`block_position`), bumped once
  /// per "Save & Done". With programs [Day1, Day2] the sequence is Day1, Day2,
  /// Day1, Day2… and `position ~/ 2` is the loop they are on.
  ///
  /// It used to be inferred from history by counting (program, date) pairs,
  /// which silently broke as soon as the same program came round twice in one
  /// day — the second visit collided with the first, so the count stopped
  /// rising and the day reopened already ticked. A stored counter has no such
  /// ambiguity, and `session_seq` on each progress row keeps the two sessions
  /// apart.
  static Future<TraineeProgramData?> loadTraineeProgram(String code,
      {String? overrideProgramId}) async {
    final traineeData = await supabase
        .from('trainees')
        .select('*, programs(*)')
        .eq('code', code)
        .maybeSingle();
    if (traineeData == null) return null;

    final traineeId = traineeData['id'].toString();
    final position = (traineeData['block_position'] as num?)?.toInt() ?? 0;
    final loopTarget = (traineeData['loop_target'] as num?)?.toInt();

    final tpData = await supabase
        .from('trainee_programs')
        .select('*, programs(*)')
        .eq('trainee_id', traineeId)
        .order('order_index', ascending: true);

    // Session counts per program, for the coach-facing "done x times" figures.
    final historyData = await supabase
        .from('progress')
        .select('program_id, date, session_finished')
        .eq('trainee_code', code);

    final programDateCounts = <String, Set<String>>{};
    final programLastDate = <String, String>{};
    for (final h in (historyData as List)) {
      final pid = h['program_id'].toString();
      final date = h['date'] as String;
      programDateCounts.putIfAbsent(pid, () => {}).add(date);
      final current = programLastDate[pid];
      if (current == null || date.compareTo(current) > 0) {
        programLastDate[pid] = date;
      }
    }

    List<AssignedProgram> assignedPrograms = [];
    Map<String, dynamic>? program;

    if ((tpData as List).isNotEmpty) {
      assignedPrograms = tpData.where((tp) => tp['programs'] != null).map<AssignedProgram>((tp) {
        final pid = tp['program_id'].toString();
        return AssignedProgram(
          id: pid,
          name: tp['programs']['name'],
          count: programDateCounts[pid]?.length ?? 0,
          lastDate: programLastDate[pid],
        );
      }).toList();

      final rotation = assignedPrograms.map((p) => p.id).toList();
      final targetId = overrideProgramId ?? rotation[position % rotation.length];

      final found = tpData.firstWhere(
        (tp) => tp['program_id'].toString() == targetId,
        orElse: () => tpData.first,
      );
      program = found['programs'];

      // Keep the stored pointer in step so the coach panel shows the same day.
      if (program != null && traineeData['program_id']?.toString() != program['id'].toString()) {
        try {
          await supabase
              .from('trainees')
              .update({'program_id': program['id']}).eq('id', traineeId);
        } catch (_) {
          // Trainees may not be allowed to write this column; it is cosmetic.
        }
      }
    } else if (traineeData['programs'] != null) {
      program = traineeData['programs'];
      final pid = program!['id'].toString();
      assignedPrograms = [
        AssignedProgram(
          id: pid,
          name: program['name'],
          count: programDateCounts[pid]?.length ?? 0,
          lastDate: programLastDate[pid],
        )
      ];
    }

    if (program == null) return null;

    final programId = program['id'].toString();
    final exercisesData = await supabase
        .from('exercises')
        .select()
        .eq('program_id', programId)
        .order('order_index', ascending: true);

    final workouts = (exercisesData as List).map((ex) => Workout.fromExerciseMap(ex)).toList();

    final dayCount = assignedPrograms.isEmpty ? 1 : assignedPrograms.length;

    return TraineeProgramData(
      traineeId: traineeId,
      programId: programId,
      programName: program['name'],
      workouts: workouts,
      assignedPrograms: assignedPrograms,
      dayIndex: position % dayCount,
      currentLoop: (position ~/ dayCount) + 1,
      loopTarget: loopTarget,
      sessionSeq: position,
    );
  }

  /// Whether the trainee has worked through every loop the coach asked for.
  static Future<BlockCompleteData?> checkBlockComplete(String code) async {
    final trainee = await supabase
        .from('trainees')
        .select('id, loop_target, block_position')
        .eq('code', code)
        .maybeSingle();
    if (trainee == null) return null;

    final loopTarget = (trainee['loop_target'] as num?)?.toInt();
    if (loopTarget == null || loopTarget <= 0) return null; // repeats forever

    final position = (trainee['block_position'] as num?)?.toInt() ?? 0;
    final traineeId = trainee['id'].toString();

    final tpData = await supabase
        .from('trainee_programs')
        .select('program_id')
        .eq('trainee_id', traineeId);
    final dayCount = (tpData as List).length;
    if (dayCount == 0) return null;

    if (position < dayCount * loopTarget) return null;

    return BlockCompleteData(
      traineeId: traineeId,
      loopsDone: position ~/ dayCount,
      loopTarget: loopTarget,
      dayCount: dayCount,
    );
  }

  /// Progress for the session currently in play. Scoped by [sessionSeq] so a
  /// program that comes round again in the same block starts clean instead of
  /// showing the earlier attempt already ticked.
  static Future<ProgressLoadResult> loadProgress(
      String code, String programId, int sessionSeq) async {
    final currentData = await supabase
        .from('progress')
        .select()
        .eq('trainee_code', code)
        .eq('program_id', programId)
        .eq('session_seq', sessionSeq);

    // Weights carry across sessions — the point is to show what they lifted
    // last time, so this deliberately ignores session_seq.
    final allWeightsData = await supabase
        .from('progress')
        .select('exercise_id, set_weights, date, session_seq')
        .eq('trainee_code', code)
        .eq('program_id', programId)
        .not('set_weights', 'is', null)
        .order('date', ascending: false)
        .order('session_seq', ascending: false);

    final lastWeights = <String, List<dynamic>>{};
    for (final row in (allWeightsData as List)) {
      final exId = row['exercise_id'].toString();
      if (!lastWeights.containsKey(exId) && row['set_weights'] != null) {
        lastWeights[exId] = List<dynamic>.from(row['set_weights']);
      }
    }

    final setWeights = <String, List<dynamic>>{};
    final completedSets = <String, List<int>>{};
    final notes = <String, String>{};
    var sessionFinished = false;
    for (final row in (currentData as List)) {
      final exId = row['exercise_id'].toString();
      if (row['set_weights'] != null) {
        setWeights[exId] = List<dynamic>.from(row['set_weights']);
      }
      completedSets[exId] =
          List<int>.from((row['completed_sets'] as List? ?? []).map((e) => (e as num).toInt()));
      notes[exId] = row['notes'] ?? '';
      if (row['session_finished'] == true) sessionFinished = true;
    }

    return ProgressLoadResult(
      setWeights: setWeights,
      lastWeights: lastWeights,
      completedSets: completedSets,
      notes: notes,
      sessionFinished: sessionFinished,
    );
  }

  static Future<void> saveProgress({
    required String code,
    required String programId,
    required String exerciseId,
    required List<int> completedSets,
    required String notes,
    required List<dynamic> weights,
    required int sessionSeq,
  }) async {
    final payload = {
      'trainee_code': code,
      'program_id': programId,
      'exercise_id': exerciseId,
      'date': _today,
      'session_seq': sessionSeq,
      'completed_sets': completedSets,
      'notes': notes,
      'set_weights': weights.isNotEmpty ? weights : null,
    };
    await supabase.from('progress').upsert(payload,
        onConflict: 'trainee_code,program_id,exercise_id,date,session_seq');
  }

  /// Closes out the session: writes a row for every exercise, stamps it
  /// finished, then moves the trainee one step along the block.
  static Future<void> finalizeWorkout({
    required String code,
    required String programId,
    required List<Workout> workouts,
    required Map<String, List<dynamic>> snapshotWeights,
    required int sessionSeq,
  }) async {
    final now = DateTime.now().toIso8601String();
    await Future.wait(workouts.map((w) => supabase.from('progress').upsert({
          'trainee_code': code,
          'program_id': programId,
          'exercise_id': w.id,
          'date': _today,
          'session_seq': sessionSeq,
          'completed_sets': w.completedSets,
          'notes': w.notes,
          'set_weights': snapshotWeights[w.id],
          'session_finished': true,
          'updated_at': now,
        }, onConflict: 'trainee_code,program_id,exercise_id,date,session_seq')));

    // Done through an RPC because a trainee has no write access to the column.
    await supabase.rpc('advance_block_position', params: {'p_code': code});
  }
}
