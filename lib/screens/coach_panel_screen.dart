import 'package:flutter/material.dart';
import '../models/app_profile.dart';
import '../services/auth_service.dart';
import 'trainees_tab.dart';
import 'programs_tab.dart';
import 'progress_tab.dart';
import 'exercise_library_screen.dart';
import 'coach_codes_tab.dart';
import 'auth/role_choice_screen.dart';

void showAppMessage(BuildContext context, String text, {bool isError = false}) {
  ScaffoldMessenger.of(context).clearSnackBars();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(text),
      backgroundColor:
          isError ? const Color(0xFFE52222) : const Color(0xFF27CE6F),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
    ),
  );
}

/// The coaching workspace. Admins get the same tabs plus Codes — everything a
/// coach sees here is already scoped to their own rows by RLS, so the admin
/// simply sees more of it.
class CoachPanelScreen extends StatefulWidget {
  final AppProfile profile;

  /// Lets a coach swap this session into a trainee's programme to look at it.
  final ValueChanged<SessionAccess> onOpenTraineeView;

  const CoachPanelScreen({
    super.key,
    required this.profile,
    required this.onOpenTraineeView,
  });

  @override
  State<CoachPanelScreen> createState() => _CoachPanelScreenState();
}

class _CoachPanelScreenState extends State<CoachPanelScreen> {
  int _tabIndex = 0;

  bool get _isAdmin => widget.profile.isAdmin;

  Future<void> _confirmSignOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Sign out?', style: TextStyle(color: Colors.white)),
        content: Text(
          'You will need your password and a new email code to get back in.\n\n${widget.profile.email}',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign out', style: TextStyle(color: Color(0xFFF87171))),
          ),
        ],
      ),
    );
    if (confirm == true) await AuthService.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = <Widget>[
      const TraineesTab(),
      const ProgramsTab(),
      ExerciseLibraryScreen(isAdmin: _isAdmin),
      const ProgressTab(),
      if (_isAdmin) const CoachCodesTab(),
    ];

    final destinations = <NavigationDestination>[
      const NavigationDestination(
          icon: Icon(Icons.groups_outlined),
          selectedIcon: Icon(Icons.groups),
          label: 'Trainees'),
      const NavigationDestination(
          icon: Icon(Icons.fitness_center_outlined),
          selectedIcon: Icon(Icons.fitness_center),
          label: 'Programs'),
      const NavigationDestination(
          icon: Icon(Icons.list_alt_outlined),
          selectedIcon: Icon(Icons.list_alt),
          label: 'Exercises'),
      const NavigationDestination(
          icon: Icon(Icons.show_chart_outlined),
          selectedIcon: Icon(Icons.show_chart),
          label: 'Progress'),
      if (_isAdmin)
        const NavigationDestination(
            icon: Icon(Icons.key_outlined), selectedIcon: Icon(Icons.key), label: 'Codes'),
    ];

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_isAdmin ? 'Admin Panel' : 'Coach Panel',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text(
              widget.profile.fullName?.trim().isNotEmpty == true
                  ? widget.profile.fullName!
                  : widget.profile.email,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            color: const Color(0xFF334155),
            onSelected: (v) {
              if (v == 'role') {
                RoleChoiceScreen.open(context,
                    onActivated: widget.onOpenTraineeView);
              }
              if (v == 'signout') _confirmSignOut();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'role',
                child: Text('Open a trainee programme',
                    style: TextStyle(color: Colors.white)),
              ),
              PopupMenuItem(
                value: 'signout',
                child: Text('Sign out', style: TextStyle(color: Color(0xFFF87171))),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: IndexedStack(index: _tabIndex, children: tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        backgroundColor: const Color(0xFF1E293B),
        destinations: destinations,
      ),
    );
  }
}
