import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/workout.dart';
import '../utils/format.dart';
import '../models/trainee_program_data.dart';
import '../services/trainee_service.dart';
import '../services/local_storage.dart';
import '../services/audio_service.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../widgets/celebration_dialog.dart';
import '../widgets/exercise_panel.dart';
import '../widgets/rest_timer_bar.dart';
import '../widgets/video_modal.dart';

class TraineeWorkoutScreen extends StatefulWidget {
  final String traineeCode;
  final String traineeName;

  /// A coach looking at a trainee's programme. Nothing is written back — the
  /// sets they tick are the trainee's record, not theirs.
  final bool isPreview;

  /// Leaves preview and returns to the role screen.
  final VoidCallback? onExitPreview;

  const TraineeWorkoutScreen({
    super.key,
    required this.traineeCode,
    required this.traineeName,
    this.isPreview = false,
    this.onExitPreview,
  });

  @override
  State<TraineeWorkoutScreen> createState() => _TraineeWorkoutScreenState();
}

class _TraineeWorkoutScreenState extends State<TraineeWorkoutScreen> {
  bool _loading = true;
  String? _programId;
  String _programName = '';
  List<Workout> _workouts = [];
  int _currentPage = 0;

  final Map<String, List<dynamic>> _setWeights = {}; // exerciseId -> weights
  final Map<String, List<dynamic>> _lastWeights = {};

  // key: "exerciseId-setIdx"
  final Map<String, SetTimerState> _setTimers = {};
  final Map<String, Timer> _setTimerTickers = {};

  // Global rest timer (per exercise or per group)
  String? _activeTimerKey;
  int _timerSeconds = 0;
  Timer? _restTimerTicker;

  Timer? _autoRefreshTimer;

  /// Whether today's session has already been closed out with "Save & Done".
  bool _sessionFinished = false;
  bool _saving = false;

  // Where the trainee sits in the coach's block. Derived server-side from
  // finished sessions; the trainee cannot change any of it.
  int _dayIndex = 0;
  int _dayCount = 1;
  int _currentLoop = 1;
  int? _loopTarget;
  int _sessionSeq = 0;

  /// Set once every loop is done — the workout is replaced by a locked card.
  BlockCompleteData? _blockComplete;

  /// Typing a weight fires on every keystroke; collapse the writes so a
  /// three-character entry is one round trip instead of three.
  final Map<String, Timer> _saveDebounce = {};
  static const _saveDelay = Duration(milliseconds: 600);

  @override
  void initState() {
    super.initState();
    _resumePersistedRestTimer();
    _loadProgram();
  }

  @override
  void dispose() {
    _restTimerTicker?.cancel();
    _autoRefreshTimer?.cancel();
    for (final t in _setTimerTickers.values) {
      t.cancel();
    }
    for (final t in _saveDebounce.values) {
      t.cancel();
    }
    super.dispose();
  }

  void _resumePersistedRestTimer() {
    final endTime = LocalStorage.restTimerEndTime;
    final workoutId = LocalStorage.restTimerWorkoutId;
    if (endTime != null && workoutId != null) {
      final remaining = ((endTime - DateTime.now().millisecondsSinceEpoch) / 1000).round();
      if (remaining > 0) {
        _activeTimerKey = workoutId;
        _timerSeconds = remaining;
        _startRestTicker();
      } else {
        LocalStorage.clearRestTimer();
      }
    }
  }

  // ---------------- LOADING ----------------

