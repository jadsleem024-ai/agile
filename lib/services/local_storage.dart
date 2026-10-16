import 'package:shared_preferences/shared_preferences.dart';

class LocalStorage {
  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  static SharedPreferences get _p {
    if (_prefs == null) {
      throw StateError('LocalStorage.init() must be called before use');
    }
    return _prefs!;
  }

  // Trainee session
  static String? get traineeCode => _p.getString('traineeCode');
  static String? get traineeName => _p.getString('traineeName');

  static Future<void> setTraineeSession(String code, String name) async {
    await _p.setString('traineeCode', code);
    await _p.setString('traineeName', name);
  }

  static Future<void> clearTraineeSession() async {
    await _p.remove('traineeCode');
    await _p.remove('traineeName');
  }

  // Rest timer persistence (so an in-flight timer survives app restart)
  static int? get restTimerEndTime => _p.getInt('restTimer_endTime');
  static String? get restTimerWorkoutId => _p.getString('restTimer_workoutId');

  static Future<void> setRestTimer(int endTimeMillis, String workoutId) async {
    await _p.setInt('restTimer_endTime', endTimeMillis);
    await _p.setString('restTimer_workoutId', workoutId);
  }

  static Future<void> clearRestTimer() async {
    await _p.remove('restTimer_endTime');
    await _p.remove('restTimer_workoutId');
  }
}
