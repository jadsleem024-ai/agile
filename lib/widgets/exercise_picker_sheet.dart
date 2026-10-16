import 'package:flutter/material.dart';
import '../models/library_exercise.dart';
import '../services/supabase_service.dart';

class ExercisePickerSheet {
  static Future<List<LibraryExercise>?> show(
    BuildContext context, {
    bool multiSelect = false,
    String title = 'Select Exercise',
  }) {
    return showModalBottomSheet<List<LibraryExercise>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _ExercisePickerBody(multiSelect: multiSelect, title: title),
    );
  }
}

class _ExercisePickerBody extends StatefulWidget {
  final bool multiSelect;
  final String title;
  const _ExercisePickerBody({required this.multiSelect, required this.title});

  @override
  State<_ExercisePickerBody> createState() => _ExercisePickerBodyState();
}

class _ExercisePickerBodyState extends State<_ExercisePickerBody> {
  List<LibraryExercise> _all = [];
  final List<LibraryExercise> _selected = [];
  bool _loading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await SupabaseService.loadLibraryExercises();
      setState(() {
        _all = data;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  List<LibraryExercise> get _filtered => _search.isEmpty
      ? _all
      : _all.where((e) => e.name.toLowerCase().contains(_search.toLowerCase())).toList();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              TextField(
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search, color: Colors.white54),
                  hintText: 'Search exercises...',
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _filtered.isEmpty
                        ? const Center(
                            child: Text(
                                'No exercises found.\nAdd some in the Exercise Library first.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white38)))
                        : ListView.builder(
                            itemCount: _filtered.length,
                            itemBuilder: (_, i) {
                              final ex = _filtered[i];
                              final isSelected = _selected.contains(ex);
                              return ListTile(
                                title: Text(ex.name, style: const TextStyle(color: Colors.white)),
                                subtitle: Text(ex.setsSummary(),
                                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
                                trailing: widget.multiSelect
                                    ? Icon(
                                        isSelected ? Icons.check_circle : Icons.circle_outlined,
                                        color: isSelected ? const Color(0xFF16A34A) : Colors.white24,
                                      )
                                    : const Icon(Icons.chevron_right, color: Colors.white24),
                                onTap: () {
                                  if (widget.multiSelect) {
                                    setState(() {
                                      if (isSelected) {
                                        _selected.remove(ex);
                                      } else {
                                        _selected.add(ex);
                                      }
                                    });
                                  } else {
                                    Navigator.pop(context, [ex]);
                                  }
                                },
                              );
                            },
                          ),
              ),
              if (widget.multiSelect) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _selected.isEmpty ? null : () => Navigator.pop(context, _selected),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF16A34A)),
                    child: Text('Add ${_selected.length} Exercise${_selected.length == 1 ? '' : 's'}'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}