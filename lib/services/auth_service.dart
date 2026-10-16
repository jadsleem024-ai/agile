import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase_config.dart';
import '../models/app_profile.dart';
import 'push_service.dart';

/// Raised for anything the user should see verbatim on screen.
class AuthFailure implements Exception {
  final String message;
  AuthFailure(this.message);
  @override
  String toString() => message;
}

/// Which email template the pending 6-digit code came from. Sign-up codes and
/// sign-in codes are verified against different OTP types.
class PendingVerification {
  final String email;
  final OtpType type;
  const PendingVerification(this.email, this.type);
}

/// Email + password.
///
/// A one-time emailed code is required once, when the account is created, to
/// prove the address is real. After that, signing in is password only.
class AuthService {
  static Session? get session => supabase.auth.currentSession;
  static User? get user => supabase.auth.currentUser;
  static bool get isSignedIn => session != null;

  static Stream<AuthState> get onAuthStateChange => supabase.auth.onAuthStateChange;

  // ---------------- SIGN UP / SIGN IN ----------------

  static Future<PendingVerification> signUp({
    required String email,
    required String password,
    String? fullName,
  }) async {
    final normalized = email.trim().toLowerCase();
    try {
      final res = await supabase.auth.signUp(
        email: normalized,
        password: password,
        data: fullName != null && fullName.trim().isNotEmpty ? {'full_name': fullName.trim()} : null,
      );

      // When the project has "Confirm email" turned off, signUp hands back a
      // live session. Drop it and gate on an emailed code anyway.
      if (res.session != null) {
        await supabase.auth.signOut();
        await supabase.auth.signInWithOtp(email: normalized, shouldCreateUser: false);
        return PendingVerification(normalized, OtpType.email);
      }
      return PendingVerification(normalized, OtpType.signup);
    } on AuthException catch (e) {
      throw AuthFailure(_readable(e));
    }
  }

  /// Signs in an existing account with just the password.
  ///
  /// Returns null on success — the session is live and the app can proceed.
  /// Returns a [PendingVerification] only when the address was never confirmed
  /// (the account was created but the sign-up code never entered), in which
  /// case a fresh code has been emailed rather than dead-ending the user.
  static Future<PendingVerification?> signIn({
    required String email,
    required String password,
  }) async {
    final normalized = email.trim().toLowerCase();
    try {
      await supabase.auth.signInWithPassword(email: normalized, password: password);
    } on AuthException catch (e) {
      if (_isUnconfirmedEmail(e)) {
        await supabase.auth.resend(type: OtpType.signup, email: normalized);
        return PendingVerification(normalized, OtpType.signup);
      }
      throw AuthFailure(_readable(e));
    }
    return null;
  }

  static Future<void> resend(PendingVerification pending) async {
    try {
      if (pending.type == OtpType.signup) {
        await supabase.auth.resend(type: OtpType.signup, email: pending.email);
      } else {
        await supabase.auth.signInWithOtp(email: pending.email, shouldCreateUser: false);
      }
    } on AuthException catch (e) {
      throw AuthFailure(_readable(e));
    }
  }

  static Future<void> verifyCode(PendingVerification pending, String code) async {
    try {
      await supabase.auth.verifyOTP(
        email: pending.email,
        token: code.trim(),
        type: pending.type,
      );
    } on AuthException catch (e) {
      throw AuthFailure(_readable(e));
    }
    if (supabase.auth.currentSession == null) {
      throw AuthFailure('Could not verify that code. Please try again.');
    }
  }

  /// Starts a password reset. The recovery email carries a 6-digit code rather
  /// than a link — a link would open the project's site_url in a browser, which
  /// on a phone goes nowhere.
  static Future<PendingVerification> sendPasswordReset(String email) async {
    final normalized = email.trim().toLowerCase();
    try {
      await supabase.auth.resetPasswordForEmail(normalized);
    } on AuthException catch (e) {
      throw AuthFailure(_readable(e));
    }
    return PendingVerification(normalized, OtpType.recovery);
  }

