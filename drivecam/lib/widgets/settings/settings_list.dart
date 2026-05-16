// settings_list.dart
// Shared settings UI used by both the main Settings screen and the onboarding
// flow. Renders dropdowns for recording/clip preferences and toggle switches
// for boolean settings (audio, dark mode). All state is owned by the providers
// passed in — this widget is purely presentational.

import 'package:drivecam/provider/settings_provider.dart';
import 'package:drivecam/provider/theme_provider.dart';
import 'package:drivecam/widgets/settings/setting_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../analytics/analytics_controller.dart';

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
    final analytics = context.read<AnalyticsController>();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text("Recording", style: TextStyle(fontSize: 22)),
        SettingDropdown(
          label: 'Framerate',
          value: settingsProvider.framerate,
          options: SettingsProvider.framerateOptions,
          onChanged: (value) {
            settingsProvider.setFramerate(value);
            analytics.trackSettingChanged(
              settings: settingsProvider,
              settingName: 'framerate',
              value: value,
            );
          },
        ),
        SettingDropdown(
          label: 'Quality',
          value: settingsProvider.quality,
          options: SettingsProvider.qualityOptions,
          onChanged: (value) {
            settingsProvider.setQuality(value);
            analytics.trackSettingChanged(
              settings: settingsProvider,
              settingName: 'quality',
              value: value,
            );
          },
        ),
        SettingDropdown(
          label: 'Rolling Footage Limit',
          value: settingsProvider.footageLimit,
          options: SettingsProvider.footageLimitOptions,
          onChanged: (value) {
            settingsProvider.setFootageLimit(value);
            analytics.trackSettingChanged(
              settings: settingsProvider,
              settingName: 'rolling_footage_limit',
              value: value,
            );
          },
        ),
        SettingDropdown(
          label: 'Footage Storage Limit',
          value: settingsProvider.storageLimit,
          options: SettingsProvider.storageLimitOptions,
          onChanged: (value) {
            settingsProvider.setStorageLimit(value);
            analytics.trackSettingChanged(
              settings: settingsProvider,
              settingName: 'footage_storage_limit',
              value: value,
            );
          },
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("Audio", style: Theme.of(context).textTheme.bodyLarge),
            Switch(
              value: settingsProvider.audioEnabled,
              onChanged: (value) {
                settingsProvider.setAudioEnabled(value);
                analytics.trackSettingChanged(
                  settings: settingsProvider,
                  settingName: 'audio_enabled',
                  value: value,
                );
              },
            ),
          ],
        ),

        Divider(),

        Text("Clipping", style: TextStyle(fontSize: 22)),
        SettingDropdown(
          label: 'Clip Pre-Duration',
          value: settingsProvider.preDurationLength,
          options: SettingsProvider.clipDurationOptions,
          onChanged: (value) {
            settingsProvider.setPreDurationLength(value);
            analytics.trackSettingChanged(
              settings: settingsProvider,
              settingName: 'clip_pre_duration',
              value: value,
            );
          },
        ),
        SettingDropdown(
          label: 'Clip Post-Duration',
          value: settingsProvider.postDurationLength,
          options: SettingsProvider.clipDurationOptions,
          onChanged: (value) {
            settingsProvider.setPostDurationLength(value);
            analytics.trackSettingChanged(
              settings: settingsProvider,
              settingName: 'clip_post_duration',
              value: value,
            );
          },
        ),
        SettingDropdown(
          label: 'Clip Storage Limit',
          value: settingsProvider.clipStorageLimit,
          options: SettingsProvider.clipStorageLimitOptions,
          onChanged: (value) {
            settingsProvider.setClipStorageLimit(value);
            analytics.trackSettingChanged(
              settings: settingsProvider,
              settingName: 'clip_storage_limit',
              value: value,
            );
          },
        ),

        Divider(),

        Text("Privacy & Analytics", style: TextStyle(fontSize: 22)),
        Text(
          'Help improve DriveCam on Android and iOS by sharing anonymous usage metrics like session activity, recording activity, clip saves, and the settings you use most often. This stays off unless you opt in.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  "Share Anonymous Usage Metrics",
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            ),
            Switch(
              value: settingsProvider.analyticsEnabled,
              onChanged: (value) async {
                settingsProvider.setAnalyticsEnabled(value);
                await analytics.setConsent(
                  value,
                  settings: settingsProvider,
                );
              },
            ),
          ],
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
