import 'package:flutter/material.dart';
import '../../models/app_profile.dart';
import '../../services/auth_service.dart';
import 'access_code_screen.dart';
import 'auth_scaffold.dart';

/// Step 3, for every account except the admin: coach or trainee.
/// Either choice still has to be unlocked with a code, so picking the wrong
/// one here costs nothing but a tap back.
class RoleChoiceScreen extends StatelessWidget {
  final ValueChanged<SessionAccess> onActivated;

  /// True when reached from inside the app rather than as the sign-up step —
  /// the user already has a role and can back out.
  final bool canDismiss;

  /// Shown when this screen is reached because a live check just revoked the
  /// previous session (a deleted coach code, a removed coach) — otherwise
  /// being bounced back here mid-use with no explanation looks like a bug.
  final String? revokedMessage;

  const RoleChoiceScreen({
    super.key,
    required this.onActivated,
    this.canDismiss = false,
    this.revokedMessage,
  });

  /// Opens the role/code screen from anywhere in the app, so someone given a
  /// new code — or whose coach access was revoked — can redeem it without
  /// signing out first.
  /// Opens the role/code screen from inside the app — used by a coach who
  /// wants to look at a trainee's programme without signing out.
  static Future<void> open(BuildContext context,
      {required ValueChanged<SessionAccess> onActivated}) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RoleChoiceScreen(canDismiss: true, onActivated: onActivated),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      onBack: canDismiss ? () => Navigator.pop(context) : null,
      title: 'How will you use AGILE?',
      subtitle: 'Pick your role, then enter the access code you were given.',
      children: [
        if (revokedMessage != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFF87171).withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFF87171).withOpacity(0.5)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, size: 16, color: Color(0xFFF87171)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(revokedMessage!,
                      style: const TextStyle(
                          color: Color(0xFFF87171), fontSize: 13, height: 1.4)),
                ),
              ],
            ),
          ),
        ],
        _RoleCard(
          icon: Icons.sports,
          color: const Color(0xFF9333EA),
          title: 'I am a Coach',
          body: 'Build programs and track your own trainees. Needs a coach code from the admin.',
          onTap: () => _open(context, AccessCodeRole.coach),
        ),
        const SizedBox(height: 12),
        _RoleCard(
          icon: Icons.fitness_center,
          color: const Color(0xFF2563EB),
          title: 'I am a Trainee',
          body: 'Follow your program and log your sets. Needs the code from your coach or the admin.',
          onTap: () => _open(context, AccessCodeRole.trainee),
        ),
        const SizedBox(height: 20),
        if (!canDismiss)
          Center(
            child: TextButton(
              onPressed: () => AuthService.signOut(),
              child: const Text('Sign out', style: TextStyle(fontSize: 13, color: Colors.white54)),
            ),
          ),
      ],
    );
  }

  void _open(BuildContext context, AccessCodeRole role) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AccessCodeScreen(role: role, onActivated: onActivated),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  final VoidCallback onTap;

  const _RoleCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kSlate700,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 3),
                  Text(body,
                      style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.35)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}