  /// Verifies a recovery code and sets the new password in one step. Verifying
  /// grants a short-lived session, which is what authorises the change.
  static Future<void> completePasswordReset({
    required PendingVerification pending,
    required String code,
    required String newPassword,
  }) async {
    try {
      await supabase.auth.verifyOTP(
        email: pending.email,
        token: code.trim(),
        type: OtpType.recovery,
      );
    } on AuthException catch (e) {
      throw AuthFailure(_readable(e));
    }
    if (supabase.auth.currentSession == null) {
      throw AuthFailure('That code could not be verified. Please try again.');
    }
    try {
      await supabase.auth.updateUser(UserAttributes(password: newPassword));
    } on AuthException catch (e) {
      // Leave no half-authenticated session behind if the change is rejected.
      await supabase.auth.signOut();
      throw AuthFailure(_readable(e));
    }
  }

  static Future<void> signOut() async {
    // Best-effort: forgetting to drop the device's push token would leave it
    // receiving another account's alerts, but a failure here should never
    // block the sign-out itself.
    try {
      await PushService.unregister();
    } catch (_) {}
    await supabase.auth.signOut();
  }

  // ---------------- PROFILE ----------------

  /// Reads the caller's profile row, joining the trainee record when linked.
  /// Returns null only if there is no session.
  static Future<AppProfile?> loadProfile() async {
    final u = supabase.auth.currentUser;
    if (u == null) return null;

    final row = await supabase.from('profiles').select().eq('id', u.id).maybeSingle();

    // The provisioning trigger normally creates this row; if it somehow has
    // not landed yet, fall back to a pending profile rather than erroring out.
    if (row == null) {
      return AppProfile(id: u.id, email: u.email ?? '', role: AppRole.pending);
    }

    Map<String, dynamic>? trainee;
    if (row['trainee_id'] != null) {
      trainee = await supabase
          .from('trainees')
          .select('id, name, code')
          .eq('id', row['trainee_id'])
          .maybeSingle();
    }
    return AppProfile.fromMap(row, trainee: trainee);
  }

  // ---------------- CODE REDEMPTION ----------------

  /// Redeems an admin-issued coach code and grants coach access for this app
  /// session. The code is re-checked every time, so deleting it in the admin
  /// panel locks the coach out from their next launch onward.
  static Future<SessionAccess> claimCoachCode(String code) async {
    final result = await supabase.rpc('claim_coach_code', params: {'p_code': code.trim()});
    _throwIfNotOk(result);
    return SessionAccess.fromRpc((result as Map).cast<String, dynamic>());
  }

  /// Redeems a trainee code. A coach or the admin entering the code of one of
  /// their own trainees gets a read-only preview instead of taking the account
  /// over — see claim_trainee_code in the migration.
  static Future<SessionAccess> claimTraineeCode(String code) async {
    final result = await supabase.rpc('claim_trainee_code', params: {'p_code': code.trim()});
    _throwIfNotOk(result);
    return SessionAccess.fromRpc((result as Map).cast<String, dynamic>());
  }

  static void _throwIfNotOk(dynamic result) {
    if (result is Map && result['ok'] != true) {
      throw AuthFailure(result['error']?.toString() ?? 'That code was not accepted.');
    }
  }

  // ---------------- ERROR TEXT ----------------

  static bool _isUnconfirmedEmail(AuthException e) {
    final m = e.message.toLowerCase();
    return m.contains('not confirmed') || m.contains('email_not_confirmed');
  }

  static String _readable(AuthException e) {
    final m = e.message.toLowerCase();
    if (m.contains('invalid login credentials')) {
      return 'Wrong email or password.';
    }
    if (m.contains('already registered') || m.contains('already been registered')) {
      return 'That email already has an account. Sign in instead.';
    }
    if (m.contains('token has expired') || m.contains('expired')) {
      return 'That code has expired. Send a new one.';
    }
    if (m.contains('invalid token') || m.contains('otp')) {
      return 'That code is not correct.';
    }
    if (m.contains('rate limit') || m.contains('too many')) {
      return 'Too many attempts. Wait a minute and try again.';
    }
    if (m.contains('password') && m.contains('6')) {
      return 'Password must be at least 6 characters.';
    }
    return e.message;
  }
}
