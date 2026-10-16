import 'package:flutter/material.dart';
import '../models/exercise.dart';
import '../models/library_exercise.dart';
import '../services/supabase_service.dart';
import '../widgets/exercise_form_sheet.dart';
import 'coach_panel_screen.dart';

class ExerciseLibraryScreen extends StatefulWidget {
  /// The admin authors the shared default library every coach can see; a coach
  /// only ever adds private entries, and cannot change the shared ones.
  final bool isAdmin;

  const ExerciseLibraryScreen({super.key, this.isAdmin = false});

  @override
  State<ExerciseLibraryScreen> createState() => _ExerciseLibraryScreenState();
}

class _ExerciseLibraryScreenState extends State<ExerciseLibraryScreen> {
  List<LibraryExercise> _exercises = [];
  bool _loading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final exercises = await SupabaseService.loadLibraryExercises();
      setState(() => _exercises = exercises);
    } catch (e) {
      if (mounted) showAppMessage(context, 'Failed to load exercises', isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<LibraryExercise> get _filtered => _search.isEmpty
      ? _exercises
      : _exercises
          .where((e) => e.name.toLowerCase().contains(_search.toLowerCase()))
          .toList();

  Future<void> _addExercise() async {
    final result = await ExerciseFormSheet.show(context, title: 'New Library Exercise');
    if (result == null) return;
    try {
      final exercise = LibraryExercise(
        id: '',
        name: result.name,
        setRows: result.setRows,
        restTime: result.restTime,
        videoUrl: result.videoUrl,
        eachSide: result.eachSide,
        notes: result.notes,   
      );
      await SupabaseService.addLibraryExercise(exercise, asGlobal: widget.isAdmin);
      await _load();
      if (mounted) showAppMessage(context, 'Exercise added to library!');
    } catch (e) {
      if (mounted) showAppMessage(context, 'Failed to add exercise', isError: true);
    }
  }

  Future<void> _editExercise(LibraryExercise exercise) async {
    final shim = Exercise(
      id: exercise.id,
      programId: '',
      name: exercise.name,
      setRows: exercise.setRows,
      restTime: exercise.restTime,
      videoUrl: exercise.videoUrl,
      eachSide: exercise.eachSide,
      notes: exercise.notes,
    );
    final result = await ExerciseFormSheet.show(context, initial: shim, title: 'Edit Exercise');
    if (result == null) return;
    try {
      exercise
        ..name = result.name
        ..setRows = result.setRows
        ..restTime = result.restTime
        ..videoUrl = result.videoUrl
        ..eachSide = result.eachSide;
        
      await SupabaseService.updateLibraryExercise(exercise);
      await _load();
      if (mounted) showAppMessage(context, 'Exercise updated!');
    } catch (e) {
      if (mounted) showAppMessage(context, 'Failed to update exercise', isError: true);
    }
  }

  Future<void> _deleteExercise(LibraryExercise exercise) async {
    try {
      await SupabaseService.deleteLibraryExercise(exercise.id);
      await _load();
      if (mounted) showAppMessage(context, 'Exercise deleted');
    } catch (e) {
      if (mounted) showAppMessage(context, 'Failed to delete exercise', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Exercise Library')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addExercise,
        icon: const Icon(Icons.add),
        label: const Text('New Exercise'),
        backgroundColor: const Color(0xFF16A34A),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search, color: Colors.white54),
                hintText: 'Search exercises...',
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? const Center(
                        child: Text('No exercises found.',
                            style: TextStyle(color: Colors.white38)))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                        itemCount: _filtered.length,
                        itemBuilder: (context, index) {
                          final ex = _filtered[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0xFF334155)),
                            ),
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(ex.name,
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 15)),
                                          ),
                                          if (ex.isGlobal) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 6, vertical: 1),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF3B82F6),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: const Text('SHARED',
                                                  style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 9,
                                                      fontWeight: FontWeight.bold)),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(ex.setsSummary(),
                                          style: const TextStyle(
                                              color: Colors.white54, fontSize: 12.5)),
                                    ],
                                  ),
                                ),
                                // Shared entries belong to the admin's default
                                // library; a coach may use them but not change
                                // them (RLS refuses the write regardless).
                                if (ex.isGlobal && !widget.isAdmin)
                                  const Padding(
                                    padding: EdgeInsets.only(right: 8),
                                    child: Icon(Icons.lock_outline,
                                        color: Colors.white24, size: 18),
                                  )
                                else
                                  PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert, color: Colors.white54),
                                    color: const Color(0xFF334155),
                                    onSelected: (value) {
                                      if (value == 'edit') _editExercise(ex);
                                      if (value == 'delete') _deleteExercise(ex);
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(
                                          value: 'edit',
                                          child: Text('Edit', style: TextStyle(color: Colors.white))),
                                      PopupMenuItem(
                                          value: 'delete',
                                          child: Text('Delete',
                                              style: TextStyle(color: Colors.redAccent))),
                                    ],
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
