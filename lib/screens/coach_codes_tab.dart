import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../services/admin_service.dart';
import 'coach_panel_screen.dart';

/// Admin-only: mint the codes that let a new coach unlock the coach role.
/// Trainee codes are not issued here — they are created with the trainee in
/// the Trainees tab, which is also where they are handed out.
class CoachCodesTab extends StatefulWidget {
  const CoachCodesTab({super.key});

  @override
  State<CoachCodesTab> createState() => _CoachCodesTabState();
}

class _CoachCodesTabState extends State<CoachCodesTab> {
  final _labelController = TextEditingController();
  List<CoachCode> _codes = [];
  List<Coach> _coaches = [];
  bool _loading = true;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final codes = await AdminService.loadCoachCodes();
      final coaches = await AdminService.loadCoaches();
      if (mounted) {
        setState(() {
          _codes = codes;
          _coaches = coaches;
        });
      }
    } catch (e) {
      if (mounted) showAppMessage(context, 'Failed to load coach codes', isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _removeCoach(Coach coach) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Remove this coach?', style: TextStyle(color: Colors.white)),
        content: Text(
          '${coach.displayName} loses access immediately and their code is '
          'destroyed, so it cannot be reused.\n\n'
          '${coach.traineeCount == 0 ? 'They have no trainees.' : 'Their ${coach.traineeCount} '
              '${coach.traineeCount == 1 ? 'trainee' : 'trainees'}, programs and private '
              'exercises move to you — nothing is deleted.'}\n\n'
          'Their login still works; they will land on the "coach or trainee" '
          'screen and need a new code to get back in.',
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
            child: const Text('Remove coach'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final moved = await AdminService.removeCoach(coach.id);
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      showAppMessage(
        context,
        moved.trainees + moved.programs + moved.library == 0
            ? '${coach.displayName} removed'
            : '${coach.displayName} removed — ${moved.trainees} trainees, '
                '${moved.programs} programs, ${moved.library} exercises moved to you',
      );
    } catch (e) {
      if (mounted) {
        showAppMessage(context, e.toString().replaceFirst('Exception: ', ''), isError: true);
      }
    }
  }

  Future<void> _create() async {
    setState(() => _creating = true);
    try {
      final code = await AdminService.createCoachCode(label: _labelController.text);
      _labelController.clear();
      if (!mounted) return;
      setState(() => _codes = [code, ..._codes]);
      showAppMessage(context, 'Coach code ${code.code} created');
    } catch (e) {
      if (mounted) showAppMessage(context, 'Could not create the code', isError: true);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _delete(CoachCode code) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Revoke code?', style: TextStyle(color: Colors.white)),
        content: Text(
          code.isClaimed
              ? 'This code was already used by ${code.claimedEmail ?? 'a coach'}. '
                  'Revoking it does not sign them out — it only stops it being reused.'
              : 'Delete ${code.code}? Anyone holding it will no longer be able to sign up as a coach.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Revoke', style: TextStyle(color: Color(0xFFF87171))),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final result = await AdminService.deleteCoachCode(code.code);
      if (!mounted) return;
      setState(() => _codes = _codes.where((c) => c.code != code.code).toList());
      if (result.demotedACoach) {
        await _load(); // their trainees/programs now show under Active Coaches as freed back to you
        showAppMessage(context, 'Code revoked — that coach lost access immediately');
      } else {
        showAppMessage(context, 'Code revoked');
      }
    } catch (e) {
      if (mounted) showAppMessage(context, 'Could not revoke the code', isError: true);
    }
  }

  void _copy(String code) {
    Clipboard.setData(ClipboardData(text: code));
    showAppMessage(context, 'Copied $code');
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Coach Codes',
              style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text(
            'Give one of these to a new coach. They sign up with their own email, '
            'pick "I am a Coach", and enter the code to unlock their panel.',
            style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Column(
              children: [
                TextField(
                  controller: _labelController,
                  enabled: !_creating,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: "Who is this for? (optional, e.g. 'Sara')",
                    hintStyle: TextStyle(color: Colors.white38),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _creating ? null : _create,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(_creating ? 'Creating...' : 'Generate coach code'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_codes.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text('No coach codes yet', style: TextStyle(color: Colors.white38)),
              ),
            )
          else
            ..._codes.map(_buildCodeCard),
          if (_coaches.isNotEmpty) ...[
            const SizedBox(height: 26),
            const Text('Active Coaches',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text(
              'Removing a coach revokes their access and moves their trainees to you.',
              style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            ..._coaches.map(_buildCoachCard),
          ],
        ],
      ),
    );
  }

  Widget _buildCoachCard(Coach coach) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                    color: Color(0xFF9333EA), shape: BoxShape.circle),
                child: const Icon(Icons.sports, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(coach.displayName,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(
                      '${coach.traineeCount} '
                      '${coach.traineeCount == 1 ? 'trainee' : 'trainees'}'
                      '${coach.activatedAt != null ? '  ·  since ${_fmt(coach.activatedAt!)}' : ''}',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => _removeCoach(coach),
                icon: const Icon(Icons.person_remove_outlined, size: 20),
                color: const Color(0xFFF87171),
                tooltip: 'Remove coach',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF334155),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  coach.sharesLibrary ? Icons.folder_shared_outlined : Icons.folder_off_outlined,
                  size: 16,
                  color: coach.sharesLibrary ? Colors.white70 : Colors.white38,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Default exercise library',
                    style: TextStyle(
                        color: coach.sharesLibrary ? Colors.white : Colors.white38,
                        fontSize: 13),
                  ),
                ),
                Switch(
                  value: coach.sharesLibrary,
                  onChanged: (v) => _toggleCoachLibrary(coach, v),
                  activeColor: const Color(0xFF9333EA),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Flips whether this coach can see the shared default library. Their own
  /// private exercises — anything not marked global — are never touched.
  Future<void> _toggleCoachLibrary(Coach coach, bool value) async {
    setState(() {
      _coaches = _coaches
          .map((c) => c.id == coach.id
              ? Coach(
                  id: c.id,
                  email: c.email,
                  fullName: c.fullName,
                  activatedAt: c.activatedAt,
                  traineeCount: c.traineeCount,
                  sharesLibrary: value,
                )
              : c)
          .toList();
    });
    try {
      await AdminService.setCoachLibraryAccess(coach.id, value);
      if (mounted) {
        showAppMessage(
          context,
          value
              ? '${coach.displayName} can now see the default library'
              : '${coach.displayName} no longer sees the default library',
        );
      }
    } catch (e) {
      // Roll back the optimistic flip if the write failed.
      if (!mounted) return;
      setState(() {
        _coaches = _coaches
            .map((c) => c.id == coach.id
                ? Coach(
                    id: c.id,
                    email: c.email,
                    fullName: c.fullName,
                    activatedAt: c.activatedAt,
                    traineeCount: c.traineeCount,
                    sharesLibrary: !value,
                  )
                : c)
            .toList();
      });
      showAppMessage(context, 'Could not update library access', isError: true);
    }
  }

  Widget _buildCodeCard(CoachCode code) {
    final claimed = code.isClaimed;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: claimed ? const Color(0xFF16A34A).withOpacity(0.5) : const Color(0xFF334155),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      code.code,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: claimed ? const Color(0xFF16A34A) : const Color(0xFF475569),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        claimed ? 'USED' : 'AVAILABLE',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  claimed
                      ? '${code.claimedEmail ?? 'Claimed'}${code.claimedAt != null ? ' · ${_fmt(code.claimedAt!)}' : ''}'
                      : (code.label ?? 'Not used yet'),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          if (!claimed)
            IconButton(
              onPressed: () => _copy(code.code),
              icon: const Icon(Icons.copy, color: Colors.white54, size: 20),
              tooltip: 'Copy',
            ),
          IconButton(
            onPressed: () => _delete(code),
            icon: const Icon(Icons.delete_outline, color: Color(0xFFF87171), size: 20),
            tooltip: 'Revoke',
          ),
        ],
      ),
    );
  }

  String _fmt(String iso) {
    try {
      return DateFormat('MMM d, yyyy').format(DateTime.parse(iso).toLocal());
    } catch (_) {
      return iso;
    }
  }
}
