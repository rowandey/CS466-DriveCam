import 'package:drivecam/provider/settings_provider.dart';
import 'package:drivecam/provider/theme_provider.dart';
import 'package:drivecam/widgets/app_bars/app_bar.dart';
import 'package:drivecam/widgets/app_bars/bottom_app_bar.dart';
import 'package:drivecam/widgets/settings_list.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// TODO: add a warning if a high resolution is selected, there may be temp issues/quickly use storage
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsProvider = context.watch<SettingsProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final isDark =
        themeProvider.themeMode == ThemeMode.dark ||
        (themeProvider.themeMode == ThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);

    return Scaffold(
      appBar: const MyAppBar(title: 'Settings'),
      body: SettingsList(settingsProvider: settingsProvider, isDark: isDark, themeProvider: themeProvider),
      bottomNavigationBar: const MyBottomNavBar(activePage: NavPage.settings),
    );
  }
}
