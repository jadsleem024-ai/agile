import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/trainee.dart';
import '../models/progress.dart';
import '../services/supabase_service.dart';
import '../utils/format.dart';
import 'coach_panel_screen.dart';

/// What the coach came here for: for a given day, what each exercise was loaded
/// with and what the trainee said about it.
class ProgressTab extends StatefulWidget {
  const ProgressTab({super.key});

  @override
  State<ProgressTab> createState() => _ProgressTabState();
}

class _ProgressTabState extends State<ProgressTab> {
  List<Trainee> _trainees = [];
  Trainee? _selected;
  bool _loadingTrainees = true;
  bool _loadingProgress = false;

  DateTime _selectedDate = DateTime.now();
  List<ProgressEntry> _progressData = [];
  List<ProgramHistory> _history = [];
  String? _expandedProgram;
  bool _showHistory = false;

  @override
  void initState() {
    super.initState();
    _loadTrainees();
  }

  Future<void> _loadTrainees() async {
    setState(() => _loadingTrainees = true);
    try {
      final trainees = await SupabaseService.loadTrainees();
      if (mounted) setState(() => _trainees = trainees);
    } catch (e) {
      if (mounted) showAppMessage(context, 'Failed to load trainees', isError: true);
    } finally {
      if (mounted) setState(() => _loadingTrainees = false);
    }
  }

  Future<void> _selectTrainee(Trainee trainee) async {
    setState(() {
      _selected = trainee;
      _progressData = [];
      _history = [];
      _selectedDate = DateTime.now();
    });
    await _loadProgressAndHistory();
  }

