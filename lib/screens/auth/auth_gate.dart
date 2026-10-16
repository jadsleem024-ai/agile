import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/app_profile.dart';
import '../../services/auth_service.dart';
import '../../services/notification_service.dart';
import '../../services/push_service.dart';
import '../admin_home_screen.dart';
import '../coach_panel_screen.dart';
import '../trainee_workout_screen.dart';
import 'auth_scaffold.dart';
import 'login_screen.dart';
import 'role_choice_screen.dart';

/// Single source of truth for what the app shows. It watches the Supabase auth
/// stream, resolves the account's role, and renders the matching home screen —
/// so signing in or out anywhere lands the user in the right place without
/// every screen having to push routes itself.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  /// Re-reads the signed-in account's role. Call after redeeming a code from a
  /// screen pushed above the gate — that does not fire an auth event, so the
  /// gate has no other way to notice.
  static Future<void> refreshRole() =>
      _AuthGateState._current?._resolve() ?? Future.value();

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  StreamSubscription<AuthState>? _sub;
  AppProfile? _profile;

  /// Access for this launch only. Null means the code has not been entered yet,
  /// which is the state every non-admin starts in.
  SessionAccess? _access;

  /// What the session was before swapping into a trainee preview, so leaving
  /// the preview returns the coach to their panel instead of demanding their
  /// code again mid-session.
  SessionAccess? _accessBeforePreview;

  bool _resolving = true;
  String? _error;

  /// Shown once on the role screen after a live check kicks someone out —
  /// otherwise being bounced back with no explanation looks like a bug.
  String? _revokedMessage;

  Timer? _liveCheckTimer;

  /// How often an open session is re-checked against the server. Matches the
  /// cadence already used for the trainee progress poll, so a revoked code or
  /// removed coach takes effect while the app is open, not only when it is
  /// restarted from a cold start.
  static const _liveCheckInterval = Duration(seconds: 20);

  /// Set so the public AuthGate.refreshRole() can reach the live state.
  static _AuthGateState? _current;

  @override
  void initState() {
    super.initState();
    _current = this;
    WidgetsBinding.instance.addObserver(this);
    _resolve();
    _sub = AuthService.onAuthStateChange.listen((state) {
      // Token refreshes fire constantly and never change the role.
      if (state.event == AuthChangeEvent.tokenRefreshed) return;
      _resolve();
    });
    _liveCheckTimer = Timer.periodic(_liveCheckInterval, (_) => _checkAccessStillValid());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Catches the common case immediately: admin revokes something, coach
    // switches back to the app a few seconds later — no need to wait for the
    // next periodic tick.
    if (state == AppLifecycleState.resumed) _checkAccessStillValid();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _liveCheckTimer?.cancel();
    if (identical(_current, this)) _current = null;
    _sub?.cancel();
    super.dispose();
  }

  /// Re-confirms the code/account behind the current session is still valid.
  /// This is what makes revoking a coach code or removing a coach take effect
  /// live: `_access` was previously granted once and then trusted forever —
  /// nothing re-read it until the app process restarted, so a revoked coach
  /// could keep working until they force-closed the app from Recents.
  Future<void> _checkAccessStillValid() async {
    final access = _access;
    if (access == null || !AuthService.isSignedIn) return;

    AppProfile? fresh;
    try {
      fresh = await AuthService.loadProfile();
    } catch (_) {
      return; // a dropped connection should not be mistaken for revocation
    }
    if (!mounted || fresh == null) return;

    String? kicked;
    switch (access.role) {
      case AppRole.coach:
        if (fresh.role != AppRole.coach) {
          kicked = 'Your coach access was removed by the admin.';
        }
        break;

      case AppRole.trainee:
        if (access.preview) {
          // Previewing a trainee — it is the previewer's own coach/admin
          // standing that matters here, not the trainee's.
          if (!fresh.canCoach) kicked = 'Your coach access was removed.';
        } else if (fresh.role != AppRole.trainee || fresh.traineeCode != access.traineeCode) {
          kicked = 'This code is no longer linked to your account.';
        }
        break;

      case AppRole.admin:
      case AppRole.pending:
        break;
    }

    setState(() {
      _profile = fresh!;
      if (kicked != null) {
        _access = null;
        _accessBeforePreview = null;
        _revokedMessage = kicked;
      }
    });
  }

  void _grantAccess(SessionAccess granted) {
    setState(() {
      _access = granted;
      _revokedMessage = null;
    });
  }

  Future<void> _resolve() async {
    if (!AuthService.isSignedIn) {
      if (mounted) {
        setState(() {
          _profile = null;
          _resolving = false;
          _error = null;
        });
      }
      return;
    }

    setState(() {
      _resolving = true;
      _error = null;
    });
    try {
      final profile = await AuthService.loadProfile();
      if (!mounted) return;
      setState(() => _profile = profile);
      if (profile != null && profile.role != AppRole.pending) {
        NotificationService.requestPermission();
        // Only a coach (or the admin) is ever the target of a push — a
        // trainee's device never needs a registered token.
        if (profile.canCoach) PushService.register();
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load your account. Check your connection.');
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  void _enterPreview(SessionAccess granted) {
    setState(() {
      _accessBeforePreview = granted.preview ? _access : null;
      _access = granted;
      _revokedMessage = null;
    });
  }

  void _exitPreview() {
    setState(() {
      _access = _accessBeforePreview;
      _accessBeforePreview = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_resolving) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return AuthScaffold(
        title: 'Something went wrong',
        subtitle: _error!,
        children: [
          SizedBox(
            height: 52,
            child: ElevatedButton(onPressed: _resolve, child: const Text('Try again')),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: () => AuthService.signOut(),
              child: const Text('Sign out', style: TextStyle(color: Colors.white54)),
            ),
          ),
        ],
      );
    }

    final profile = _profile;
    if (profile == null) return const LoginScreen();

    // The admin owns the whole system and holds no code, so there is nothing
    // for them to redeem — everyone else proves access on every launch.
    if (profile.isAdmin && _access == null) {
      return AdminHomeScreen(
        profile: profile,
        onOpenTraineeView: _enterPreview,
      );
    }

    final access = _access;
    if (access == null) {
      return RoleChoiceScreen(
        onActivated: _grantAccess,
        revokedMessage: _revokedMessage,
      );
    }

    switch (access.role) {
      case AppRole.coach:
        return CoachPanelScreen(
          profile: profile,
          onOpenTraineeView: _enterPreview,
        );

      case AppRole.trainee:
        if (access.traineeCode == null || access.traineeName == null) {
          return _orphanedTrainee();
        }
        return TraineeWorkoutScreen(
          key: ValueKey('${access.traineeCode}-${access.preview}'),
          traineeCode: access.traineeCode!,
          traineeName: access.traineeName!,
          isPreview: access.preview,
          onExitPreview: access.preview ? _exitPreview : null,
        );

      case AppRole.admin:
        return AdminHomeScreen(
          profile: profile,
          onOpenTraineeView: _enterPreview,
        );

      case AppRole.pending:
        return RoleChoiceScreen(
          onActivated: _grantAccess,
          revokedMessage: _revokedMessage,
        );
    }
  }

  Widget _orphanedTrainee() {
    return AuthScaffold(
      title: 'Account not linked',
      subtitle: 'Your trainee record is no longer available. '
          'Ask your coach for a new code.',
      children: [
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: () => setState(() => _profile = _profile!.copyWith(role: AppRole.pending)),
            child: const Text('Enter a new code'),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: () => AuthService.signOut(),
            child: const Text('Sign out', style: TextStyle(color: Colors.white54)),
          ),
        ),
      ],
    );
  }
}
