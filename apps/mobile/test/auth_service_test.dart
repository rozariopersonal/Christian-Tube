import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile/core/models/user.dart';
import 'package:mobile/features/auth/auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AuthService State and Storage', () {
    test('initializes with unauthenticated state', () {
      final authService = AuthService();
      expect(authService.isAuthenticated, isFalse);
      expect(authService.currentUser, isNull);
      expect(authService.isAdmin, isFalse);
      expect(authService.isLoading, isFalse);
      expect(authService.lastError, isNull);
    });

    test('loads cached user from storage on creation', () async {
      const mockUser = User(
        id: '12345',
        email: 'test@example.com',
        displayName: 'Test User',
        idToken: 'mock_token',
      );
      SharedPreferences.setMockInitialValues({
        'current_user': jsonEncode(mockUser.toJson()),
        'auth_token': 'mock_token',
      });

      final authService = AuthService();
      // Allow async _loadUserFromStorage to complete
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(authService.isAuthenticated, isTrue);
      expect(authService.currentUser?.email, 'test@example.com');
      expect(authService.currentUser?.displayName, 'Test User');
    });

    test('signOut clears user and stored preferences', () async {
      const mockUser = User(
        id: '12345',
        email: 'test@example.com',
        displayName: 'Test User',
        idToken: 'mock_token',
      );
      SharedPreferences.setMockInitialValues({
        'current_user': jsonEncode(mockUser.toJson()),
        'auth_token': 'mock_token',
      });

      final authService = AuthService();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(authService.isAuthenticated, isTrue);

      await authService.signOut();

      expect(authService.isAuthenticated, isFalse);
      expect(authService.currentUser, isNull);
      expect(authService.isAdmin, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('current_user'), isNull);
      expect(prefs.getString('auth_token'), isNull);
    });

    test('buildGuestToken embeds the claimed email so admins pass backend guard', () {
      expect(
        AuthService.buildGuestToken(userId: 'u1', email: 'arul.rozario4@gmail.com'),
        'token_u1::arul.rozario4@gmail.com',
      );
      expect(AuthService.buildGuestToken(userId: 'u1', email: '  a@b.c  '), 'token_u1::a@b.c');
      expect(AuthService.buildGuestToken(userId: 'u1'), 'token_u1');
      expect(AuthService.buildGuestToken(userId: 'u1', email: ''), 'token_u1');
    });

    test('signInAsGuest stores a token embedding the claimed email', () async {
      final authService = AuthService();
      await authService.signInAsGuest(
        'Admin Tester',
        'arul.rozario4@gmail.com',
      );

      expect(authService.isAuthenticated, isTrue);
      expect(authService.currentUser?.email, 'arul.rozario4@gmail.com');

      final prefs = await SharedPreferences.getInstance();
      final storedToken = prefs.getString('auth_token');
      expect(storedToken, startsWith('token_user_'));
      expect(storedToken, endsWith('::arul.rozario4@gmail.com'));
    });
  });
}
