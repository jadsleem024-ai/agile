import 'package:flutter/material.dart';
import '../models/exercise.dart';
import 'video_upload_field.dart';
import 'set_rows_editor.dart';

class ExerciseFormResult {
  final String name;
  final List<SetRow> setRows;
  final int restTime;
  final String? videoUrl;
  final bool eachSide;
  final String? notes;   // <-- add this

  ExerciseFormResult({
    required this.name,
    required this.setRows,
    required this.restTime,
    required this.videoUrl,
    required this.eachSide,
    this.notes,   // <-- add this
  });
}

class ExerciseFormSheet extends StatefulWidget {
  final Exercise? initial;
  final String title;

  const ExerciseFormSheet({super.key, this.initial, this.title = 'Add Exercise'});

  static Future<ExerciseFormResult?> show(BuildContext context, {Exercise? initial, String title = 'Add Exercise'}) {
    return showModalBottomSheet<ExerciseFormResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ExerciseFormSheet(initial: initial, title: title),
    );
  }

  @override
  State<ExerciseFormSheet> createState() => _ExerciseFormSheetState();
}

class _ExerciseFormSheetState extends State<ExerciseFormSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _restController;
  late final TextEditingController _notesController;   // <-- add this
  late List<SetRow> _setRows;
  String? _videoUrl;
  bool _eachSide = false;

  @override
  void initState() {
    super.initState();
    final ex = widget.initial;
    _nameController = TextEditingController(text: ex?.name ?? '');
    _restController = TextEditingController(text: (ex?.restTime ?? 60).toString());
    _notesController = TextEditingController(text: ex?.notes ?? '');   // <-- add this
    _setRows = ex != null && ex.setRows.isNotEmpty
        ? ex.setRows.map((r) => r.copy()).toList()
        : List.generate(3, (_) => SetRow());
    _videoUrl = ex?.videoUrl;
    _eachSide = ex?.eachSide ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _restController.dispose();
    _notesController.dispose();   // <-- add this
    super.dispose();
  }

  void _save() {
    if (_nameController.text.trim().isEmpty) return;
    Navigator.pop(
      context,
      ExerciseFormResult(
        name: _nameController.text.trim(),
        setRows: _setRows,
        restTime: int.tryParse(_restController.text) ?? 60,
        videoUrl: _videoUrl,
        eachSide: _eachSide,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),   // <-- add this
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1E293B),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(20),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4)),
                ),
              ),
              Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                controller: _nameController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(hintText: 'Exercise name'),
              ),
              const SizedBox(height: 12),
              VideoUploadField(videoUrl: _videoUrl, onChanged: (url) => setState(() => _videoUrl = url)),
              const SizedBox(height: 16),
              SetRowsEditor(rows: _setRows, onChanged: (rows) => setState(() => _setRows = rows)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _restController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(labelText: 'Rest (s)'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() => _eachSide = !_eachSide),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: _eachSide ? const Color(0xFF2563EB) : Colors.transparent,
                        side: BorderSide(color: _eachSide ? const Color(0xFF2563EB) : const Color(0xFF475569)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(_eachSide ? '✓ Each Side' : 'Each Side', style: const TextStyle(color: Colors.white)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _notesController,
                maxLines: 3,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Coach notes',
                  hintText: 'Optional notes for the trainee',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(child: ElevatedButton(onPressed: _save, child: const Text('Save'))),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20)),
                    child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}