import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase authentication wrapper used by the role gate and API requests.
class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  SupabaseClient get _client => Supabase.instance.client;

  bool get isAuthenticated => _client.auth.currentSession != null;
  User? get currentUser => _client.auth.currentUser;

  String get role =>
      currentUser?.userMetadata?['role']?.toString().toUpperCase() ?? 'EXTERNAL';

  String get displayName {
    final user = currentUser;
    if (user == null) return 'OptiFlow User';
    final fullName = user.userMetadata?['full_name']?.toString();
    return (fullName != null && fullName.isNotEmpty)
        ? fullName
        : user.email?.split('@').first ?? 'OptiFlow User';
  }

  String? get resourceId => currentUser?.userMetadata?['resource_id']?.toString();

  Future<void> signIn({required String email, required String password}) async {
    final response = await _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    if (response.session == null) {
      throw Exception('Sign in failed. Please check your credentials.');
    }
  }

  Future<void> signOut() => _client.auth.signOut();
}
