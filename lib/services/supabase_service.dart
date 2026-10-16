import 'dart:math';
import 'package:coach_panel/models/library_exercise.dart';
import 'package:uuid/uuid.dart';
import '../supabase_config.dart';
import '../models/trainee.dart';
import '../models/program.dart';
import '../models/exercise.dart';
import '../models/progress.dart';

class SupabaseService {
  static const _uuid = Uuid();

  /// The coach who owns anything created from here.
  ///
  /// Reads never need this — row level security already limits every select to
  /// the signed-in coach's own rows. It is stamped on inserts so ownership is
  /// explicit in the app rather than relying solely on the column default.
  static String? get _ownerId => supabase.auth.currentUser?.id;

  static String generateCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rnd = Random();
    return List.generate(6, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  // ---------------- TRAINEES ----------------

  static Future<List<Trainee>> loadTrainees() async {
    final data = await supabase
        .from('trainees')
        .select('*, programs(name)')
        .order('created_at', ascending: false);
    return (data as List).map((e) => Trainee.fromMap(e)).toList();
  }

  /// trainee_id -> ordered list of program_ids (rotation)
  static Future<Map<String, List<String>>> loadTraineePrograms() async {
    final data = await supabase
        .from('trainee_programs')
        .select()
        .order('order_index', ascending: true);
    final map = <String, List<String>>{};
    for (final row in (data as List)) {
      final traineeId = row['trainee_id'].toString();
      final programId = row['program_id'].toString();
      map.putIfAbsent(traineeId, () => []).add(programId);
    }
    return map;
  }

  static Future<Trainee> addTrainee(String name, String? code) async {
    final finalCode =
        (code == null || code.trim().isEmpty) ? generateCode() : code.trim();
    final data = await supabase
        .from('trainees')
        .insert({'name': name, 'code': finalCode, 'coach_id': _ownerId}).select();
    return Trainee.fromMap((data as List).first);
  }

  static Future<void> deleteTrainee(String id) async {
    await supabase.from('trainees').delete().eq('id', id);
  }

  /// Sets how many times the trainee's program rotation repeats before the
  /// block locks. Null clears the limit, so it repeats indefinitely.
  static Future<void> setLoopTarget(String traineeId, int? loops) async {
    await supabase
        .from('trainees')
        .update({'loop_target': loops}).eq('id', traineeId);
  }

  /// Wipes a trainee's logged history and puts them back at the start of their
  /// block. Used when a block is over and the old data is no longer worth
  /// keeping — it is not recoverable afterwards.
  static Future<int> clearTraineeProgress(String traineeId, String code) async {
    final deleted = await supabase
        .from('progress')
        .delete()
        .eq('trainee_code', code)
        .select('id');
    await supabase
        .from('trainees')
        .update({'block_position': 0}).eq('id', traineeId);
    return (deleted as List).length;
  }


  static Future<void> saveMultiPrograms(
      String traineeId, List<String> programIds) async {
    await supabase
        .from('trainee_programs')
        .delete()
        .eq('trainee_id', traineeId);
    if (programIds.isNotEmpty) {
      final rows = programIds
          .asMap()
          .entries
          .map((e) => {
                'trainee_id': traineeId,
                'program_id': e.value,
                'order_index': e.key,
              })
          .toList();
      await supabase.from('trainee_programs').insert(rows);
      await supabase.from('trainees').update({
        'program_id': programIds.first,
        'program_start_date': DateTime.now().toIso8601String().split('T').first,
      }).eq('id', traineeId);
    } else {
      await supabase.from('trainees').update(
          {'program_id': null, 'program_start_date': null}).eq('id', traineeId);
    }
  }

  // ---------------- PROGRAMS ----------------

  static Future<List<Program>> loadPrograms() async {
    final data = await supabase
        .from('programs')
        .select()
        .order('created_at', ascending: false);
    return (data as List).map((e) => Program.fromMap(e)).toList();
  }

  static Future<Program> addProgram(String name, String description) async {
    final data = await supabase
        .from('programs')
        .insert({'name': name, 'description': description, 'coach_id': _ownerId}).select();
    return Program.fromMap((data as List).first);
  }

  static Future<void> deleteProgram(String id) async {
    await supabase.from('programs').delete().eq('id', id);
  }

  static Future<void> renameProgram(String id, String newName) async {
    await supabase.from('programs').update({'name': newName}).eq('id', id);
  }

  static Future<Program> duplicateProgram(Program program) async {
    final newProgData = await supabase.from('programs').insert({
      'name': '${program.name} (Copy)',
      'description': program.description,
      'coach_id': _ownerId,
    }).select();
    final newProgram = Program.fromMap((newProgData as List).first);

    final originalExercises = await supabase
        .from('exercises')
        .select()
        .eq('program_id', program.id)
        .order('order_index', ascending: true);

    if ((originalExercises as List).isNotEmpty) {
      final cloned = originalExercises.map((ex) {
        final copy = Map<String, dynamic>.from(ex);
        copy.remove('id');
        copy.remove('created_at');
        copy['program_id'] = newProgram.id;
        return copy;
      }).toList();
      await supabase.from('exercises').insert(cloned);
    }
    return newProgram;
  }

  // ---------------- EXERCISES ----------------

  static Future<List<Exercise>> loadExercises(String programId) async {
    final data = await supabase
        .from('exercises')
        .select()
        .eq('program_id', programId)
        .order('order_index', ascending: true);
    return (data as List).map((e) => Exercise.fromMap(e)).toList();
  }

  static Future<void> addSingleExercise(Exercise exercise) async {
    await supabase.from('exercises').insert(exercise.toInsertMap());
  }

  /// Inserts a list of exercises that form a new group (superset/triset/circuit)
  static Future<void> addExerciseGroup(List<Exercise> groupExercises,
      String groupType, String? groupName) async {
    final groupId = _uuid.v4();
    final rows = groupExercises
        .map((ex) => {
              ...ex.toInsertMap(),
              'group_id': groupId,
              'group_type': groupType,
              'group_name': groupName,
            })
        .toList();
    await supabase.from('exercises').insert(rows);
  }

  static Future<void> updateExercise(Exercise exercise) async {
  final updateData = {
    'name': exercise.name,
    'sets':
        exercise.setRows.isNotEmpty ? exercise.setRows.length : exercise.sets,
    'reps': exercise.reps,
    'weight': exercise.weight,
    'rest_time': exercise.restTime,
    'video_url': exercise.videoUrl,
    'each_side': exercise.eachSide,
    'set_rows': exercise.setRows.map((r) => r.toMap()).toList(),
    'notes': exercise.notes,   // <-- add this
  };
  await supabase.from('exercises').update(updateData).eq('id', exercise.id);
}

  /// [videoUrl]
  static Future<void> deleteExercise(String id, String? videoUrl) async {
    await supabase.from('exercises').delete().eq('id', id);
  }

  static Future<void> reorderExercises(List<Exercise> orderedExercises) async {
  if (orderedExercises.isEmpty) return;

  final futures = orderedExercises.asMap().entries.map((entry) async {
    final result = await supabase
        .from('exercises')
        .update({'order_index': entry.key})
        .eq('id', entry.value.id)
        .select();
    if (result.isEmpty) {
      throw Exception(
          'No rows updated for exercise ${entry.value.id} — likely blocked by RLS policy');
    }
  });

  await Future.wait(futures);
}

  static Future<void> saveGroupName(String groupId, String? newName) async {
    await supabase
        .from('exercises')
        .update({'group_name': newName}).eq('group_id', groupId);
  }

  /// Removes an exercise from its group (fixes up remaining members' group_type)
  static Future<void> ejectFromGroup(
      Exercise exercise, List<Exercise> remainingGroupMembers) async {
    await supabase.from('exercises').update({
      'group_id': null,
      'group_type': null,
      'group_name': null,
    }).eq('id', exercise.id);

    if (remainingGroupMembers.length == 1) {
      await supabase.from('exercises').update({
        'group_id': null,
        'group_type': null,
        'group_name': null,
      }).eq('id', remainingGroupMembers.first.id);
    } else if (remainingGroupMembers.length >= 2) {
      final newType = groupTypeForCount(remainingGroupMembers.length);
      await supabase.from('exercises').update({'group_type': newType}).eq(
          'group_id', remainingGroupMembers.first.groupId!);
    }
  }

  /// Moves an exercise into an existing group
  static Future<void> moveIntoGroup(Exercise exercise, String targetGroupId,
      List<Exercise> targetGroupMembers) async {
    final newCount = targetGroupMembers.length + 1;
    final newType = groupTypeForCount(newCount);

    await supabase.from('exercises').update({
      'group_id': targetGroupId,
      'group_type': newType,
      'group_name': targetGroupMembers.isNotEmpty
          ? targetGroupMembers.first.groupName
          : null,
    }).eq('id', exercise.id);

    await supabase
        .from('exercises')
        .update({'group_type': newType}).eq('group_id', targetGroupId);
  }
  // ---------------- EXERCISE LIBRARY ----------------

  static Future<List<LibraryExercise>> loadLibraryExercises() async {
    final data = await supabase
        .from('exercise_library')
        .select()
        .order('name', ascending: true);
    return (data as List).map((e) => LibraryExercise.fromMap(e)).toList();
  }

  /// Anything the admin adds becomes part of the shared default library that
  /// every coach sees; a coach's own additions stay private to them.
  static Future<void> addLibraryExercise(LibraryExercise exercise,
      {bool asGlobal = false}) async {
    await supabase.from('exercise_library').insert({
      ...exercise.toInsertMap(),
      'coach_id': _ownerId,
      'is_global': asGlobal,
    });
  }

  static Future<void> updateLibraryExercise(LibraryExercise exercise) async {
    await supabase
        .from('exercise_library')
        .update(exercise.toInsertMap())
        .eq('id', exercise.id);
  }

  static Future<void> deleteLibraryExercise(String id) async {
    await supabase.from('exercise_library').delete().eq('id', id);
  }
  // ---------------- PROGRESS ----------------

  static Future<List<ProgressEntry>> loadTraineeProgress(
      String traineeCode, String date) async {
    final data = await supabase
        .from('progress')
        .select('*, exercises(name, sets, reps, weight, rest_time, video_url, '
            'set_rows, each_side, order_index)')
        .eq('trainee_code', traineeCode)
        .eq('date', date);

    final entries = (data as List).map((e) => ProgressEntry.fromMap(e)).toList();

    // A trainee can now do the same program twice in one day (session_seq keeps
    // the attempts apart), so order by session first — otherwise the two would
    // interleave and read as one duplicated workout.
    entries.sort((a, b) {
      final bySession = a.sessionSeq.compareTo(b.sessionSeq);
      if (bySession != 0) return bySession;
      // PostgREST cannot order parent rows by a column on a to-one embed, so
      // restore the coach's exercise order here.
      return (a.exercise?.orderIndex ?? 0).compareTo(b.exercise?.orderIndex ?? 0);
    });
    return entries;
  }

  static Future<List<ProgramHistory>> loadWorkoutHistory(
      String traineeCode) async {
    final data = await supabase.from('progress').select('''
          date, completed_sets, program_id, session_seq,
          exercises (sets, set_rows, program_id),
          programs!inner (id, name)
        ''').eq('trainee_code', traineeCode).order('date', ascending: false);

    // Keyed per session, not per date. Grouping by date alone folded several
    // workouts done on the same day into one entry — it took the first
    // program's name and summed everyone's exercises into it, so a day with
    // four programs reported as a single inflated session.
    final sessionsByKey = <String, WorkoutSession>{};
    for (final record in (data as List)) {
      final date = record['date'] as String;
      final programId = record['program_id'].toString();
      final seq = (record['session_seq'] as num?)?.toInt() ?? 0;
      final programName =
          (record['programs'] as Map?)?['name'] ?? 'Unknown Program';
      final exercises = record['exercises'] as Map?;
      final completedSets = (record['completed_sets'] as List?) ?? [];
      final setRows = exercises?['set_rows'] as List?;
      final setsCount = exercises?['sets'] ?? 0;

      final session = sessionsByKey.putIfAbsent(
        '$date|$programId|$seq',
        () => WorkoutSession(
            date: date, programId: programId, programName: programName),
      );
      session.exercises += 1;
      session.totalSets += (setRows?.length ?? setsCount) as int;
      session.completedSets += completedSets.length;
    }

    final programMap = <String, ProgramHistory>{};
    for (final session in sessionsByKey.values) {
      final history = programMap.putIfAbsent(
        session.programName,
        () => ProgramHistory(
            programName: session.programName, programId: session.programId),
      );
      history.count += 1;
      history.sessions.add(session);
    }

    for (final history in programMap.values) {
      history.sessions.sort((a, b) => b.date.compareTo(a.date));
    }

    final list = programMap.values.toList()
      ..sort((a, b) => b.lastSession.compareTo(a.lastSession));
    return list;
  }
}