  Future<void> _loadProgressAndHistory() async {
    if (_selected == null) return;
    setState(() => _loadingProgress = true);
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    try {
      final progress = await SupabaseService.loadTraineeProgress(_selected!.code, dateStr);
      final history = await SupabaseService.loadWorkoutHistory(_selected!.code);
      if (!mounted) return;
      setState(() {
        _progressData = progress;
        _history = history;
      });
    } catch (e) {
      if (mounted) showAppMessage(context, 'Failed to load progress', isError: true);
    } finally {
      if (mounted) setState(() => _loadingProgress = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      await _loadProgressAndHistory();
    }
  }

  void _shiftDate(int days) {
    final next = _selectedDate.add(Duration(days: days));
    if (next.isAfter(DateTime.now())) return;
    setState(() => _selectedDate = next);
    _loadProgressAndHistory();
  }

  String _formatDate(String isoDate) {
    try {
      return DateFormat('MMM d, yyyy').format(DateTime.parse(isoDate));
    } catch (_) {
      return isoDate;
    }
  }

  String _dateStrOf(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  bool get _isToday => _dateStrOf(_selectedDate) == _dateStrOf(DateTime.now());

  @override
  Widget build(BuildContext context) {
    if (_selected == null) {
      return _loadingTrainees
          ? const Center(child: CircularProgressIndicator())
          : _buildTraineeSelector();
    }
    return _buildProgressDetail();
  }

  // ---------------- TRAINEE PICKER ----------------

  Widget _buildTraineeSelector() {
    return RefreshIndicator(
      onRefresh: _loadTrainees,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Select Trainee',
              style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          if (_trainees.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: Text('No trainees yet', style: TextStyle(color: Colors.white38))),
            ),
          ..._trainees.map((t) => Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: ListTile(
                  title: Text(t.name,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: Text(
                      'Code: ${t.code}${t.programName != null ? '  ·  ${t.programName}' : ''}',
                      style: const TextStyle(color: Colors.white54)),
                  trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                  onTap: () => _selectTrainee(t),
                ),
              )),
        ],
      ),
    );
  }

  // ---------------- DETAIL ----------------

  Widget _buildProgressDetail() {
    return Column(
      children: [
        _buildTopBar(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadProgressAndHistory,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                if (_loadingProgress)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 60),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_progressData.isEmpty)
                  _buildEmptyState()
                else ...[
                  _buildDaySummary(),
                  const SizedBox(height: 14),
                  ..._progressData.map(_buildExerciseCard),
                ],
                const SizedBox(height: 8),
                _buildHistorySection(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 8, 12, 10),
      color: const Color(0xFF0F172A),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => setState(() => _selected = null),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_selected!.name,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                    Text('Code: ${_selected!.code}',
                        style: const TextStyle(color: Colors.white38, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Stepping a day at a time is the common move; the picker stays for
          // jumping further back.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, color: Colors.white70),
                  onPressed: () => _shiftDate(-1),
                  tooltip: 'Previous day',
                ),
                Expanded(
                  child: InkWell(
                    onTap: _pickDate,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        _isToday
                            ? 'Today · ${DateFormat('MMM d').format(_selectedDate)}'
                            : DateFormat('EEE, MMM d, yyyy').format(_selectedDate),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.chevron_right,
                      color: _isToday ? Colors.white24 : Colors.white70),
                  onPressed: _isToday ? null : () => _shiftDate(1),
                  tooltip: 'Next day',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 60),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.event_busy, size: 40, color: Colors.white24),
            SizedBox(height: 10),
            Text('No workout logged on this date',
                style: TextStyle(color: Colors.white38, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  /// One compact strip instead of the old full-width gradient card, so the
  /// exercises themselves start near the top of the screen.
  Widget _buildDaySummary() {
    final exercises = _progressData.length;
    final completed = _progressData.fold<int>(0, (s, p) => s + p.completedSets.length);
    final total = _progressData.fold<int>(0, (s, p) => s + p.totalSets);
    final pct = total > 0 ? ((completed / total) * 100).round() : 0;
    final finished = _progressData.any((p) => p.sessionFinished);
    final programName = _programNameForSelectedDate();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF2563EB), Color(0xFF9333EA)]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  programName ?? 'Workout',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              if (finished)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('FINISHED',
                      style: TextStyle(
                          color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _stat('$exercises', 'Exercises'),
              _stat('$completed/$total', 'Sets'),
              _stat('$pct%', 'Complete'),
            ],
          ),
        ],
      ),
    );
  }

  String? _programNameForSelectedDate() {
    final dateStr = _dateStrOf(_selectedDate);
    for (final program in _history) {
      for (final session in program.sessions) {
        if (session.date == dateStr) return program.programName;
      }
    }
    return null;
  }

  Widget _stat(String value, String label) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
      ],
    );
  }

  /// The heart of the tab: per exercise, one line per set showing the weight
  /// the trainee actually used, plus their note.
  Widget _buildExerciseCard(ProgressEntry entry) {
    final total = entry.totalSets;
    final completed = entry.completedSets.length;
    final allDone = total > 0 && completed == total;
    final rows = entry.exercise?.setRows ?? [];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          entry.exercise?.name ?? 'Exercise',
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                      if (entry.exercise?.eachSide == true) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                              color: const Color(0xFF3B82F6),
                              borderRadius: BorderRadius.circular(4)),
                          child: const Text('ES',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$completed/$total',
                  style: TextStyle(
                    color: allDone ? const Color(0xFF4ADE80) : const Color(0xFF60A5FA),
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF334155)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Column(
              children: List.generate(total, (idx) {
                final done = entry.completedSets.contains(idx);
                final logged = entry.weightForSet(idx);
                final planned = idx < rows.length ? rows[idx] : null;
                final isTime = planned?.type == 'time';

                // What they lifted if they logged it, otherwise the plan —
                // labelled so the two are never confused.
                final hasLogged = logged != null;
                final shown = hasLogged ? logged : planned?.weight;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 22,
                        child: Text('${idx + 1}',
                            style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 12,
                                fontWeight: FontWeight.bold)),
                      ),
                      SizedBox(
                        width: 78,
                        child: Text(
                          weightChip(shown),
                          style: TextStyle(
                            color: hasLogged ? Colors.white : Colors.white38,
                            fontSize: 14,
                            fontWeight: hasLogged ? FontWeight.bold : FontWeight.normal,
                            fontStyle: hasLogged ? FontStyle.normal : FontStyle.italic,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          planned == null
                              ? ''
                              : isTime
                                  ? '${planned.duration}s'
                                  : '× ${planned.reps} reps',
                          style: const TextStyle(color: Colors.white54, fontSize: 13),
                        ),
                      ),
                      Icon(
                        done ? Icons.check_circle : Icons.radio_button_unchecked,
                        size: 18,
                        color: done ? const Color(0xFF22C55E) : const Color(0xFF475569),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
          if (entry.hasNotes)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(14, 2, 14, 14),
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: const Color(0xFFFACC15).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFACC15).withOpacity(0.35)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.sticky_note_2_outlined,
                      size: 15, color: Color(0xFFFACC15)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      entry.notes!.trim(),
                      style: const TextStyle(
                          color: Color(0xFFFDE68A), fontSize: 13, height: 1.4),
                    ),
                  ),
                ],
              ),
            )
          else
            const SizedBox(height: 6),
        ],
      ),
    );
  }

  // ---------------- HISTORY ----------------

  Widget _buildHistorySection() {
    if (_history.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _showHistory = !_showHistory),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(Icons.history, size: 18, color: Colors.white70),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('Workout History',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                  Icon(_showHistory ? Icons.expand_less : Icons.expand_more,
                      color: Colors.white54),
                ],
              ),
            ),
          ),
          if (_showHistory)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(children: _history.map(_buildHistoryProgram).toList()),
            ),
        ],
      ),
    );
  }

  Widget _buildHistoryProgram(ProgramHistory program) {
    final expanded = _expandedProgram == program.programName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(
              () => _expandedProgram = expanded ? null : program.programName),
          child: Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
                color: const Color(0xFF334155), borderRadius: BorderRadius.circular(10)),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text('x${program.count}',
                            style: const TextStyle(
                                color: Colors.greenAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 15)),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(program.programName,
                              style: const TextStyle(
                                  color: Colors.white, fontWeight: FontWeight.w600)),
                        ),
                      ]),
                      const SizedBox(height: 2),
                      Text('Last: ${_formatDate(program.lastSession)}',
                          style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    ],
                  ),
                ),
                Icon(expanded ? Icons.expand_less : Icons.expand_more, color: Colors.white54),
              ],
            ),
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 8),
            child: Column(
              children: program.sessions.map((session) {
                final isSelected = _dateStrOf(_selectedDate) == session.date;
                return InkWell(
                  onTap: () {
                    setState(() => _selectedDate = DateTime.parse(session.date));
                    _loadProgressAndHistory();
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF2563EB) : const Color(0xFF334155),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_formatDate(session.date),
                                  style: TextStyle(
                                      color:
                                          isSelected ? Colors.white : Colors.blue.shade200,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13)),
                              Text(
                                  '${session.exercises} exercises • ${session.completionRate}% complete',
                                  style: TextStyle(
                                      color: isSelected ? Colors.white70 : Colors.white38,
                                      fontSize: 11)),
                            ],
                          ),
                        ),
                        Text('${session.completedSets}/${session.totalSets}',
                            style: TextStyle(
                                color: isSelected ? Colors.white : Colors.blue.shade200,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}
