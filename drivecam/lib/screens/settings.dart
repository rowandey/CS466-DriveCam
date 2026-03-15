import 'package:drivecam/provider/settings_provider.dart';
import 'package:drivecam/provider/theme_provider.dart';
import 'package:drivecam/widgets/app_bar.dart';
import 'package:drivecam/widgets/bottom_app_bar.dart';
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
            options: const ['15 fps', '30 fps', '60 fps'],
            onChanged: settings.setFramerate,
          ),
          SettingDropdown(
            label: 'Quality',
            value: settings.quality,
            options: const ['480p', '720p', '1080p', '1440p'],
            onChanged: settings.setQuality,
          ),
          SettingDropdown(
            label: 'Rolling Footage Limit',
            value: settings.footageLimit,
            options: const [
              '30min',
              '1h',
              '1.5h',
              '2h',
              '3h',
              '4h',
              '5h',
              '6h',
            ],
            onChanged: settings.setFootageLimit,
          ),
          SettingDropdown(
            label: 'Footage Storage Limit',
            value: settings.storageLimit,
            options: const [
              '1GB',
              '2GB',
              '4GB',
              '8GB',
              '12GB',
              '16GB',
              '32GB',
              '64GB',
            ],
            onChanged: settings.setStorageLimit,
          ),

          Divider(),

          Text("Clipping", style: TextStyle(fontSize: 22)),
          SettingDropdown(
            label: 'Clip Pre-Duration',
            value: settings.preDurationLength,
            options: const ['30s', '1m', '2m', '3m', '5m'],
            onChanged: settings.setPreDurationLength,
          ),
          SettingDropdown(
            label: 'Clip Post-Duration',
            value: settings.postDurationLength,
            options: const ['30s', '1m', '2m', '3m', '5m'],
            onChanged: settings.setPostDurationLength,
          ),
          SettingDropdown(
            label: 'Clip Storage Limit',
            value: settings.clipStorageLimit,
            options: const ['1GB', '2GB', '4GB', '6GB', '8GB'],
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
      bottomNavigationBar: const MyBottomNavBar(disableSettings: true),
    );
  }
}
