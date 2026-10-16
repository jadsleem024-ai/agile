import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/app_profile.dart';
import '../../services/auth_service.dart';
import 'auth_scaffold.dart';

enum AccessCodeRole { coach, trainee }

/// Step 4: redeem the access code that unlocks the chosen role.
///
/// Coach codes are minted by the admin; trainee codes are the code attached to
/// the trainee record by whoever created it (admin or coach). Both are checked
/// server-side, so a wrong guess here never grants anything.
class AccessCodeScreen extends StatefulWidget {
  final AccessCodeRole role;
  final ValueChanged<SessionAccess> onActivated;

  const AccessCodeScreen({super.key, required this.role, required this.onActivated});

  @override
  State<AccessCodeScreen> createState() => _AccessCodeScreenState();
}

class _AccessCodeScreenState extends State<AccessCodeScreen> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  bool get _isCoach => widget.role == AccessCodeRole.coach;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _controller.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Enter your access code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final access = _isCoach
          ? await AuthService.claimCoachCode(code)
          : await AuthService.claimTraineeCode(code);
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
      widget.onActivated(access);
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not check that code. Check your connection.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      onBack: _busy ? null : () => Navigator.pop(context),
      title: _isCoach ? 'Coach access code' : 'Your trainee code',
      subtitle: _isCoach
          ? 'Enter the coach code the admin gave you.'
          : 'Enter the code your coach gave you.',
      children: [
        AuthError(_error),
        TextField(
          controller: _controller,
          enabled: !_busy,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          textAlign: TextAlign.center,
          autocorrect: false,
          onSubmitted: (_) => _busy ? null : _submit(),
          inputFormatters: [UpperCaseFormatter()],
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
            letterSpacing: 5,
          ),
          decoration: authField('ABC123').copyWith(
            hintStyle: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 24,
              fontWeight: FontWeight.bold,
              letterSpacing: 5,
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 18),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Unlock', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            _isCoach
                ? 'Only the admin can issue coach codes.'
                : "Don't have a code? Ask your coach for it.",
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

/// Access codes are stored and compared upper-case; normalise as the user types
/// so the field always matches what the server will look for.
class UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
