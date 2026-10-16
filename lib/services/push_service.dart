import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../supabase_config.dart';
import 'notification_service.dart';

/// Registers this device to receive the "trainee finished their block" alert
/// and displays it if it arrives while the app is already open.
///
/// Only a coach or the admin ever needs this — a trainee's device never
/// registers a token, since nothing is ever pushed to a trainee.
class PushService {
  static bool _listening = false;

  /// Call once the signed-in profile resolves to a coach or admin. Safe to
  /// call repeatedly — it registers the current token once per app run and
  /// then only reacts to Firebase's own refresh events.
  static Future<void> register() async {
    try {
      final messaging = FirebaseMessaging.instance;

      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      final token = await messaging.getToken();
      if (token != null) await _upsertToken(token);

      if (!_listening) {
        _listening = true;
        messaging.onTokenRefresh.listen(_upsertToken);

        // The system tray already shows this for a backgrounded or closed
        // app; only the foreground case needs to be surfaced by hand.
        FirebaseMessaging.onMessage.listen((message) {
          final notification = message.notification;
          if (notification == null) return;
          NotificationService.showNow(
            title: notification.title ?? 'AGILE',
            body: notification.body ?? '',
          );
        });
      }
    } catch (e) {
      // Push is a convenience layer on top of the app, not a dependency of
      // it — a coach whose device rejects FCM (no Google Play Services, a
      // stripped-down ROM) should never lose the ability to use the app.
      debugPrint('PushService.register failed: $e');
    }
  }

  static Future<void> _upsertToken(String token) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await supabase.from('push_tokens').upsert(
        {
          'profile_id': uid,
          'token': token,
          'platform': defaultTargetPlatform.name,
          'updated_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'token',
      );
    } catch (e) {
      debugPrint('PushService token upsert failed: $e');
    }
  }

  /// Removes this device's token so it stops receiving alerts after sign-out
  /// — otherwise a phone that changes hands (or a coach who signs into a
  /// second account) keeps getting pushes meant for whoever registered it.
  static Future<void> unregister() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await supabase.from('push_tokens').delete().eq('token', token);
      }
    } catch (e) {
      debugPrint('PushService.unregister failed: $e');
    }
  }
}
