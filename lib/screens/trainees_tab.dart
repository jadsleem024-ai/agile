import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/trainee.dart';
import '../models/program.dart';
import '../services/supabase_service.dart';
import 'coach_panel_screen.dart';

class TraineesTab extends StatefulWidget {
  const TraineesTab({super.key});

  @override
  State<TraineesTab> createState() => _TraineesTabState();
}

class _TraineesTabState extends State<TraineesTab> {
  List<Trainee> _trainees = [];
  List<Program> _programs = [];
  Map<String, List<String>> _traineePrograms = {};

  bool _loading = true;
  bool _showAddForm = false;

  final _nameController = TextEditingController();
  final _codeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final trainees = await SupabaseService.loadTrainees();
      final programs = await SupabaseService.loadPrograms();
      final traineePrograms = await SupabaseService.loadTraineePrograms();
      setState(() {
        _trainees = trainees;
        _programs = programs;
        _traineePrograms = traineePrograms;
      });
    } catch (e) {
      if (mounted) showAppMessage(context, 'Failed to load trainees', isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addTrainee() async {
    if (_nameController.text.trim().isEmpty) {
      showAppMessage(context, 'Please enter trainee name', isError: true);
      return;
    }
    try {
      final trainee = await SupabaseService.addTrainee(_nameController.text.trim(), _codeController.text.trim());
      setState(() {
        _trainees = [trainee, ..._trainees];
        _nameController.clear();
        _codeController.clear();
        _showAddForm = false;
      });
      showAppMessage(context, 'Trainee added! Code: ${trainee.code}');
    } catch (e) {
      showAppMessage(context, 'Failed to add trainee', isError: true);
    }
  }

  Future<void> _deleteTrainee(Trainee trainee) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Delete trainee?', style: TextStyle(color: Colors.white)),
        content: const Text('This will remove all their progress data.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await SupabaseService.deleteTrainee(trainee.id);
      setState(() => _trainees.removeWhere((t) => t.id == trainee.id));
      showAppMessage(context, 'Trainee deleted');
    } catch (e) {
      showAppMessage(context, 'Failed to delete trainee', isError: true);
    }
  }

  Future<void> _addProgramToRotation(Trainee trainee, String programId) async {
    final current = _traineePrograms[trainee.id] ?? [];
    if (current.contains(programId)) {
      showAppMessage(context, 'Program already in rotation', isError: true);
      return;
    }
    final updated = [...current, programId];
    await _saveRotation(trainee.id, updated);
  }

  Future<void> _removeProgramFromRotation(String traineeId, String programId) async {
    final updated = (_traineePrograms[traineeId] ?? []).where((id) => id != programId).toList();
    await _saveRotation(traineeId, updated);
  }

  Future<void> _moveProgram(String traineeId, int from, int to) async {
    final current = List<String>.from(_traineePrograms[traineeId] ?? []);
    final moved = current.removeAt(from);
    current.insert(to, moved);
    await _saveRotation(traineeId, current);
  }

  Future<void> _saveRotation(String traineeId, List<String> programIds) async {
    try {
      await SupabaseService.saveMultiPrograms(traineeId, programIds);
      setState(() => _traineePrograms = {..._traineePrograms, traineeId: programIds});
      await _loadAll();
      showAppMessage(
          context, programIds.length > 1 ? '${programIds.length} programs assigned in rotation!' : 'Program assigned!');
    } catch (e) {
      showAppMessage(context, 'Failed to save program rotation', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Trainees', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              ElevatedButton.icon(
                onPressed: () => setState(() => _showAddForm = !_showAddForm),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add'),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_showAddForm) _buildAddForm(),
          if (_trainees.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.groups_outlined, size: 48, color: Colors.white24),
                    SizedBox(height: 12),
                    Text('No trainees yet. Add your first trainee!', style: TextStyle(color: Colors.white38)),
                  ],
                ),
              ),
            ),
          ..._trainees.map(_buildTraineeCard),
        ],
      ),
    );
  }

  Widget _buildAddForm() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Add New Trainee', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          TextField(controller: _nameController, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: 'Trainee name')),
          const SizedBox(height: 8),
          TextField(
            controller: _codeController,
            style: const TextStyle(color: Colors.white),
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(hintText: 'Access code (leave empty to auto-generate)'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: ElevatedButton(onPressed: _addTrainee, child: const Text('Add Trainee'))),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => setState(() => _showAddForm = false),
                icon: const Icon(Icons.close, color: Colors.white70),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// How many times the rotation repeats before the trainee's screen locks,
  /// plus where they currently are in it.
  Widget _buildLoopControl(Trainee trainee, int dayCount) {
    final target = trainee.loopTarget;
    final done = trainee.blockPosition;
    final loopsDone = dayCount > 0 ? done ~/ dayCount : 0;
    final complete = target != null && dayCount > 0 && done >= dayCount * target;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: complete ? const Color(0x1A22C55E) : const Color(0xFF334155),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: complete ? const Color(0xFF22C55E) : const Color(0xFF475569)),
      ),
      child: Row(
        children: [
          Icon(complete ? Icons.emoji_events : Icons.repeat,
              size: 16,
              color: complete ? const Color(0xFF4ADE80) : Colors.white54),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  target == null ? 'Repeats forever' : 'Loops: $loopsDone of $target',
                  style: TextStyle(
                    color: complete ? const Color(0xFF4ADE80) : Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  complete
                      ? 'Block complete — assign a new program to unlock'
                      : '$done ${done == 1 ? 'session' : 'sessions'} finished',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _editLoopTarget(trainee),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Set', style: TextStyle(fontSize: 12)),
          ),
          IconButton(
            onPressed: () => _clearProgress(trainee),
            icon: const Icon(Icons.delete_sweep_outlined, size: 20),
            color: const Color(0xFFF87171),
            tooltip: 'Clear all progress',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  /// Wipes a trainee's logged history once their block is over. Deliberately
  /// double-guarded: this is not undoable and the coach loses the record of
  /// every weight and note the trainee entered.
  Future<void> _clearProgress(Trainee trainee) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Clear all progress?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Deletes every logged session for ${trainee.name} — all weights, notes '
          'and completed sets — and puts them back at Day 1, Loop 1.\n\n'
          'This cannot be undone.',
          style: const TextStyle(color: Colors.white70, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            child: const Text('Delete everything'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final removed =
          await SupabaseService.clearTraineeProgress(trainee.id, trainee.code);
      if (!mounted) return;
      setState(() {
        _trainees = _trainees
            .map((t) => t.id == trainee.id ? t.copyWith(blockPosition: 0) : t)
            .toList();
      });
      showAppMessage(context, 'Cleared $removed rows for ${trainee.name}');
    } catch (e) {
      if (mounted) showAppMessage(context, 'Could not clear progress', isError: true);
    }
  }

  Future<void> _editLoopTarget(Trainee trainee) async {
    final controller =
        TextEditingController(text: trainee.loopTarget?.toString() ?? '');
    final result = await showDialog<int?>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Program loops', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'How many times should the whole rotation repeat before the '
              'trainee is locked out and you set a new block?',
              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'e.g. 3  (leave empty = forever)',
                hintStyle: TextStyle(color: Colors.white38),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, -1), // sentinel: clear it
            child: const Text('Forever', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              final v = int.tryParse(controller.text.trim());
              Navigator.pop(ctx, (v == null || v <= 0) ? -1 : v);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null) return;

    final loops = result == -1 ? null : result;
    try {
      await SupabaseService.setLoopTarget(trainee.id, loops);
      if (!mounted) return;
      setState(() {
        _trainees = _trainees
            .map((t) => t.id == trainee.id
                ? t.copyWith(loopTarget: loops, clearLoopTarget: loops == null)
                : t)
            .toList();
      });
      showAppMessage(
          context, loops == null ? 'Set to repeat forever' : 'Set to $loops loops');
    } catch (e) {
      if (mounted) showAppMessage(context, 'Could not save the loop count', isError: true);
    }
  }

  Widget _buildTraineeCard(Trainee trainee) {
    final rotation = _traineePrograms[trainee.id] ?? [];
    final availablePrograms = _programs.where((p) => !rotation.contains(p.id)).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(trainee.name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text('Code: ${trainee.code}', style: const TextStyle(color: Colors.white54, fontSize: 13)),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.copy, size: 14, color: Colors.blue),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: trainee.code));
                            showAppMessage(context, 'Copied to clipboard!');
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => _deleteTrainee(trainee),
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildLoopControl(trainee, rotation.length),
          const SizedBox(height: 12),
          const Text('Assigned Programs:', style: TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 8),
          if (rotation.isEmpty)
            const Text('No programs assigned', style: TextStyle(color: Colors.white38, fontSize: 13))
          else
            ...rotation.asMap().entries.map((entry) {
              final idx = entry.key;
              final programId = entry.value;
              final program = _programs.where((p) => p.id == programId).firstOrNull;
              if (program == null) return const SizedBox.shrink();
              final isActive = trainee.programId == programId;
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: isActive ? const Color(0x1A22C55E) : const Color(0xFF334155),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: isActive ? const Color(0xFF22C55E) : const Color(0xFF475569)),
                ),
                child: Row(
                  children: [
                    Text('Day ${idx + 1}', style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        program.name + (isActive ? '  ← Today' : ''),
                        style: TextStyle(color: isActive ? const Color(0xFF4ADE80) : Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ),
                    if (idx > 0)
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.arrow_upward, size: 16, color: Colors.white54),
                        onPressed: () => _moveProgram(trainee.id, idx, idx - 1),
                      ),
                    if (idx < rotation.length - 1)
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.arrow_downward, size: 16, color: Colors.white54),
                        onPressed: () => _moveProgram(trainee.id, idx, idx + 1),
                      ),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close, size: 16, color: Colors.redAccent),
                      onPressed: () => _removeProgramFromRotation(trainee.id, programId),
                    ),
                  ],
                ),
              );
            }),
          const SizedBox(height: 6),
          if (availablePrograms.isNotEmpty)
            DropdownButtonFormField<String>(
              value: null,
              hint: const Text('+ Add program to rotation...', style: TextStyle(color: Colors.white38, fontSize: 13)),
              dropdownColor: const Color(0xFF334155),
              items: availablePrograms
                  .map((p) => DropdownMenuItem(value: p.id, child: Text(p.name, style: const TextStyle(color: Colors.white))))
                  .toList(),
              onChanged: (value) {
                if (value != null) _addProgramToRotation(trainee, value);
              },
            ),
        ],
      ),
    );
  }
}

extension FirstOrNullExt<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
