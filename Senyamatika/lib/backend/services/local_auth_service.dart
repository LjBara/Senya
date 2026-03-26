import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../models/user_model.dart';
import 'local_storage_service.dart';

/// Local authentication service (no Firebase required)
class LocalAuthService {
  final LocalStorageService _storage = LocalStorageService();

  /// Generate unique user ID
  String _generateUserId() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }

  /// Hash password
  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Register new user
  Future<UserModel?> registerWithEmail({
    required String email,
    required String password,
    required String name,
    String? school,
    String? section,
  }) async {
    try {
      print('📝 Attempting registration for: $email');

      // Check if user already exists
      final existingUser = await _storage.getUserByEmail(email);
      if (existingUser != null) {
        print('❌ Email already registered: $email');
        throw Exception('Email already registered');
      }

      // Create new user
      final uid = _generateUserId();
      final user = UserModel(
        uid: uid,
        name: name,
        email: email,
        school: school,
        section: section,
        createdAt: DateTime.now(),
        lastLogin: DateTime.now(),
      );

      // Save user
      await _storage.saveUser(user);
      print('✓ User saved to database');

      // Save credentials
      final passwordHash = _hashPassword(password);
      await _storage.saveCredentials(email, passwordHash);
      print('✓ Credentials saved');

      // Set as current user
      await _storage.setCurrentUser(uid);
      print('✓ Set as current user');

      print('✅ Registration successful for: $email');
      return user;
    } catch (e) {
      print('❌ Registration error: $e');
      throw Exception('Registration failed: ${e.toString()}');
    }
  }

  /// Sign in with email and password
  Future<UserModel?> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      print('🔐 Attempting login for: $email');

      // Get user
      final user = await _storage.getUserByEmail(email);
      if (user == null) {
        print('❌ User not found: $email');
        throw Exception('Invalid email or password');
      }

      print('✓ User found: ${user.name}');

      // Verify password
      final passwordHash = _hashPassword(password);
      print('🔑 Checking password hash...');
      final isValid = await _storage.verifyCredentials(email, passwordHash);

      if (!isValid) {
        print('❌ Password verification failed');
        throw Exception('Invalid email or password');
      }

      print('✓ Password verified successfully');

      // Update last login
      await _storage.updateUser(user.uid, {
        'lastLogin': DateTime.now().toIso8601String(),
      });

      // Set as current user
      await _storage.setCurrentUser(user.uid);

      print('✅ Login successful for: ${user.email}');

      return user;
    } catch (e) {
      print('❌ Login error: $e');
      if (e.toString().contains('Invalid email or password')) {
        rethrow;
      }
      throw Exception('Invalid email or password');
    }
  }

  /// Get current user
  Future<UserModel?> getCurrentUser() async {
    final uid = _storage.getCurrentUserId();
    if (uid == null) return null;

    return await _storage.getUser(uid);
  }

  /// Sign out
  Future<void> signOut() async {
    await _storage.clearCurrentUser();
  }

  /// Update user profile (name, school, section) — persists to Hive
  /// Call this from EditProfileScreen to ensure changes survive restarts.
  Future<void> updateUserProfile({
    required String email,
    required String name,
    String? school,
    String? section,
  }) async {
    final user = await _storage.getUserByEmail(email);
    if (user == null) {
      throw Exception('User not found');
    }

    await _storage.updateUser(user.uid, {
      'name': name,
      if (school != null) 'school': school,
      if (section != null) 'section': section,
    });

    print('✅ Profile updated in Hive for: $email');
  }

  /// Update user profile using current logged-in user (no email needed)
  Future<void> updateProfile({
    String? name,
    String? school,
    String? section,
  }) async {
    final uid = _storage.getCurrentUserId();
    if (uid == null) throw Exception('No user logged in');

    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (school != null) updates['school'] = school;
    if (section != null) updates['section'] = section;

    await _storage.updateUser(uid, updates);
  }

  /// Delete account
  Future<void> deleteAccount() async {
    final uid = _storage.getCurrentUserId();
    if (uid == null) throw Exception('No user logged in');

    await _storage.deleteUser(uid);
    await _storage.clearCurrentUser();
  }

  /// Reset password (updates stored hash)
  Future<void> resetPassword(String email, String newPassword) async {
    final user = await _storage.getUserByEmail(email);
    if (user == null) {
      throw Exception('User not found');
    }

    final passwordHash = _hashPassword(newPassword);
    await _storage.saveCredentials(email, passwordHash);
  }
}