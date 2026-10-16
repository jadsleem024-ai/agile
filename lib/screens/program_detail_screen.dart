import 'package:flutter/material.dart';
import '../models/program.dart';
import '../models/exercise.dart';
import '../models/library_exercise.dart';
import '../services/supabase_service.dart';
import '../widgets/exercise_form_sheet.dart';
import '../widgets/exercise_picker_sheet.dart';
import 'coach_panel_screen.dart';
import 'video_player_screen.dart';

class ProgramDetailScreen extends StatefulWidget {
  final Program program;
  const ProgramDetailScreen({super.key, required this.program});

  @override
  State<ProgramDetailScreen> createState() => _ProgramDetailScreenState();
}

class _ProgramDetailScreenState extends State<ProgramDetailScreen> {
  List<Exercise> _exercises = [];
  bool _loading = true;
  bool _hasUnsavedOrder = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final exercises = await SupabaseService.loadExercises(widget.program.id);
      setState(() {
        _exercises = exercises;
        _hasUnsavedOrder = false;
      });
    } catch (e) {
      if (mounted)
        showAppMessage(context, 'Failed to load exercises', isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<ExerciseListItem> get _items => groupExercisesForDisplay(_exercises);

  // ---------------- ADD SINGLE ----------------

  Future<void> _addSingleExercise() async {
    final result = await ExerciseFormSheet.show(context, title: 'Add Exercise');
    if (result == null) return;
    try {
      final exercise = Exercise(
        id: '',
        programId: widget.program.id,
        name: result.name,
        setRows: result.setRows,
        restTime: result.restTime,
        videoUrl: result.videoUrl,
        eachSide: result.eachSide,
        notes: result.notes,
        orderIndex: _exercises.length,
      );
      await SupabaseService.addSingleExercise(exercise);
      await _load();
      if (mounted) showAppMessage(context, 'Exercise added!');
    } catch (e) {
      if (mounted)
        showAppMessage(context, 'Failed to add exercise', isError: true);
    }
  }

  Future<void> _addFromLibrary() async {
    final picked = await ExercisePickerSheet.show(context, title: 'Add Exercise');
    if (picked == null || picked.isEmpty) return;
    final libEx = picked.first;
    try {
      final exercise = Exercise(
        id: '',
        programId: widget.program.id,
        name: libEx.name,
        setRows: libEx.setRows.map((r) => r.copy()).toList(),
        restTime: libEx.restTime,
        videoUrl: libEx.videoUrl,
        eachSide: libEx.eachSide,
        notes: libEx.notes,
        orderIndex: _exercises.length,
      );
      await SupabaseService.addSingleExercise(exercise);
      await _load();
      if (mounted) showAppMessage(context, 'Exercise added!');
    } catch (e) {
      if (mounted)
        showAppMessage(context, 'Failed to add exercise', isError: true);
    }
  }

  // ---------------- ADD GROUP (superset/triset/circuit) ----------------

  Future<void> _startGroupBuilder(String groupType) async {
    final req = getGroupRequirement(groupType);
    final staged = <ExerciseFormResult>[];
    String groupName = '';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) {
        return StatefulBuilder(builder: (sheetCtx, setSheetState) {
          bool canFinalize() =>
              staged.length >= req.min && staged.length <= req.max;

          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Build ${groupType.toUpperCase()}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('Requires ${req.label}',
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 13)),
                  const SizedBox(height: 12),
                  TextField(
                    style: const TextStyle(color: Colors.white),
                    decoration:
                        InputDecoration(hintText: '$groupType name (optional)'),
                    onChanged: (v) => groupName = v,
                  ),
                  const SizedBox(height: 12),
                  if (staged.isNotEmpty)
                    Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: staged.length,
                        itemBuilder: (_, i) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text('${i + 1}. ${staged[i].name}',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 14)),
                          trailing: IconButton(
                            icon: const Icon(Icons.close,
                                size: 18, color: Colors.redAccent),
                            onPressed: () =>
                                setSheetState(() => staged.removeAt(i)),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: staged.length >= req.max
                              ? null
                              : () async {
                                  final result = await ExerciseFormSheet.show(
                                      context,
                                      title: 'Exercise ${staged.length + 1}');
                                  if (result != null)
                                    setSheetState(() => staged.add(result));
                                },
                          icon: const Icon(Icons.add),
                          label: const Text('New'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: staged.length >= req.max
                              ? null
                              : () async {
                                  final remaining = req.max - staged.length;
                                  final picked = await ExercisePickerSheet.show(
                                    context,
                                    multiSelect: true,
                                    title: 'Add from Library',
                                  );
                                  if (picked != null && picked.isNotEmpty) {
                                    setSheetState(() {
                                      for (final libEx in picked.take(remaining)) {
                                        staged.add(ExerciseFormResult(
                                          name: libEx.name,
                                          setRows: libEx.setRows
                                              .map((r) => r.copy())
                                              .toList(),
                                          restTime: libEx.restTime,
                                          videoUrl: libEx.videoUrl,
                                          eachSide: libEx.eachSide,
                                          notes: libEx.notes,
                                        ));
                                      }
                                    });
                                  }
                                },
                          icon: const Icon(Icons.search),
                          label: const Text('Library'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: canFinalize()
                          ? () async {
                              Navigator.pop(sheetCtx);
                              await _finalizeGroup(
                                  groupType, groupName, staged);
                            }
                          : null,
                      icon: const Icon(Icons.check),
                      label: const Text('Finalize'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF16A34A)),
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  Future<void> _finalizeGroup(String groupType, String groupName,
      List<ExerciseFormResult> staged) async {
    try {
      final startOrder = _exercises.length;
      final exercises = staged.asMap().entries.map((entry) {
        return Exercise(
          id: '',
          programId: widget.program.id,
          name: entry.value.name,
          setRows: entry.value.setRows,
          restTime: entry.value.restTime,
          videoUrl: entry.value.videoUrl,
          eachSide: entry.value.eachSide,
          notes: entry.value.notes,
          orderIndex: startOrder + entry.key,
        );
      }).toList();
      await SupabaseService.addExerciseGroup(exercises, groupType,
          groupName.trim().isEmpty ? null : groupName.trim());
      await _load();
      if (mounted) showAppMessage(context, 'Exercise group added!');
    } catch (e) {
      if (mounted)
        showAppMessage(context, 'Failed to add exercises', isError: true);
    }
  }

  void _showAddMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.fitness_center, color: Colors.white),
              title: const Text('Single Exercise',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _addSingleExercise();
              },
            ),
            ListTile(
              leading: const Icon(Icons.search, color: Colors.tealAccent),
              title: const Text('From Library',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _addFromLibrary();
              },
            ),
            ListTile(
              leading: const Icon(Icons.link, color: Colors.orange),
              title: const Text('Superset (2 exercises)',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _startGroupBuilder('superset');
              },
            ),
            ListTile(
              leading: const Icon(Icons.link, color: Colors.purpleAccent),
              title: const Text('Triset (3 exercises)',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _startGroupBuilder('triset');
              },
            ),
            ListTile(
              leading: const Icon(Icons.link, color: Colors.greenAccent),
              title: const Text('Circuit (4-10 exercises)',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _startGroupBuilder('circuit');
              },
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- EDIT / DELETE ----------------

  Future<void> _editExercise(Exercise exercise) async {
    final result = await ExerciseFormSheet.show(context,
        initial: exercise, title: 'Edit Exercise');
    if (result == null) return;
    try {
      exercise
        ..name = result.name
        ..setRows = result.setRows
        ..restTime = result.restTime
        ..videoUrl = result.videoUrl
        ..eachSide = result.eachSide
        ..notes = result.notes;
      await SupabaseService.updateExercise(exercise);
      await _load();
      if (mounted) showAppMessage(context, 'Exercise updated!');
    } catch (e, st) {
      debugPrint('updateExercise error: $e\n$st');
      if (mounted)
        showAppMessage(context, 'Failed to update exercise: $e', isError: true);
    }
  }

  Future<void> _deleteExercise(Exercise exercise) async {
    try {
      await SupabaseService.deleteExercise(exercise.id, exercise.videoUrl);
      await _load();
      if (mounted) showAppMessage(context, 'Exercise deleted');
    } catch (e) {
      if (mounted)
        showAppMessage(context, 'Failed to delete exercise', isError: true);
    }
  }

  Future<void> _renameGroup(ExerciseGroup group) async {
    final controller = TextEditingController(text: group.groupName ?? '');
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Group name', style: TextStyle(color: Colors.white)),
        content: TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Save')),
        ],
      ),
    );
    if (newName == null) return;
    try {
      await SupabaseService.saveGroupName(
          group.groupId, newName.trim().isEmpty ? null : newName.trim());
      await _load();
      if (mounted) showAppMessage(context, 'Group name updated!');
    } catch (e) {
      if (mounted)
        showAppMessage(context, 'Failed to update group name', isError: true);
    }
  }

  Future<void> _ejectFromGroup(Exercise exercise) async {
    final remaining = _exercises
        .where((e) => e.groupId == exercise.groupId && e.id != exercise.id)
        .toList();
    try {
      await SupabaseService.ejectFromGroup(exercise, remaining);
      await _load();
      if (mounted) showAppMessage(context, 'Exercise removed from group!');
    } catch (e) {
      if (mounted)
        showAppMessage(context, 'Failed to eject exercise', isError: true);
    }
  }

  Future<void> _addToGroup(ExerciseGroup group) async {
    final req = getGroupRequirement(group.groupType);
    if (group.exercises.length >= req.max) {
      showAppMessage(
          context, 'This ${group.label.toLowerCase()} is already full (max ${req.max})',
          isError: true);
      return;
    }

    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.fitness_center, color: Colors.white),
              title: const Text('New Exercise', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(ctx, 'new'),
            ),
            ListTile(
              leading: const Icon(Icons.search, color: Colors.tealAccent),
              title: const Text('From Library', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(ctx, 'library'),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;

    final staged = <ExerciseFormResult>[];
    if (choice == 'new') {
      final result = await ExerciseFormSheet.show(context, title: 'New Exercise');
      if (result == null) return;
      staged.add(result);
    } else {
      final remaining = req.max - group.exercises.length;
      final picked = await ExercisePickerSheet.show(
        context,
        multiSelect: true,
        title: 'Add from Library',
      );
      if (picked == null || picked.isEmpty) return;
      staged.addAll(picked.take(remaining).map((libEx) => ExerciseFormResult(
            name: libEx.name,
            setRows: libEx.setRows.map((r) => r.copy()).toList(),
            restTime: libEx.restTime,
            videoUrl: libEx.videoUrl,
            eachSide: libEx.eachSide,
            notes: libEx.notes,
          )));
    }
    if (staged.isEmpty) return;

    try {
      final startOrder = _exercises.length;
      final exercises = staged.asMap().entries.map((entry) {
        return Exercise(
          id: '',
          programId: widget.program.id,
          name: entry.value.name,
          setRows: entry.value.setRows,
          restTime: entry.value.restTime,
          videoUrl: entry.value.videoUrl,
          eachSide: entry.value.eachSide,
          notes: entry.value.notes,
          orderIndex: startOrder + entry.key,
          groupId: group.groupId,
          groupType: group.groupType,
          groupName: group.groupName,
        );
      }).toList();
      await Future.wait(exercises.map(SupabaseService.addSingleExercise));
      await _load();
      if (mounted)
        showAppMessage(
            context, 'Exercise${exercises.length > 1 ? 's' : ''} added to group!');
    } catch (e) {
      if (mounted)
        showAppMessage(context, 'Failed to add exercise', isError: true);
    }
  }

  Future<void> _moveToGroup(Exercise exercise) async {
    final groups = groupExercisesForDisplay(_exercises)
        .where((i) => i.isGroup)
        .map((i) => i.group!)
        .toList();
    if (groups.isEmpty) {
      showAppMessage(context, 'No groups to move into yet — create one first',
          isError: true);
      return;
    }
    final chosen = await showModalBottomSheet<ExerciseGroup>(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: groups
              .map((g) => ListTile(
                    title: Text(g.groupName ?? g.label,
                        style: const TextStyle(color: Colors.white)),
                    subtitle: Text(
                        '${g.exercises.length} exercises · ${g.label.toLowerCase()}',
                        style: const TextStyle(color: Colors.white54)),
                    onTap: () => Navigator.pop(ctx, g),
                  ))
              .toList(),
        ),
      ),
    );
    if (chosen == null) return;
    try {
      await SupabaseService.moveIntoGroup(
          exercise, chosen.groupId, chosen.exercises);
      await _load();
      if (mounted) showAppMessage(context, 'Moved into group!');
    } catch (e) {
      if (mounted)
        showAppMessage(context, 'Failed to move exercise', isError: true);
    }
  }

  // ---------------- REORDER (top-level) ----------------

  void _onReorder(int oldIndex, int newIndex) {
    final items = _items;
    if (newIndex > oldIndex) newIndex -= 1;
    final moved = items.removeAt(oldIndex);
    items.insert(newIndex, moved);

    final flattened = <Exercise>[];
    for (final item in items) {
      if (item.isGroup) {
        flattened.addAll(item.group!.exercises);
      } else {
        flattened.add(item.single!);
      }
    }
    setState(() {
      _exercises = flattened;
      _hasUnsavedOrder = true;
    });
  }

  // ---------------- REORDER (within a group, via arrows) ----------------

  void _moveWithinGroup(String groupId, int indexInGroup, int delta) {
    final memberPositions = <int>[];
    for (int i = 0; i < _exercises.length; i++) {
      if (_exercises[i].groupId == groupId) memberPositions.add(i);
    }
    final targetIndex = indexInGroup + delta;
    if (targetIndex < 0 || targetIndex >= memberPositions.length) return;

    final posA = memberPositions[indexInGroup];
    final posB = memberPositions[targetIndex];
    setState(() {
      final tmp = _exercises[posA];
      _exercises[posA] = _exercises[posB];
      _exercises[posB] = tmp;
      _hasUnsavedOrder = true;
    });
  }

  Future<void> _saveOrder() async {
    try {
      await SupabaseService.reorderExercises(_exercises);
      setState(() => _hasUnsavedOrder = false);
      if (mounted) showAppMessage(context, 'Order saved!');
    } catch (e) {
      if (mounted)
        showAppMessage(context, 'Failed to save order', isError: true);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.program.name),
        actions: [
          if (_hasUnsavedOrder)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: _saveOrder,
                icon: const Icon(Icons.save, color: Colors.white),
                label:
                    const Text('Save', style: TextStyle(color: Colors.white)),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddMenu,
        icon: const Icon(Icons.add),
        label: const Text('Add Exercise'),
        backgroundColor: const Color(0xFF16A34A),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.fitness_center_outlined,
                          size: 48, color: Colors.white24),
                      SizedBox(height: 12),
                      Text('No exercises yet.',
                          style: TextStyle(color: Colors.white38)),
                      Text('Tap "Add Exercise" to start building!',
                          style:
                              TextStyle(color: Colors.white24, fontSize: 12)),
                    ],
                  ),
                )
              : ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  itemCount: _items.length,
                  onReorder: _onReorder,
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    return Padding(
                      key: ValueKey(item.isGroup
                          ? 'g_${item.group!.groupId}'
                          : 's_${item.single!.id}'),
                      padding: const EdgeInsets.only(bottom: 12),
                      child: item.isGroup
                          ? _buildGroupCard(item.group!)
                          : _buildSingleCard(item.single!),
                    );
                  },
                ),
    );
  }

  Widget _buildSingleCard(Exercise ex) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.drag_handle, color: Colors.white24),
          const SizedBox(width: 8),
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
                                fontSize: 15))),
                    if (ex.eachSide) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                            color: const Color(0xFF3B82F6),
                            borderRadius: BorderRadius.circular(4)),
                        child: const Text('ES',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold)),
                      ),
                    ],
                    if (ex.videoUrl != null) ...[
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => VideoPlayerScreen(
                                videoUrl: ex.videoUrl!, title: ex.name),
                          ),
                        ),
                        child: const Icon(Icons.play_circle_outline,
                            size: 16, color: Colors.greenAccent),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(ex.setsSummary(),
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 12.5)),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white54),
            color: const Color(0xFF334155),
            onSelected: (value) {
              if (value == 'edit') _editExercise(ex);
              if (value == 'delete') _deleteExercise(ex);
              if (value == 'group') _moveToGroup(ex);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: 'edit',
                  child: Text('Edit', style: TextStyle(color: Colors.white))),
              PopupMenuItem(
                  value: 'group',
                  child: Text('Move to group',
                      style: TextStyle(color: Colors.white))),
              PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete',
                      style: TextStyle(color: Colors.redAccent))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGroupCard(ExerciseGroup group) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.drag_handle, color: Colors.white24),
              const Icon(Icons.link, size: 16, color: Colors.white54),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  group.groupName != null
                      ? '${group.groupName} (${group.label.toLowerCase()})'
                      : group.label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline,
                    size: 18, color: Colors.white54),
                tooltip: 'Add exercise to group',
                onPressed: () => _addToGroup(group),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined,
                    size: 16, color: Colors.white54),
                onPressed: () => _renameGroup(group),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...group.exercises.asMap().entries.map((entry) {
            final idx = entry.key;
            final ex = entry.value;
            return Container(
              key: ValueKey('member_${ex.id}'),
              margin: const EdgeInsets.only(bottom: 6, left: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF334155),
                borderRadius: BorderRadius.circular(10),
                border: const Border(
                    left: BorderSide(color: Color(0xFF475569), width: 2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(Icons.arrow_drop_up,
                            size: 22, color: Colors.white54),
                        onPressed: idx == 0
                            ? null
                            : () => _moveWithinGroup(group.groupId, idx, -1),
                      ),
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(Icons.arrow_drop_down,
                            size: 22, color: Colors.white54),
                        onPressed: idx == group.exercises.length - 1
                            ? null
                            : () => _moveWithinGroup(group.groupId, idx, 1),
                      ),
                    ],
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                                child: Text('${idx + 1}. ${ex.name}',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w500))),
                            if (ex.videoUrl != null) ...[
                              const SizedBox(width: 6),
                              GestureDetector(
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => VideoPlayerScreen(
                                        videoUrl: ex.videoUrl!,
                                        title: ex.name),
                                  ),
                                ),
                                child: const Icon(Icons.play_circle_outline,
                                    size: 14, color: Colors.greenAccent),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(ex.setsSummary(),
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12)),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.more_vert,
                        size: 18, color: Colors.white54),
                    color: const Color(0xFF475569),
                    onSelected: (value) {
                      if (value == 'edit') _editExercise(ex);
                      if (value == 'delete') _deleteExercise(ex);
                      if (value == 'eject') _ejectFromGroup(ex);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                          value: 'edit',
                          child: Text('Edit',
                              style: TextStyle(color: Colors.white))),
                      PopupMenuItem(
                          value: 'eject',
                          child: Text('Remove from group',
                              style: TextStyle(color: Colors.white))),
                      PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete',
                              style: TextStyle(color: Colors.redAccent))),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}