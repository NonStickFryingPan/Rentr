import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const String _keyDefaultEditCode = 'default_edit_code';
  static SharedPreferences? _prefs;

  // Initialize SharedPreferences instance
  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // Get default edit code
  static String getDefaultEditCode() {
    return _prefs?.getString(_keyDefaultEditCode) ?? '';
  }

  // Save default edit code
  static Future<void> setDefaultEditCode(String code) async {
    await _prefs?.setString(_keyDefaultEditCode, code);
  }
}
