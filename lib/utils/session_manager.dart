import 'package:shared_preferences/shared_preferences.dart';

class SessionManager {
  static const String _kUserId = 'user_id';
  static const String _kUserRole = 'user_role';

  static Future<void> setUserId(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUserId, userId);
  }

  static Future<void> setUserRole(String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUserRole, role);
  }

  static Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kUserId);
  }

  static Future<String?> getUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kUserRole);
  }

  static Future<bool> isUserLoggedIn() async {
    final userId = await getUserId();
    return userId != null && userId.isNotEmpty;
  }

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kUserId);
    await prefs.remove(_kUserRole);
  }

  static Future<void> saveUser(String id, String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUserId, id);
    await prefs.setString(_kUserRole, role);
  }
}
