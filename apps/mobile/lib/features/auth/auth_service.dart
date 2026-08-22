import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/api/api_client.dart';
import '../../core/models/user.dart';

class AuthService extends ChangeNotifier {
  final ApiClient _apiClient = ApiClient();
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
  );

  User? _currentUser;
  bool _isLoading = false;

  User? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isLoading => _isLoading;

  AuthService() {
    _loadUserFromStorage();
  }

  Future<void> _loadUserFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString('current_user');
    if (userJson != null) {
      try {
        _currentUser = User.fromJson(jsonDecode(userJson));
        notifyListeners();
      } catch (e) {
        debugPrint('Failed to parse cached user: $e');
      }
    }
  }

  Future<User?> signInWithGoogle() async {
    _isLoading = true;
    notifyListeners();

    try {
      final account = await _googleSignIn.signIn();
      if (account != null) {
        final auth = await account.authentication;
        final user = User(
          id: account.id,
          email: account.email,
          displayName: account.displayName ?? 'ChristianTube User',
          photoUrl: account.photoUrl,
          idToken: auth.idToken,
        );

        // Sync with backend API
        try {
          await _apiClient.dio.post(
            '/user/sync',
            data: user.toJson(),
          );
        } catch (e) {
          debugPrint('Backend user sync non-blocking error: $e');
        }

        _currentUser = user;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('current_user', jsonEncode(user.toJson()));
        if (auth.idToken != null) {
          await prefs.setString('auth_token', auth.idToken!);
        }

        notifyListeners();
        return user;
      }
    } catch (e) {
      debugPrint('Google Sign-In Error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    return null;
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {}

    _currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('current_user');
    await prefs.remove('auth_token');
    notifyListeners();
  }
}
