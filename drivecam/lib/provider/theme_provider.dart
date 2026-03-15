import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  // start with using the system theme for light/dark, but user can change later
  ThemeMode themeMode = ThemeMode.system;

  bool recordingOn = false;

  Color recordButtonColor = const Color(0xFF646464);

  ColorScheme lightColorScheme = const ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF4AB9E7),
    onPrimary: Colors.white,
    secondary: Color(0xFF0072AC),
    onSecondary: Colors.white,
    error: Colors.red,
    onError: Colors.white,
    surface: Colors.white,
    onSurface: Colors.black,
  );

  ColorScheme darkColorScheme = const ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFF0072AC),
    onPrimary: Colors.white,
    secondary: Color(0xFF4AB9E7),
    onSecondary: Colors.white,
    error: Colors.red,
    onError: Colors.white,
    surface: Color(0x33333333), // TODO: make dark mode less, uh, dark (surface value doesn't seem to actually get used)
    onSurface: Colors.white,
  );

  void toggleRecordingButtonColor() {
    recordingOn = !recordingOn;
    recordButtonColor = recordingOn ? const Color(0xFFFF0000) : const Color(0xFF646464);
    notifyListeners();
  }

  Future<void> loadDarkModePrefs() async {
    // load in saved preferences
    final prefs = SharedPreferencesAsync();
    bool? mode = await prefs.getBool("darkMode");
    if (mode != null) {
      setDarkMode(mode);
    }
  }

  void setDarkMode(bool mode) async {
    themeMode = mode ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();

    // save preferences to device
    final prefs = SharedPreferencesAsync();
    await prefs.setBool("darkMode", mode);
  }
}
