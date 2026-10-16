import 'package:flutter/material.dart';
import '../models/exercise.dart';

class SetRowsEditor extends StatefulWidget {
  final List<SetRow> rows;
  final ValueChanged<List<SetRow>> onChanged;

  const SetRowsEditor({super.key, required this.rows, required this.onChanged});

  @override
  State<SetRowsEditor> createState() => _SetRowsEditorState();
}

class _SetRowsEditorState extends State<SetRowsEditor> {
  late List<SetRow> _rows;
  late List<TextEditingController> _weightControllers;
  late List<TextEditingController> _repsControllers;

  @override
  void initState() {
    super.initState();
    _rows = widget.rows.map((r) => r.copy()).toList();
    _weightControllers = _rows.map((r) => TextEditingController(text: r.weight == 0 ? '' : _trimNum(r.weight))).toList();
    _repsControllers = _rows
        .map((r) => TextEditingController(
            text: r.type == 'time' ? (r.duration == 0 ? '' : r.duration.toString()) : (r.reps == 0 ? '' : r.reps.toString())))
        .toList();
  }

  String _trimNum(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  void dispose() {
    for (final c in _weightControllers) {
      c.dispose();
    }
    for (final c in _repsControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _notify() => widget.onChanged(_rows.map((r) => r.copy()).toList());

  void _addRow() {
    setState(() {
      _rows.add(SetRow());
      _weightControllers.add(TextEditingController());
      _repsControllers.add(TextEditingController(text: '10'));
    });
    _notify();
  }

  void _removeRow(int index) {
    setState(() {
      _rows.removeAt(index);
      _weightControllers.removeAt(index).dispose();
      _repsControllers.removeAt(index).dispose();
    });
    _notify();
  }

  void _toggleType(int index, String type) {
    setState(() {
      _rows[index].type = type;
      _repsControllers[index].text = type == 'time'
          ? (_rows[index].duration == 0 ? '' : _rows[index].duration.toString())
          : (_rows[index].reps == 0 ? '' : _rows[index].reps.toString());
    });
    _notify();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Sets (rows)', style: TextStyle(color: Colors.white54, fontSize: 12)),
            TextButton.icon(
              onPressed: _addRow,
              icon: const Icon(Icons.add, size: 14),
              label: const Text('Add Row', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ...List.generate(_rows.length, (idx) {
          final row = _rows[idx];
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                SizedBox(width: 18, child: Text('${idx + 1}', style: const TextStyle(color: Colors.white38, fontSize: 12))),
                Expanded(
                  child: TextField(
                    controller: _weightControllers[idx],
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(hintText: 'kg', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                    onChanged: (v) {
                      row.weight = double.tryParse(v) ?? 0;
                      _notify();
                    },
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: _repsControllers[idx],
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(hintText: row.type == 'time' ? 'secs' : 'reps', isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                    onChanged: (v) {
                      if (row.type == 'time') {
                        row.duration = int.tryParse(v) ?? 0;
                      } else {
                        row.reps = int.tryParse(v) ?? 0;
                      }
                      _notify();
                    },
                  ),
                ),
                const SizedBox(width: 6),
                ToggleButtons(
                  isSelected: [row.type != 'time', row.type == 'time'],
                  onPressed: (i) => _toggleType(idx, i == 0 ? 'reps' : 'time'),
                  borderRadius: BorderRadius.circular(8),
                  constraints: const BoxConstraints(minHeight: 32, minWidth: 32),
                  children: const [
                    Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('reps', style: TextStyle(fontSize: 11))),
                    Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('⏱', style: TextStyle(fontSize: 11))),
                  ],
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 16, color: Colors.redAccent),
                  onPressed: () => _removeRow(idx),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
