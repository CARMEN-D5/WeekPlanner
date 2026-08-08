import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../data/profile_repository.dart';

class AuthService extends ChangeNotifier {
  AuthService(this._client, this._profiles) {
    _subscription = _client.auth.onAuthStateChange.listen((event) async {
      await _refresh(event.session?.user);
    });
    _refresh(_client.auth.currentUser);
  }

  final SupabaseClient _client;
  final ProfileRepository _profiles;
  late final StreamSubscription<AuthState> _subscription;
  UserProfile? profile;
  bool loading = true;

  User? get user => _client.auth.currentUser;
  bool get isSignedIn => user != null;
  bool get isEmailVerified => user?.emailConfirmedAt != null;

  Future<void> _refresh(User? currentUser) async {
    loading = true;
    notifyListeners();
    if (currentUser == null) {
      profile = null;
    } else {
      try {
        profile = await _profiles.ensureFor(currentUser);
      } catch (error, stack) {
        // Authentication must remain usable if the optional profiles table has
        // not been installed yet. SQL is provided with the release artifact.
        debugPrint('Profile bootstrap failed: $error\n$stack');
      }
    }
    loading = false;
    notifyListeners();
  }

  Future<AuthResponse> signUp(String email, String password, String name) =>
      _client.auth.signUp(
        email: email.trim(),
        password: password,
        data: {'display_name': name.trim()},
        emailRedirectTo: SupabaseConfig.redirectUrl,
      );

  Future<AuthResponse> signIn(String email, String password) =>
      _client.auth.signInWithPassword(email: email.trim(), password: password);

  Future<void> signInWithGoogle() => _client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: SupabaseConfig.redirectUrl,
        authScreenLaunchMode: LaunchMode.externalApplication,
      );

  Future<void> sendPasswordReset(String email) =>
      _client.auth.resetPasswordForEmail(
        email.trim(),
        redirectTo: SupabaseConfig.redirectUrl,
      );

  Future<void> resendVerification() async {
    final email = user?.email;
    if (email == null) return;
    await _client.auth.resend(
      type: OtpType.signup,
      email: email,
      emailRedirectTo: SupabaseConfig.redirectUrl,
    );
  }

  Future<void> signOut() => _client.auth.signOut();

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
