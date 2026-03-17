import 'package:drivecam/provider/settings_provider.dart';
import 'package:drivecam/provider/theme_provider.dart';
import 'package:drivecam/widgets/setting_dropdown.dart';
import 'package:flutter/material.dart';

class SettingsList extends StatelessWidget {
  const SettingsList({
    super.key,
    required this.settingsProvider,
    required this.isDark,
    required this.themeProvider,
  });

  final SettingsProvider settingsProvider;
  final bool isDark;
  final ThemeProvider themeProvider;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text("Recording", style: TextStyle(fontSize: 22)),
        SettingDropdown(
          label: 'Framerate',
          value: settingsProvider.framerate,
          options: SettingsProvider.framerateOptions,
          onChanged: settingsProvider.setFramerate,
        ),
        SettingDropdown(
          label: 'Quality',
          value: settingsProvider.quality,
          options: SettingsProvider.qualityOptions,
          onChanged: settingsProvider.setQuality,
        ),
        SettingDropdown(
          label: 'Rolling Footage Limit',
          value: settingsProvider.footageLimit,
          options: SettingsProvider.footageLimitOptions,
          onChanged: settingsProvider.setFootageLimit,
        ),
        SettingDropdown(
          label: 'Footage Storage Limit',
          value: settingsProvider.storageLimit,
          options: SettingsProvider.storageLimitOptions,
          onChanged: settingsProvider.setStorageLimit,
        ),

        Divider(),

        Text("Clipping", style: TextStyle(fontSize: 22)),
        SettingDropdown(
          label: 'Clip Pre-Duration',
          value: settingsProvider.preDurationLength,
          options: SettingsProvider.clipDurationOptions,
          onChanged: settingsProvider.setPreDurationLength,
        ),
        SettingDropdown(
          label: 'Clip Post-Duration',
          value: settingsProvider.postDurationLength,
          options: SettingsProvider.clipDurationOptions,
          onChanged: settingsProvider.setPostDurationLength,
        ),
        SettingDropdown(
          label: 'Clip Storage Limit',
          value: settingsProvider.clipStorageLimit,
          options: SettingsProvider.clipStorageLimitOptions,
          onChanged: settingsProvider.setClipStorageLimit,
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
    );
  }
}
