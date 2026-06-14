import 'package:shared_preferences/shared_preferences.dart';

class AuthStateManager {
  static const String _keyUserEmail = 'user_email';
  static const String _keyUserDisplayName = 'user_display_name';
  static const String _keyAppWhitelistSetupDone = 'app_whitelist_setup_done';

  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUserEmail) != null;
  }

  Future<Map<String, String>?> getStoredUser() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString(_keyUserEmail);
    final displayName = prefs.getString(_keyUserDisplayName);

    if (email == null) return null;

    return {'email': email, 'displayName': displayName ?? 'User'};
  }

  Future<void> saveUser({required String email, required String displayName}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserEmail, email);
    await prefs.setString(_keyUserDisplayName, displayName);
  }

  Future<void> clearUser() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUserEmail);
    await prefs.remove(_keyUserDisplayName);
  }

  Future<bool> isAppWhitelistSetupDone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAppWhitelistSetupDone) ?? false;
  }

  Future<void> markAppWhitelistSetupDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAppWhitelistSetupDone, true);
  }
}
