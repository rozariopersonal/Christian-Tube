import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/api/api_client.dart';
import '../../core/models/user.dart';
import '../../core/config/app_config.dart';

class AuthService extends ChangeNotifier {
  // Client ID now comes dynamically from AppConfig

  final ApiClient _apiClient = ApiClient();
  late GoogleSignIn _googleSignIn;

  User? _currentUser;
  bool _isAdmin = false;
  bool _isLoading = false;
  String? _lastError;

  User? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isAdmin => _isAdmin;
  bool get isLoading => _isLoading;
  String? get lastError => _lastError;

  AuthService() {
    _initGoogleSignIn();
    _loadUserFromStorage();
  }

  void _initGoogleSignIn() {
    _googleSignIn = GoogleSignIn(
      clientId: kIsWeb ? AppConfig.googleClientId : null,
      scopes: const ['email', 'profile'],
    );
  }

  Future<void> _loadUserFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString('current_user');
    if (userJson != null) {
      try {
        _currentUser = User.fromJson(jsonDecode(userJson));
        await checkIsAdmin(_currentUser?.email);
        notifyListeners();
      } catch (e) {
        debugPrint('Failed to parse cached user: $e');
      }
    }
  }

  Future<bool> checkIsAdmin([String? email]) async {
    final targetEmail = email ?? _currentUser?.email;
    if (targetEmail == null || targetEmail.isEmpty) {
      _isAdmin = false;
      notifyListeners();
      return false;
    }

    try {
      final response = await _apiClient.dio.get(
        '/channels/check-admin',
        queryParameters: {'email': targetEmail},
      );
      if (response.statusCode == 200 && response.data != null) {
        _isAdmin = response.data['isAdmin'] == true;
        notifyListeners();
        return _isAdmin;
      }
    } catch (e) {
      debugPrint('Admin check error: $e');
    }
    return _isAdmin;
  }

  Future<User?> signInWithGoogle() async {
    _isLoading = true;
    _lastError = null;
    notifyListeners();

    try {
      // Disconnect previous session to allow clean account picker
      try {
        await _googleSignIn.signOut();
      } catch (_) {}

      GoogleSignInAccount? account;
      String? innerError;
      try {
        account = await _googleSignIn.signIn();
      } catch (e) {
        debugPrint('Primary Google Sign-In attempt error: $e');
        innerError = e.toString();
        // Fallback: try with serverClientId if configured
        if (!kIsWeb) {
          try {
            final fallbackSignIn = GoogleSignIn(
              serverClientId: AppConfig.googleClientId,
              scopes: const ['email', 'profile'],
            );
            account = await fallbackSignIn.signIn();
            innerError = null; // Cleared if fallback succeeds
          } catch (e2) {
            debugPrint('Fallback Google Sign-In attempt error: $e2');
            innerError = e2.toString();
          }
        }
      }

      if (account != null) {
        String? idToken;
        try {
          final auth = await account.authentication.timeout(
            const Duration(seconds: 6),
            onTimeout: () => throw Exception('Authentication timeout'),
          );
          idToken = auth.idToken;
        } catch (authErr) {
          debugPrint('Google authentication token fetch warning: $authErr');
        }

        final user = User(
          id: account.id.isNotEmpty ? account.id : 'user_${DateTime.now().millisecondsSinceEpoch}',
          email: account.email,
          displayName: account.displayName != null && account.displayName!.isNotEmpty
              ? account.displayName!
              : account.email.split('@').first,
          photoUrl: account.photoUrl,
          idToken: idToken ?? 'token_${account.id}',
        );

        _currentUser = user;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('current_user', jsonEncode(user.toJson()));
        if (user.idToken != null) {
          await prefs.setString('auth_token', user.idToken!);
        }

        // Non-blocking sync with backend API
        _syncUserWithBackend(user);

        await checkIsAdmin(user.email);

        _isLoading = false;
        notifyListeners();
        return user;
      } else {
        if (innerError != null) {
          _lastError = 'Sign-in failed. Please check app configuration/SHA-1 setup.\nDetails: ${innerError.replaceAll('Exception:', '').trim()}';
        } else {
          _lastError = 'Sign-in cancelled by user.';
        }
      }
    } catch (e) {
      debugPrint('Google Sign-In General Error: $e');
      _lastError = 'Google Sign-In failed: ${e.toString().replaceAll('Exception:', '').trim()}';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    return null;
  }

  void _syncUserWithBackend(User user) {
    Future.microtask(() async {
      try {
        await _apiClient.dio.post(
          '/user/sync',
          data: user.toJson(),
        );
      } catch (e) {
        debugPrint('Backend user sync non-blocking error: $e');
      }
    });
  }

  Future<User> signInAsGuest([String? customName, String? customEmail]) async {
    _isLoading = true;
    _lastError = null;
    notifyListeners();

    final id = 'user_${DateTime.now().millisecondsSinceEpoch}';
    final name = (customName != null && customName.trim().isNotEmpty)
        ? customName.trim()
        : '${AppConfig.appName} Member';
    final email = (customEmail != null && customEmail.trim().isNotEmpty)
        ? customEmail.trim()
        : 'admin@centumacademy.org';

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

    _syncUserWithBackend(user);
    await checkIsAdmin(user.email);

    _isLoading = false;
    notifyListeners();
    return user;
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {}

    _currentUser = null;
    _isAdmin = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('current_user');
    await prefs.remove('auth_token');
    notifyListeners();
  }
}
