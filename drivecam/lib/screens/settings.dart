import 'package:drivecam/provider/settings_provider.dart';
import 'package:drivecam/provider/theme_provider.dart';
import 'package:drivecam/widgets/app_bars/app_bar.dart';
import 'package:drivecam/widgets/app_bars/bottom_app_bar.dart';
import 'package:drivecam/widgets/setting_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// TODO: add a warning if a high resolution is selected, there may be temp issues/quickly use storage
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final isDark =
        themeProvider.themeMode == ThemeMode.dark ||
        (themeProvider.themeMode == ThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);

    return Scaffold(
      appBar: const MyAppBar(title: 'Settings'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text("Recording", style: TextStyle(fontSize: 22)),
          SettingDropdown(
            label: 'Framerate',
            value: settings.framerate,
            options: SettingsProvider.framerateOptions,
            onChanged: settings.setFramerate,
          ),
          SettingDropdown(
            label: 'Quality',
            value: settings.quality,
            options: SettingsProvider.qualityOptions,
            onChanged: settings.setQuality,
          ),
          SettingDropdown(
            label: 'Rolling Footage Limit',
            value: settings.footageLimit,
            options: SettingsProvider.footageLimitOptions,
            onChanged: settings.setFootageLimit,
          ),
          SettingDropdown(
            label: 'Footage Storage Limit',
            value: settings.storageLimit,
            options: SettingsProvider.storageLimitOptions,
            onChanged: settings.setStorageLimit,
          ),

          Divider(),

          Text("Clipping", style: TextStyle(fontSize: 22)),
          SettingDropdown(
            label: 'Clip Pre-Duration',
            value: settings.preDurationLength,
            options: SettingsProvider.clipDurationOptions,
            onChanged: settings.setPreDurationLength,
          ),
          SettingDropdown(
            label: 'Clip Post-Duration',
            value: settings.postDurationLength,
            options: SettingsProvider.clipDurationOptions,
            onChanged: settings.setPostDurationLength,
          ),
          SettingDropdown(
            label: 'Clip Storage Limit',
            value: settings.clipStorageLimit,
            options: SettingsProvider.clipStorageLimitOptions,
            onChanged: settings.setClipStorageLimit,
          ),

          Divider(),

          Text("Misc", style: TextStyle(fontSize: 22)),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Dark Mode", style: Theme.of(context).textTheme.bodyLarge),
              // TODO: update switch themeing to work with darkmode
              Switch(
                value: isDark,
                onChanged: (value) => themeProvider.setDarkMode(value),
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: const MyBottomNavBar(activePage: NavPage.settings),
    );
  }
}