  Future<void> _loadProgram({String? overrideProgramId}) async {
    setState(() => _loading = true);
    try {
      // Checked before anything loads: once the block is done there is no
      // current program to show.
      final finished = await TraineeService.checkBlockComplete(widget.traineeCode);
      if (finished != null) {
        _autoRefreshTimer?.cancel();
        if (mounted) {
          setState(() {
            _blockComplete = finished;
            _workouts = [];
            _programId = null;
          });
        }
        return;
      }

      final data = await TraineeService.loadTraineeProgram(widget.traineeCode, overrideProgramId: overrideProgramId);
      if (data == null) {
        setState(() => _loading = false);
        return;
      }
      setState(() {
        _blockComplete = null;
        _programId = data.programId;
        _programName = data.programName;
        _workouts = data.workouts;
        _dayIndex = data.dayIndex;
        _dayCount = data.dayCount;
        _currentLoop = data.currentLoop;
        _loopTarget = data.loopTarget;
        _sessionSeq = data.sessionSeq;
        _currentPage = 0;
      });
      await _loadProgress();
      _startAutoRefresh();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }


  Future<void> _loadProgress() async {
    if (_programId == null) return;
    final result = await TraineeService.loadProgress(widget.traineeCode, _programId!, _sessionSeq);
    if (!mounted) return;
    setState(() {
      _sessionFinished = result.sessionFinished;
      _setWeights
        ..clear()
        ..addAll(result.setWeights);
      _lastWeights
        ..clear()
        ..addAll(result.lastWeights);
      for (final w in _workouts) {
        if (result.completedSets.containsKey(w.id)) {
          w.completedSets = result.completedSets[w.id]!;
        }
        if (result.notes.containsKey(w.id)) {
          w.notes = result.notes[w.id]!;
        }
      }
    });
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      // Don't pull server state over edits that have not been written yet.
      if (_saveDebounce.isNotEmpty) return;
      _loadProgress();
    });
  }

  // ---------------- PROGRESS SAVE ----------------

  Future<void> _persistProgress(Workout w) async {
    if (_programId == null || widget.isPreview) return;
    await TraineeService.saveProgress(
      code: widget.traineeCode,
      programId: _programId!,
      exerciseId: w.id,
      completedSets: w.completedSets,
      notes: w.notes,
      weights: _setWeights[w.id] ?? [],
      sessionSeq: _sessionSeq,
    );
  }

  /// Same save, delayed and coalesced — for the fields that change on every
  /// keystroke. Ticking a set still writes immediately.
  void _persistProgressDebounced(Workout w) {
    _saveDebounce[w.id]?.cancel();
    _saveDebounce[w.id] = Timer(_saveDelay, () {
      _saveDebounce.remove(w.id);
      _persistProgress(w);
    });
  }

  /// Flushes anything still waiting on its debounce timer.
  Future<void> _flushPendingSaves() async {
    final pending = _saveDebounce.keys.toList();
    for (final t in _saveDebounce.values) {
      t.cancel();
    }
    _saveDebounce.clear();
    for (final id in pending) {
      final matches = _workouts.where((x) => x.id == id);
      if (matches.isNotEmpty) await _persistProgress(matches.first);
    }
  }

  void _updateSetWeight(String workoutId, int setIdx, String value) {
    // Keep '' for a cleared box so it reads as "not recorded" rather than 0 kg.
    final parsed = parseWeight(value) ?? '';
    setState(() {
      final list = List<dynamic>.from(_setWeights[workoutId] ?? []);
      while (list.length <= setIdx) {
        list.add('');
      }
      list[setIdx] = parsed;
      _setWeights[workoutId] = list;

      final lastList = List<dynamic>.from(_lastWeights[workoutId] ?? []);
      while (lastList.length <= setIdx) {
        lastList.add('');
      }
      lastList[setIdx] = parsed;
      _lastWeights[workoutId] = lastList;
    });
    final workout = _workouts.firstWhere((w) => w.id == workoutId);
    _persistProgressDebounced(workout);
  }

  void _toggleSetComplete(String workoutId, int setIdx) {
    final workout = _workouts.firstWhere((w) => w.id == workoutId);
    setState(() {
      final completed = List<int>.from(workout.completedSets);
      if (completed.contains(setIdx)) {
        completed.remove(setIdx);
      } else {
        completed.add(setIdx);
      }
      workout.completedSets = completed;
    });
    _persistProgress(workout);
  }

  void _updateNotes(String workoutId, String notes) {
    final workout = _workouts.firstWhere((w) => w.id == workoutId);
    workout.notes = notes;
    _persistProgressDebounced(workout);
  }

  void _resetWorkout(String workoutId) {
    final workout = _workouts.firstWhere((w) => w.id == workoutId);
    setState(() {
      workout.completedSets = [];
      _setWeights[workoutId] = [];
    });
    _persistProgress(workout);
  }

  // ---------------- PER-SET TIMERS ----------------

  void _startSetTimer(String workoutId, int setIdx, int duration, String exerciseName) {
    NotificationService.schedule(
      duration,
      title: '⏱ Set Time Over!',
      body: 'The set time of "$exerciseName" is finished',
      alert: TimerAlert.set,
    );
    final key = '$workoutId-$setIdx';
    _setTimerTickers[key]?.cancel();
    setState(() => _setTimers[key] = SetTimerState(seconds: duration, running: true));
    _setTimerTickers[key] = Timer.periodic(const Duration(seconds: 1), (_) {
      final current = _setTimers[key];
      if (current == null || current.seconds <= 1) {
        _setTimerTickers[key]?.cancel();
        _setTimerTickers.remove(key);
        AudioService.playSetOverSound();
        setState(() => _setTimers[key] = SetTimerState(seconds: 0, running: false));
        _toggleSetComplete(workoutId, setIdx);
        return;
      }
      setState(() => _setTimers[key] = SetTimerState(seconds: current.seconds - 1, running: true));
    });
  }

  void _stopSetTimer(String workoutId, int setIdx) {
    NotificationService.cancel();
    final key = '$workoutId-$setIdx';
    _setTimerTickers[key]?.cancel();
    _setTimerTickers.remove(key);
    setState(() {
      final current = _setTimers[key];
      if (current != null) _setTimers[key] = SetTimerState(seconds: current.seconds, running: false);
    });
  }

  void _resetSetTimer(String workoutId, int setIdx, int duration) {
    NotificationService.cancel();
    final key = '$workoutId-$setIdx';
    _setTimerTickers[key]?.cancel();
    _setTimerTickers.remove(key);
    setState(() => _setTimers[key] = SetTimerState(seconds: duration, running: false));
  }

  // ---------------- GLOBAL REST TIMER ----------------

  void _startRestTimer(String key, int restTime) {
    final endTime = DateTime.now().millisecondsSinceEpoch + restTime * 1000;
    LocalStorage.setRestTimer(endTime, key);
    setState(() {
      _activeTimerKey = key;
      _timerSeconds = restTime;
    });
    NotificationService.schedule(
      restTime,
      title: '⏱ Rest Over!',
      body: 'Rest time is finished',
      alert: TimerAlert.rest,
    );
    _startRestTicker();
  }

  void _startRestTicker() {
    _restTimerTicker?.cancel();
    _restTimerTicker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final endTime = LocalStorage.restTimerEndTime;
      if (endTime == null) {
        _restTimerTicker?.cancel();
        setState(() {});
        return;
      }
      final remaining = ((endTime - DateTime.now().millisecondsSinceEpoch) / 1000).round();
      if (remaining <= 0) {
        _restTimerTicker?.cancel();
        LocalStorage.clearRestTimer();
        AudioService.playRestOverSound();
        setState(() {
          _activeTimerKey = null;
          _timerSeconds = 0;
        });
      } else {
        setState(() => _timerSeconds = remaining);
      }
    });
  }

  void _pauseTimer() {
    _restTimerTicker?.cancel();
    LocalStorage.clearRestTimer();
    NotificationService.cancel();
    setState(() {});
  }

  void _resetTimer() {
    _restTimerTicker?.cancel();
    LocalStorage.clearRestTimer();
    NotificationService.cancel();
    setState(() {
      _activeTimerKey = null;
      _timerSeconds = 0;
    });
  }

  // ---------------- DONE / LOGOUT ----------------

  /// Closes out the session. Works from any page and at any completion level —
  /// a half-finished workout is still worth recording, so an incomplete one
  /// only asks for a confirmation rather than blocking.
  Future<void> _handleWorkoutDone() async {
    if (_saving || _programId == null || widget.isPreview) return;

    final done = _completedTotal;
    final total = _totalSets;

    if (done < total) {
      final proceed = await _confirmPartialSave(done, total);
      if (proceed != true) return;
    }

    setState(() => _saving = true);
    try {
      // Any keystroke still sitting on its debounce timer must land first,
      // otherwise the finalize below would overwrite it with stale values.
      await _flushPendingSaves();

      final snapshot = <String, List<dynamic>>{};
      for (final w in _workouts) {
        final weights = _setWeights[w.id];
        if (weights != null && weights.any((x) => x != '' && x != null)) {
          snapshot[w.id] = weights;
        }
      }

      await TraineeService.finalizeWorkout(
        code: widget.traineeCode,
        programId: _programId!,
        workouts: _workouts,
        snapshotWeights: snapshot,
        sessionSeq: _sessionSeq,
      );

      if (!mounted) return;
      setState(() {
        _lastWeights
          ..clear()
          ..addAll(snapshot);
        _sessionFinished = true;
      });

      final finishedName = _programName;

      await CelebrationDialog.show(
        context,
        programName: finishedName,
        completedSets: done,
        totalSets: total,
      );

      if (!mounted) return;
      // Reload rather than stepping the rotation by hand: the session just
      // written moves the position, and this is also what surfaces the
      // block-complete screen when that was the final loop.
      await _loadProgram();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save your workout. Check your connection and try again.'),
          backgroundColor: Color(0xFFE52222),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool?> _confirmPartialSave(int done, int total) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Finish here?', style: TextStyle(color: Colors.white)),
        content: Text(
          done == 0
              ? 'You have not logged any sets yet. Save this session anyway?'
              : "You've done $done of $total sets. Everything you logged will be saved "
                  'and your coach will see it. You can always come back later today.',
          style: const TextStyle(color: Colors.white70, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep going', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF16A34A)),
            child: const Text('Save & finish'),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    await _flushPendingSaves();
    await LocalStorage.clearTraineeSession();
    await AuthService.signOut();
  }

  void _openVideo(String url, String name) => VideoModal.show(context, url, name);

  // ---------------- DERIVED ----------------

  int get _totalSets => _workouts.fold(0, (sum, w) => sum + w.sets);
  int get _completedTotal => _workouts.fold(0, (sum, w) => sum + w.completedSets.length);
  double get _progressPct => _totalSets > 0 ? (_completedTotal / _totalSets) * 100 : 0;

  List<WorkoutPage> get _pages => buildWorkoutPages(_workouts);

  Color _groupColor(String? type) {
    switch (type) {
      case 'superset':
        return const Color(0xFFEA580C);
      case 'triset':
        return const Color(0xFF9333EA);
      case 'circuit':
        return const Color(0xFF16A34A);
      default:
        return const Color(0xFF2563EB);
    }
  }

  String _groupLabel(String? type) {
    switch (type) {
      case 'superset':
        return 'SUPERSET';
      case 'triset':
        return 'TRISET';
      case 'circuit':
        return 'CIRCUIT';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _workouts.isEmpty && _blockComplete == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_blockComplete != null) return _buildBlockComplete(_blockComplete!);

    final pages = _pages;
    final page = pages.isNotEmpty && _currentPage < pages.length ? pages[_currentPage] : null;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (widget.isPreview) _buildPreviewBanner(),
            _buildHeader(),
            const SizedBox(height: 16),
            if (pages.length > 1) _buildPageDots(pages),
            if (page != null) _buildPage(page),
            const SizedBox(height: 16),
            _buildNav(pages),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final dateStr = DateFormat('EEEE, MMMM d, yyyy').format(DateTime.now());
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF2563EB), Color(0xFF9333EA)]),
        borderRadius: BorderRadius.circular(20),
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
                    Text(_programName, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(dateStr, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 4),
                    Row(children: [
                      const Icon(Icons.person, size: 14, color: Colors.white70),
                      const SizedBox(width: 6),
                      Text(widget.traineeName, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    ]),
                  ],
                ),
              ),
              IconButton(
                onPressed: _logout,
                icon: const Icon(Icons.logout, color: Colors.white),
                tooltip: 'Sign out',
                style: IconButton.styleFrom(backgroundColor: Colors.white24),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildPositionChip(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Progress', style: TextStyle(color: Colors.white, fontSize: 13)),
              Text('$_completedTotal/$_totalSets sets', style: const TextStyle(color: Colors.white, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(value: _progressPct / 100, minHeight: 10, backgroundColor: Colors.white24, color: Colors.white),
          ),
        ],
      ),
    );
  }

  /// Shown in place of the workout once every loop is finished. There is no way
  /// past it from here on purpose: the coach decides what comes next, and this
  /// is the moment programming should be reviewed.
  Widget _buildBlockComplete(BlockCompleteData data) {
    final sessions = data.loopsDone * data.dayCount;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420),
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFF22C55E), width: 1.5),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Color(0xFF16A34A), Color(0xFF059669)],
                      ),
                    ),
                    child: const Icon(Icons.emoji_events, color: Colors.white, size: 46),
                  ),
                  const SizedBox(height: 20),
                  const Text('Block complete!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Text(
                    'You finished all ${data.loopTarget} '
                    '${data.loopTarget == 1 ? 'loop' : 'loops'} of your program — '
                    '$sessions ${sessions == 1 ? 'session' : 'sessions'} done.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 15, height: 1.5),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF334155),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, color: Color(0xFF60A5FA), size: 18),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Your coach will set your next block. '
                            'Check back once they have updated your program.',
                            style: TextStyle(
                                color: Colors.white70, fontSize: 13, height: 1.45),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: () => _loadProgram(),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Check again'),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: _logout,
                    child: const Text('Sign out',
                        style: TextStyle(color: Colors.white54, fontSize: 13)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Where the trainee is in the block. Replaces the old program switcher —
  /// the day is decided by how many sessions they have finished, so this is
  /// information, not a control.
  /// Makes it unmistakable that this is the trainee's programme being looked
  /// at, not the coach's own workout — nothing here is recorded.
  Widget _buildPreviewBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFACC15).withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFACC15).withOpacity(0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.visibility_outlined, size: 18, color: Color(0xFFFACC15)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "Previewing ${widget.traineeName}'s programme — nothing is saved",
              style: const TextStyle(
                  color: Color(0xFFFDE68A), fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          if (widget.onExitPreview != null)
            TextButton(
              onPressed: widget.onExitPreview,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Exit', style: TextStyle(fontSize: 13)),
            ),
        ],
      ),
    );
  }

  Widget _buildPositionChip() {
    if (_dayCount < 2 && _loopTarget == null) return const SizedBox.shrink();

    final parts = <String>[];
    if (_dayCount > 1) parts.add('Day ${_dayIndex + 1} of $_dayCount');
    if (_loopTarget != null) parts.add('Loop $_currentLoop of $_loopTarget');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
          color: Colors.white24, borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.calendar_today, size: 13, color: Colors.white70),
          const SizedBox(width: 6),
          Text(parts.join('  ·  '),
              style: const TextStyle(
                  color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildPageDots(List<WorkoutPage> pages) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: List.generate(pages.length, (idx) {
          final isDone = pages[idx].isComplete;
          final isCurrent = idx == _currentPage;
          return GestureDetector(
            onTap: () => setState(() => _currentPage = idx),
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isCurrent ? const Color(0xFF3B82F6) : (isDone ? const Color(0xFF22C55E) : const Color(0xFF334155)),
                shape: BoxShape.circle,
              ),
              child: Text(isDone ? '✓' : '${idx + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildPage(WorkoutPage page) {
    if (page.isGroup) {
      return _buildGroupPage(page);
    }
    return _buildSingleCard(page.single!);
  }

  Widget _buildSingleCard(Workout workout) {
    final isComplete = workout.completedSets.length == workout.sets;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isComplete ? const Color(0xFF22C55E) : const Color(0xFF334155), width: isComplete ? 1.5 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExercisePanel(
            // Keyed per exercise so paging does not hand one exercise's text
            // controllers to the next one.
            key: ValueKey(workout.id),
            workout: workout,
            weights: _setWeights[workout.id] ?? [],
            setTimers: _setTimersFor(workout.id, workout.setRows.length),
            onWeightChange: (idx, v) => _updateSetWeight(workout.id, idx, v),
            onToggleComplete: (idx) => _toggleSetComplete(workout.id, idx),
            onStartSetTimer: (idx, dur) => _startSetTimer(workout.id, idx, dur, workout.name),
            onStopSetTimer: (idx) => _stopSetTimer(workout.id, idx),
            onResetSetTimer: (idx, dur) => _resetSetTimer(workout.id, idx, dur),
            onNotesChange: (v) => _updateNotes(workout.id, v),
            onWatchVideo: workout.videoUrl != null ? () => _openVideo(workout.videoUrl!, workout.name) : null,
          ),
          if (workout.coachNotes != null && workout.coachNotes!.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFACC15).withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFACC15).withOpacity(0.4)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, size: 16, color: Color(0xFFFACC15)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      workout.coachNotes!,
                      style: const TextStyle(color: Color(0xFFFDE68A), fontSize: 13, fontStyle: FontStyle.italic),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          RestTimerBar(
            isActive: _activeTimerKey == workout.id,
            secondsRemaining: _timerSeconds,
            totalSeconds: workout.restTime,
            label: workout.name,
            onStart: () => _startRestTimer(workout.id, workout.restTime),
            onPause: _pauseTimer,
            onReset: () => workout.completedSets.isNotEmpty ? _resetWorkout(workout.id) : _resetTimer(),
            showResetWhenIdle: workout.completedSets.isNotEmpty,
          ),
        ],
      ),
    );
  }

  Widget _buildGroupPage(WorkoutPage page) {
    final members = page.group!;
    final color = _groupColor(page.groupType);
    final label = _groupLabel(page.groupType);
    final groupName = members.first.groupName;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14)),
          child: Row(
            children: [
              const Icon(Icons.link, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  groupName != null ? '$groupName (${label.toLowerCase()})' : label,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
              Text('${members.length} exercises', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        ...members.asMap().entries.map((entry) {
          final idx = entry.key;
          final w = entry.value;
          return Container(
            margin: const EdgeInsets.only(bottom: 10, left: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(16),
              border: Border(left: BorderSide(color: color, width: 3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExercisePanel(
                  key: ValueKey(w.id),
                  workout: w,
                  weights: _setWeights[w.id] ?? [],
                  setTimers: _setTimersFor(w.id, w.setRows.length),
                  onWeightChange: (i, v) => _updateSetWeight(w.id, i, v),
                  onToggleComplete: (i) => _toggleSetComplete(w.id, i),
                  onStartSetTimer: (i, dur) => _startSetTimer(w.id, i, dur, w.name),
                  onStopSetTimer: (i) => _stopSetTimer(w.id, i),
                  onResetSetTimer: (i, dur) => _resetSetTimer(w.id, i, dur),
                  onNotesChange: (v) => _updateNotes(w.id, v),
                  onWatchVideo: w.videoUrl != null ? () => _openVideo(w.videoUrl!, w.name) : null,
                  badgeColor: color,
                  badgeNumber: idx + 1,
                  compact: true,
                ),
                if (w.coachNotes != null && w.coachNotes!.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFACC15).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFACC15).withOpacity(0.4)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline, size: 14, color: Color(0xFFFACC15)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            w.coachNotes!,
                            style: const TextStyle(color: Color(0xFFFDE68A), fontSize: 12, fontStyle: FontStyle.italic),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
        }),
        const SizedBox(height: 4),
        _buildGroupRestTimer(page),
      ],
    );
  }

  /// Rest for a superset / triset / circuit is taken once, after the whole
  /// round — so the group gets a single timer rather than one per exercise.
  Widget _buildGroupRestTimer(WorkoutPage page) {
    final members = page.group!;
    // Coaches set the round's rest on whichever exercise they think of as the
    // end of it, leaving the others at 0, so take the longest rather than the
    // first — otherwise the timer reads 0s for most groups.
    final longest = members.map((w) => w.restTime).fold<int>(0, (a, b) => a > b ? a : b);
    // Every member left at 0 would render a "0s" button that fires instantly;
    // fall back to the same default a single exercise gets.
    final restTime = longest > 0 ? longest : 60;
    final key = 'group-${page.groupId}';
    final anyCompleted = members.any((w) => w.completedSets.isNotEmpty);

    return RestTimerBar(
      isActive: _activeTimerKey == key,
      secondsRemaining: _timerSeconds,
      totalSeconds: restTime,
      label: members.first.groupName ?? _groupLabel(page.groupType),
      onStart: () => _startRestTimer(key, restTime),
      onPause: _pauseTimer,
      onReset: () => anyCompleted ? _resetGroup(members) : _resetTimer(),
      showResetWhenIdle: anyCompleted,
    );
  }

  /// Clears every exercise in the group in one go, matching what the reset
  /// button does for a single exercise.
  void _resetGroup(List<Workout> members) {
    setState(() {
      for (final w in members) {
        w.completedSets = [];
        _setWeights[w.id] = [];
      }
    });
    for (final w in members) {
      _persistProgress(w);
    }
  }

  Map<int, SetTimerState> _setTimersFor(String workoutId, int setCount) {
    final map = <int, SetTimerState>{};
    for (var i = 0; i < setCount; i++) {
      final t = _setTimers['$workoutId-$i'];
      if (t != null) map[i] = t;
    }
    return map;
  }

  Widget _buildNav(List<WorkoutPage> pages) {
    final isLastPage = _currentPage >= pages.length - 1;
    final complete = _progressPct == 100;

    return Column(
      children: [
        Row(
          children: [
            if (_currentPage > 0)
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => _currentPage -= 1),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: const Text('← Prev',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            if (_currentPage > 0 && !isLastPage) const SizedBox(width: 12),
            if (!isLastPage)
              Expanded(
                child: ElevatedButton(
                  onPressed: () => setState(() => _currentPage += 1),
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: const Text('Next →',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        // Always available, on every page: a trainee who has to cut a session
        // short should not have to page to the end to record what they did.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: complete
                  ? [const Color(0xFF16A34A), const Color(0xFF059669)]
                  : [const Color(0xFF334155), const Color(0xFF475569)],
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: [
              Text(
                _sessionFinished
                    ? '✓ Saved for today — you can keep adding'
                    : complete
                        ? '🎉 Workout Complete!'
                        : 'Done for today? Save whatever you did',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text('$_completedTotal of $_totalSets sets logged',
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _handleWorkoutDone,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor:
                        complete ? const Color(0xFF15803D) : const Color(0xFF334155),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Color(0xFF334155)),
                        )
                      : Text(_sessionFinished ? '✓ Save again' : '✓ Save & Done',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}