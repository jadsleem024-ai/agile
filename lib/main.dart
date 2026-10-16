import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'supabase_config.dart';
import 'services/local_storage.dart';
import 'services/notification_service.dart';
import 'screens/auth/auth_gate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initSupabase();
  await LocalStorage.init();
  await NotificationService.init();
  await _initFirebase();
  runApp(const CoachApp());
}

/// Firebase powers the "trainee finished their block" push to a coach. Until
/// android/app/google-services.json is added (see supabase/SETUP.md), there is
/// no native config for it to find, and initialization throws — caught here so
/// the app runs exactly as before rather than failing to start.
Future<void> _initFirebase() async {
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Firebase not configured yet, push notifications disabled: $e');
  }
}

class CoachApp extends StatelessWidget {
  const CoachApp({super.key});

  @override
  Widget build(BuildContext context) {
    const slate900 = Color(0xFF0F172A);
    const slate800 = Color(0xFF1E293B);
    const slate700 = Color(0xFF334155);
    const blue600 = Color(0xFF2563EB);

    return MaterialApp(
      title: 'Coach Admin Panel',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: slate900,
        colorScheme: ColorScheme.dark(
          primary: blue600,
          secondary: blue600,
          surface: slate800,
          background: slate900,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: slate900,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        cardColor: slate800,
        dividerColor: slate700,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: slate700,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: blue600,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        textTheme: Typography.whiteMountainView,
      ),
      home: const AuthGate(),
    );
  }
}
