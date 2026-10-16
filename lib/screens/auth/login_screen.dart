import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import 'auth_scaffold.dart';
import 'reset_password_screen.dart';
import 'verify_code_screen.dart';

/// Step 1 of the flow: email + password. Nothing else is reachable until the
/// emailed code from step 2 is entered.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();

  bool _isSignUp = false;
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    if (password.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final pending = _isSignUp
          ? await AuthService.signUp(
              email: email,
              password: password,
              fullName: _nameController.text,
            )
          : await AuthService.signIn(email: email, password: password);

      if (!mounted) return;

      // Signing in needs no code — the session is already live and AuthGate
      // routes on it. Only a new (or never-confirmed) account gets the step.
      if (pending == null) return;

      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => VerifyCodeScreen(pending: pending)),
      );
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Something went wrong. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _forgotPassword() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ResetPasswordScreen(initialEmail: _emailController.text.trim()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'AGILE',
      subtitle: _isSignUp
          ? 'Create your account. We will email you a code to confirm it.'
          : 'Sign in with your email and password.',
      children: [
        AuthError(_error),
        if (_isSignUp) ...[
          TextField(
            controller: _nameController,
            enabled: !_busy,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(color: Colors.white, fontSize: 15),
            decoration: authField('Your name', icon: Icons.person_outline),
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _emailController,
          enabled: !_busy,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          style: const TextStyle(color: Colors.white, fontSize: 15),
          decoration: authField('Email address', icon: Icons.mail_outline),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passwordController,
          enabled: !_busy,
          obscureText: _obscure,
          onSubmitted: (_) => _busy ? null : _submit(),
          style: const TextStyle(color: Colors.white, fontSize: 15),
          decoration: authField(
            'Password',
            icon: Icons.lock_outline,
            suffix: IconButton(
              icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                  color: const Color(0xFF94A3B8), size: 20),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        if (!_isSignUp)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _busy ? null : _forgotPassword,
              child: const Text('Forgot password?', style: TextStyle(fontSize: 12)),
            ),
          ),
        const SizedBox(height: 8),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(_isSignUp ? 'Create account' : 'Continue',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 14),
        Center(
          child: TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                      _isSignUp = !_isSignUp;
                      _error = null;
                    }),
            child: Text(
              _isSignUp ? 'Already have an account? Sign in' : "New here? Create an account",
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }
}
