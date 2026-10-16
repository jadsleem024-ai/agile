import 'package:flutter/material.dart';
import '../models/program.dart';
import '../services/supabase_service.dart';
import 'coach_panel_screen.dart';
import 'program_detail_screen.dart';

class ProgramsTab extends StatefulWidget {
  const ProgramsTab({super.key});

  @override
  State<ProgramsTab> createState() => _ProgramsTabState();
}

class _ProgramsTabState extends State<ProgramsTab> {
  List<Program> _programs = [];
  bool _loading = true;
  bool _showAddForm = false;
  final _nameController = TextEditingController();
  final _descController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final programs = await SupabaseService.loadPrograms();
      setState(() => _programs = programs);
    } catch (e) {
      if (mounted) showAppMessage(context, 'Failed to load programs', isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addProgram() async {
    if (_nameController.text.trim().isEmpty) {
      showAppMessage(context, 'Please enter program name', isError: true);
      return;
    }
    try {
      final program = await SupabaseService.addProgram(_nameController.text.trim(), _descController.text.trim());
      setState(() {
        _programs = [program, ..._programs];
        _nameController.clear();
        _descController.clear();
        _showAddForm = false;
      });
      showAppMessage(context, 'Program created!');
    } catch (e) {
      showAppMessage(context, 'Failed to create program', isError: true);
    }
  }

  Future<void> _renameProgram(Program program) async {
    final controller = TextEditingController(text: program.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Rename Program', style: TextStyle(color: Colors.white)),
        content: TextField(controller: controller, autofocus: true, style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Save')),
        ],
      ),
    );
    if (newName == null || newName.trim().isEmpty) return;
    try {
      await SupabaseService.renameProgram(program.id, newName.trim());
      setState(() => _programs = _programs.map((p) => p.id == program.id ? Program(id: p.id, name: newName.trim(), description: p.description) : p).toList());
      showAppMessage(context, 'Program renamed!');
    } catch (e) {
      showAppMessage(context, 'Failed to rename program', isError: true);
    }
  }

  Future<void> _duplicateProgram(Program program) async {
    try {
      final newProgram = await SupabaseService.duplicateProgram(program);
      setState(() => _programs = [newProgram, ..._programs]);
      showAppMessage(context, 'Program duplicated as "${newProgram.name}"!');
    } catch (e) {
      showAppMessage(context, 'Failed to duplicate program', isError: true);
    }
  }

  Future<void> _deleteProgram(Program program) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Delete program?', style: TextStyle(color: Colors.white)),
        content: const Text('Trainees assigned to it will lose their program.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await SupabaseService.deleteProgram(program.id);
      setState(() => _programs.removeWhere((p) => p.id == program.id));
      showAppMessage(context, 'Program deleted');
    } catch (e) {
      showAppMessage(context, 'Failed to delete program', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Programs', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              ElevatedButton.icon(
                onPressed: () => setState(() => _showAddForm = !_showAddForm),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_showAddForm) _buildAddForm(),
          if (_programs.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.fitness_center_outlined, size: 48, color: Colors.white24),
                    SizedBox(height: 12),
                    Text('No programs yet. Create your first program!', style: TextStyle(color: Colors.white38)),
                  ],
                ),
              ),
            ),
          ..._programs.map(_buildProgramCard),
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
          const Text('Create New Program', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          TextField(controller: _nameController, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: 'Program name')),
          const SizedBox(height: 8),
          TextField(
            controller: _descController,
            maxLines: 2,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(hintText: 'Description (optional)'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: ElevatedButton(onPressed: _addProgram, child: const Text('Create Program'))),
              const SizedBox(width: 8),
              IconButton(onPressed: () => setState(() => _showAddForm = false), icon: const Icon(Icons.close, color: Colors.white70)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProgramCard(Program program) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: ListTile(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProgramDetailScreen(program: program))),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(program.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        subtitle: program.description.isNotEmpty
            ? Text(program.description, style: const TextStyle(color: Colors.white54), maxLines: 2, overflow: TextOverflow.ellipsis)
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(icon: const Icon(Icons.edit_outlined, size: 18, color: Colors.white54), onPressed: () => _renameProgram(program)),
            IconButton(icon: const Icon(Icons.copy_outlined, size: 18, color: Colors.blue), onPressed: () => _duplicateProgram(program)),
            IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent), onPressed: () => _deleteProgram(program)),
          ],
        ),
      ),
    );
  }
}
