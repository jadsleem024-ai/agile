import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Which timer finished — picks the channel, and therefore the sound.
enum TimerAlert { rest, set }

/// OS-scheduled notification support for timer completion.
///
/// Uses the platform alarm/notification scheduler (`zonedSchedule`) rather
/// than an in-process Dart timer, so the alert still fires while the app is
/// backgrounded or the screen is off.
class NotificationService {
  static const int _timerNotificationId = 0;

  // Android freezes a channel's sound at creation time: editing an existing
  // channel is silently ignored on any device that already has it. So the
  // sound lives in the channel id — bump the suffix to roll out a new one.
  static const _restChannelId = 'rest_timer_ding_v2';
  static const _setChannelId = 'set_timer_sweet_v2';

  /// Coach-facing "a trainee finished their block" alert. This id must match
  /// the `android.notification.channel_id` the send-block-complete-push edge
  /// function sends, or Android silently falls back to the default channel.
  static const blockCompleteChannelId = 'block_complete';

  /// Channels from earlier builds, removed so users are not left with stale
  /// duplicates in the system notification settings.
  static const _retiredChannelIds = [
    'rest_timer',
    'rest_timer_ding_v1',
    'set_timer_sweet_v1',
  ];

  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    // Only relative ("seconds from now") delays are scheduled, so the
    // absolute instant is correct regardless of which named zone tz.local
    // resolves to (it defaults to UTC) — no need to detect the device zone.
    tz_data.initializeTimeZones();
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    await _plugin.initialize(const InitializationSettings(android: androidSettings, iOS: iosSettings));

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      for (final id in _retiredChannelIds) {
        await android.deleteNotificationChannel(id);
      }
      await android.createNotificationChannel(_channel(TimerAlert.rest));
      await android.createNotificationChannel(_channel(TimerAlert.set));
      await android.createNotificationChannel(const AndroidNotificationChannel(
        blockCompleteChannelId,
        'Trainee Block Complete',
        description: 'Alerts you when a trainee finishes every loop of their program',
        importance: Importance.high,
      ));
    }
    _initialized = true;
  }

  static AndroidNotificationChannel _channel(TimerAlert alert) {
    final isRest = alert == TimerAlert.rest;
    return AndroidNotificationChannel(
      isRest ? _restChannelId : _setChannelId,
      isRest ? 'Rest Timer' : 'Set Timer',
      description: isRest
          ? 'Alerts when your rest between exercises is up'
          : 'Alerts when a timed set is up',
      importance: Importance.high,
      playSound: true,
      sound: RawResourceAndroidNotificationSound(
        isRest ? 'modern_ding' : 'sweet_text',
      ),
    );
  }

  static Future<void> requestPermission() async {
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
  }

  /// Schedules a notification to fire after [seconds]. Cancels any
  /// previously scheduled one first (only one timer runs at a time).
  static void schedule(
    int seconds, {
    required String title,
    required String body,
    TimerAlert alert = TimerAlert.rest,
  }) {
    cancel();
    final isRest = alert == TimerAlert.rest;
    final androidDetails = AndroidNotificationDetails(
      isRest ? _restChannelId : _setChannelId,
      isRest ? 'Rest Timer' : 'Set Timer',
      channelDescription: isRest
          ? 'Alerts when your rest between exercises is up'
          : 'Alerts when a timed set is up',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      sound: RawResourceAndroidNotificationSound(
        isRest ? 'modern_ding' : 'sweet_text',
      ),
    );
    final details = NotificationDetails(
      android: androidDetails,
      // The matching file has to be added to the iOS bundle in Xcode before
      // this resolves; until then iOS falls back to the default sound.
      iOS: DarwinNotificationDetails(
        sound: isRest ? 'modern_ding.mp3' : 'sweet_text.mp3',
      ),
    );
    final scheduledDate = tz.TZDateTime.now(tz.local).add(Duration(seconds: seconds));
    _plugin.zonedSchedule(
      _timerNotificationId,
      title,
      body,
      scheduledDate,
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  static void cancel() {
    _plugin.cancel(_timerNotificationId);
  }

  /// Shows an immediate notification, used to surface a push message that
  /// arrived while the app was already in the foreground — Android does not
  /// auto-display FCM notifications for an app that is currently on screen,
  /// it only delivers them to FirebaseMessaging.onMessage.
  static Future<void> showNow({required String title, required String body}) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        blockCompleteChannelId,
        'Trainee Block Complete',
        channelDescription: 'Alerts you when a trainee finishes every loop of their program',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );
    // A fixed id would let a foreground message be replaced by a later one
    // before the coach reads it; each gets its own slot instead.
    final id = DateTime.now().millisecondsSinceEpoch.remainder(1 << 31);
    await _plugin.show(id, title, body, details);
  }
}
