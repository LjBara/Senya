import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import 'local_auth_service.dart';
import 'local_storage_service.dart';

/// **Debug / profile only.** Creates or signs in a fixed local student so you can skip
/// the register/login flow on every `flutter run`.
///
/// Uses a real `@gmail.com` address so it matches the app's login validation if you
/// ever sign out and use the normal login screen.
///
/// **Release builds:** always returns `null` (no auto-login).
class DevStudentBootstrap {
  static const String devEmail = 'dev.student.senyamatika@gmail.com';
  static const String devPassword = 'SenyaDevStudent1';
  static const String devName = 'Dev Student';
  static const String devSchool = 'Local Dev School';
  static const String devSection = 'Grade 1 - Dev';

  static final LocalAuthService _auth = LocalAuthService();
  static final LocalStorageService _storage = LocalStorageService();

  /// Returns the signed-in [UserModel] in debug/profile, or `null` in release / on failure.
  static Future<UserModel?> ensureDebugStudent() async {
    if (kReleaseMode) return null;

    try {
      UserModel? user = await _storage.getUserByEmail(devEmail);
      if (user == null) {
        user = await _auth.registerWithEmail(
          email: devEmail,
          password: devPassword,
          name: devName,
          school: devSchool,
          section: devSection,
        );
        debugPrint('🔧 DevStudentBootstrap: registered $devEmail');
      } else {
        user = await _auth.signInWithEmail(
          email: devEmail,
          password: devPassword,
        );
        debugPrint('🔧 DevStudentBootstrap: signed in $devEmail');
      }
      return user;
    } catch (e, st) {
      debugPrint('DevStudentBootstrap failed: $e\n$st');
      return null;
    }
  }
}
