import 'package:supabase_flutter/supabase_flutter.dart';

/// New Supabase project
const String supabaseUrl = 'https://yuaevlnbmsildmyuiujr.supabase.co';
const String supabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inl1YWV2bG5ibXNpbGRteXVpdWpyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ5NjIwMzEsImV4cCI6MjEwMDUzODAzMX0.-_lIrRUAgwp5u88ee5bwGjaXUPAPs_RB3ySEbXiZT0U';

Future<void> initSupabase() async {
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );
}

SupabaseClient get supabase => Supabase.instance.client;