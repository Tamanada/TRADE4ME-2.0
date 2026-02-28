import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static SupabaseService? _instance;
  static SupabaseService get instance => _instance ??= SupabaseService._();

  SupabaseService._();

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  static bool _initialized = false;

  // Initialize Supabase - call this in main()
  static Future<void> initialize() async {
    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) return;
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
    _initialized = true;
  }

  bool get isInitialized => _initialized;

  // Get Supabase client - throws StateError in demo mode
  SupabaseClient get client {
    if (!_initialized) throw StateError('Supabase not initialized (demo mode)');
    return Supabase.instance.client;
  }

  // Get current user ID
  String? getCurrentUserId() {
    if (!isInitialized) return null;
    return client.auth.currentUser?.id;
  }
}
