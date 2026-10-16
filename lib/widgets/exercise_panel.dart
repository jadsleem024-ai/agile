import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/workout.dart';
import '../utils/format.dart';

class SetTimerState {
  int seconds;
  bool running;
  SetTimerState({required this.seconds, required this.running});
}

/// One exercise: its plan, a row per set with a weight box and a done tick,
/// and the trainee's notes.
///
/// Stateful purely so the text fields own persistent controllers. They used to
/// be rebuilt from the model on every frame, which re-wrote the field mid-entry
/// and turned "12.5" into "12.05" — the controllers below are only refreshed
/// when the value genuinely changed elsewhere and the field is not focused.
class ExercisePanel extends StatefulWidget {
  final Workout workout;
  final List<dynamic> weights; // current weight per set index
  final Map<int, SetTimerState> setTimers; // setIdx -> timer state
  final void Function(int setIdx, String value) onWeightChange;
  final void Function(int setIdx) onToggleComplete;
  final void Function(int setIdx, int duration) onStartSetTimer;
  final void Function(int setIdx) onStopSetTimer;
  final void Function(int setIdx, int duration) onResetSetTimer;
  final void Function(String notes) onNotesChange;
  final VoidCallback? onWatchVideo;

  /// If non-null, renders a small numbered badge (used inside a group) with this color.
  final Color? badgeColor;
  final int? badgeNumber;
  final bool compact;

  const ExercisePanel({
    super.key,
    required this.workout,
    required this.weights,
    required this.setTimers,
    required this.onWeightChange,
    required this.onToggleComplete,
    required this.onStartSetTimer,
    required this.onStopSetTimer,
    required this.onResetSetTimer,
    required this.onNotesChange,
    this.onWatchVideo,
    this.badgeColor,
    this.badgeNumber,
    this.compact = false,
  });

  @override
  State<ExercisePanel> createState() => _ExercisePanelState();
}

