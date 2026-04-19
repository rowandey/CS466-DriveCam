// theme_provider.dart
// Centralized theme state and color schemes used by MaterialApp.
// Stores and restores the user-selected dark mode preference.
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  // start with using the system theme for light/dark, but user can change later
  ThemeMode themeMode = ThemeMode.system;

  final Color clipSavedColor = const Color(0xFF4CAF50);

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
    // Use an opaque dark surface so popup/dropdown menus are readable.
    surface: Color(0xFF1F1F1F),
    onSurface: Colors.white,
  );

  // Loads the persisted dark mode preference from local storage.
  // Returns a Future that completes after the preference is applied.
  Future<void> loadDarkModePrefs() async {
    // load in saved preferences
    final prefs = SharedPreferencesAsync();
    bool? mode = await prefs.getBool("darkMode");
    if (mode != null) {
      setDarkMode(mode);
    }
  }

  // Updates the app ThemeMode and persists the preference.
  // [mode] true enables dark mode, false enables light mode.
  void setDarkMode(bool mode) async {
    themeMode = mode ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();

    // save preferences to device
    final prefs = SharedPreferencesAsync();
    await prefs.setBool("darkMode", mode);
  }
}
