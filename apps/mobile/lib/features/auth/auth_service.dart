import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/api/api_client.dart';
import '../../core/models/user.dart';
import '../../core/config/app_config.dart';

class AuthService extends ChangeNotifier {
  final ApiClient _apiClient = ApiClient();
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
  );

  User? _currentUser;
  bool _isLoading = false;
  String? _lastError;

  User? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isLoading => _isLoading;
  String? get lastError => _lastError;

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
    _lastError = null;
    notifyListeners();

    try {
      final account = await _googleSignIn.signIn();
      if (account != null) {
        final auth = await account.authentication;
        final user = User(
          id: account.id,
          email: account.email,
          displayName: account.displayName ?? '${AppConfig.appName} User',
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
      _lastError = 'Google Sign-In was cancelled or unavailable on this device.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    return null;
  }

  Future<User> signInAsGuest([String? customName, String? customEmail]) async {
    _isLoading = true;
    _lastError = null;
    notifyListeners();

    final id = 'user_${DateTime.now().millisecondsSinceEpoch}';
    final name = (customName != null && customName.trim().isNotEmpty)
        ? customName.trim()
        : '${AppConfig.appName} Student';
    final email = (customEmail != null && customEmail.trim().isNotEmpty)
        ? customEmail.trim()
        : '$id@privatetube.app';

    final user = User(
      id: id,
      email: email,
      displayName: name,
      photoUrl: null,
      idToken: 'token_$id',
    );

    _currentUser = user;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('current_user', jsonEncode(user.toJson()));
    await prefs.setString('auth_token', user.idToken ?? '');

    _isLoading = false;
    notifyListeners();
    return user;
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
