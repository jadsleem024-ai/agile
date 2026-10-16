import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/auth_service.dart';
import 'auth_scaffold.dart';

/// Code-based password reset.
///
/// Supabase's stock reset emails a link pointing at the project's site_url,
/// which on a phone opens nothing — so this asks for the emailed 6-digit code
/// and sets the new password in the app instead.
class ResetPasswordScreen extends StatefulWidget {
  final String initialEmail;

  const ResetPasswordScreen({super.key, this.initialEmail = ''});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();

  PendingVerification? _pending;
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _emailController.text = widget.initialEmail;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final pending = await AuthService.sendPasswordReset(email);
      if (mounted) setState(() => _pending = pending);
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not send the code. Check your connection.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitNewPassword() async {
    final code = _codeController.text.trim();
    final password = _passwordController.text;

    if (code.length < 6) {
      setState(() => _error = 'Enter the 6-digit code from your email.');
      return;
    }
    if (password.length < 6) {
      setState(() => _error = 'New password must be at least 6 characters.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.completePasswordReset(
        pending: _pending!,
        code: code,
        newPassword: password,
      );
      if (!mounted) return;
      // The reset leaves a valid session, so AuthGate drops straight into the
      // app rather than making them sign in again with the password they just
      // typed.
      Navigator.of(context).popUntil((r) => r.isFirst);
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not reset the password. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sent = _pending != null;

    return AuthScaffold(
      onBack: _busy ? null : () => Navigator.pop(context),
      title: 'Reset password',
      subtitle: sent
          ? 'Enter the code sent to\n${_pending!.email}\nand pick a new password.'
          : 'We will email you a 6-digit code.',
      children: [
        AuthError(_error),
        if (!sent) ...[
          TextField(
            controller: _emailController,
            enabled: !_busy,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            onSubmitted: (_) => _busy ? null : _sendCode(),
            style: const TextStyle(color: Colors.white, fontSize: 15),
            decoration: authField('Email address', icon: Icons.mail_outline),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _busy ? null : _sendCode,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Send code',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ] else ...[
          TextField(
            controller: _codeController,
            enabled: !_busy,
            autofocus: true,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.bold,
              letterSpacing: 10,
            ),
            decoration: authField('------').copyWith(
              counterText: '',
              hintStyle: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 26,
                fontWeight: FontWeight.bold,
                letterSpacing: 10,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            enabled: !_busy,
            obscureText: _obscure,
            onSubmitted: (_) => _busy ? null : _submitNewPassword(),
            style: const TextStyle(color: Colors.white, fontSize: 15),
            decoration: authField(
              'New password',
              icon: Icons.lock_outline,
              suffix: IconButton(
                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                    color: const Color(0xFF94A3B8), size: 20),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _busy ? null : _submitNewPassword,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Set new password',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: _busy ? null : _sendCode,
              child: const Text('Send a new code', style: TextStyle(fontSize: 13)),
            ),
          ),
        ],
      ],
    );
  }
}