class _ExercisePanelState extends State<ExercisePanel> {
  final Map<int, TextEditingController> _weightControllers = {};
  final Map<int, FocusNode> _weightFocus = {};
  late TextEditingController _notesController;
  final FocusNode _notesFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _notesController = TextEditingController(text: widget.workout.notes);
    _syncWeightControllers();
  }

  @override
  void didUpdateWidget(covariant ExercisePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncWeightControllers();

    if (!_notesFocus.hasFocus && _notesController.text != widget.workout.notes) {
      _notesController.text = widget.workout.notes;
    }
  }

  @override
  void dispose() {
    for (final c in _weightControllers.values) {
      c.dispose();
    }
    for (final f in _weightFocus.values) {
      f.dispose();
    }
    _notesController.dispose();
    _notesFocus.dispose();
    super.dispose();
  }

  /// Adopts externally-changed weights (a reload, a reset) without ever
  /// touching a field the trainee is currently typing into.
  void _syncWeightControllers() {
    for (var i = 0; i < widget.workout.setRows.length; i++) {
      final incoming = i < widget.weights.length ? formatWeight(widget.weights[i]) : '';
      final controller = _weightControllers.putIfAbsent(
        i,
        () => TextEditingController(text: incoming),
      );
      _weightFocus.putIfAbsent(i, () => FocusNode());

      if (_weightFocus[i]!.hasFocus) continue;
      // Compare numerically so "12.50" typed earlier is not clobbered by "12.5".
      if (formatWeight(controller.text) != incoming) {
        controller.text = incoming;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final workout = widget.workout;
    final compact = widget.compact;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (widget.badgeColor != null && widget.badgeNumber != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                              color: widget.badgeColor, borderRadius: BorderRadius.circular(4)),
                          child: Text('${widget.badgeNumber}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11)),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Text(
                          workout.name,
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: compact ? 14 : 17),
                        ),
                      ),
                      if (workout.eachSide) ...[
                        const SizedBox(width: 6),
                        Tooltip(
                          message: 'Each Side — do all the reps on one side, then the other',
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                                color: const Color(0xFF3B82F6),
                                borderRadius: BorderRadius.circular(4)),
                            child: const Text('ES',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                      if (!compact && workout.videoUrl != null) ...[
                        const SizedBox(width: 8),
                        _watchButton(),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(workout.setsSummaryLine(),
                      style: TextStyle(color: Colors.white54, fontSize: compact ? 12 : 13)),
                ],
              ),
            ),
            if (compact && workout.videoUrl != null) _watchButton(),
          ],
        ),
        SizedBox(height: compact ? 8 : 12),
        ...List.generate(workout.setRows.length, _buildSetRow),
        SizedBox(height: compact ? 8 : 12),
        TextField(
          controller: _notesController,
          focusNode: _notesFocus,
          onChanged: widget.onNotesChange,
          maxLines: compact ? 1 : 2,
          textCapitalization: TextCapitalization.sentences,
          style: TextStyle(color: Colors.white, fontSize: compact ? 12 : 13),
          decoration: InputDecoration(
            hintText: compact ? 'Notes...' : 'Add notes (e.g., felt strong, increase weight next time...)',
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: const Color(0xFF334155),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            isDense: true,
          ),
        ),
      ],
    );
  }

  Widget _watchButton() {
    return ElevatedButton.icon(
      onPressed: widget.onWatchVideo,
      icon: const Icon(Icons.play_circle_outline, size: 16),
      label: Text(widget.compact ? 'Watch' : 'Watch Video', style: const TextStyle(fontSize: 12)),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF16A34A),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  Widget _buildSetRow(int setIdx) {
    final workout = widget.workout;
    final compact = widget.compact;
    final row = workout.setRows[setIdx];
    final isComplete = workout.completedSets.contains(setIdx);
    final isTime = row.type == 'time';
    final timer = widget.setTimers[setIdx];
    final running = timer?.running ?? false;
    final secs = timer?.seconds ?? row.duration;

    // The planned load, shown as placeholder text so an untouched field reads
    // as a suggestion rather than as a recorded 0.0.
    final planned = parseWeight(row.weight);
    final hint = (planned != null && planned > 0) ? formatWeight(planned) : 'BW';

    final bg = isComplete
        ? const Color(0x3322C55E)
        : isTime
            ? const Color(0x3D9333EA)
            : const Color(0xFF334155);
    final borderColor = isComplete
        ? const Color(0xFF22C55E)
        : isTime
            ? const Color(0xFF7E22CE)
            : const Color(0xFF475569);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: compact ? 6 : 8),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: borderColor)),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: Text(
              '${setIdx + 1}',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: isComplete
                      ? const Color(0xFF4ADE80)
                      : (isTime ? const Color(0xFFC084FC) : Colors.white54),
                  fontWeight: FontWeight.bold,
                  fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _weightControllers[setIdx],
              focusNode: _weightFocus[setIdx],
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [DecimalWeightFormatter()],
              onChanged: (v) => widget.onWeightChange(setIdx, v),
              style: TextStyle(
                  color: isComplete ? const Color(0xFF86EFAC) : Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(
                    color: isComplete ? const Color(0x8022C55E) : Colors.white38, fontSize: 13),
                suffixText: 'kg',
                suffixStyle: TextStyle(
                    color: isComplete ? const Color(0x8022C55E) : Colors.white38, fontSize: 11),
                isDense: true,
                filled: true,
                fillColor: isComplete ? const Color(0x2622C55E) : const Color(0xFF475569),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (isTime)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 38,
                  child: Text(
                    formatDuration(secs),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: isComplete
                            ? const Color(0xFF4ADE80)
                            : (running ? const Color(0xFFD8B4FE) : Colors.white),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ),
                if (!isComplete) ...[
                  const SizedBox(width: 4),
                  _smallIconButton(
                    icon: running ? Icons.pause : Icons.play_arrow,
                    color: running ? const Color(0xFFCA8A04) : const Color(0xFF9333EA),
                    onTap: () => running
                        ? widget.onStopSetTimer(setIdx)
                        : widget.onStartSetTimer(setIdx, secs > 0 ? secs : row.duration),
                  ),
                  const SizedBox(width: 4),
                  _smallIconButton(
                      icon: Icons.replay,
                      color: const Color(0xFF475569),
                      onTap: () => widget.onResetSetTimer(setIdx, row.duration)),
                ],
              ],
            )
          else
            SizedBox(
              width: 54,
              child: Text('× ${row.reps}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: isComplete ? const Color(0xFF4ADE80) : Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => widget.onToggleComplete(setIdx),
            child: Container(
              width: compact ? 28 : 34,
              height: compact ? 28 : 34,
              decoration: BoxDecoration(
                color: isComplete ? const Color(0xFF22C55E) : const Color(0xFF475569),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(isComplete ? Icons.check : Icons.circle_outlined,
                  color: isComplete ? Colors.white : Colors.white54, size: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _smallIconButton(
      {required IconData icon, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 14, color: Colors.white),
      ),
    );
  }
}

/// Accepts a single decimal number, normalising a typed comma to a dot so the
/// value still parses on a locale keyboard that offers ",".
class DecimalWeightFormatter extends TextInputFormatter {
  static final _valid = RegExp(r'^\d{0,4}([.]\d{0,2})?$');

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;
    final normalized = newValue.text.replaceAll(',', '.');
    if (!_valid.hasMatch(normalized)) return oldValue;
    return newValue.copyWith(
      text: normalized,
      selection: TextSelection.collapsed(
        offset: newValue.selection.baseOffset.clamp(0, normalized.length),
      ),
    );
  }
}
