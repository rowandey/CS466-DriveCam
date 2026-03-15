import 'package:drivecam/provider/theme_provider.dart';
import 'package:drivecam/widgets/app_bar.dart';
import 'package:drivecam/widgets/bottom_app_bar.dart';
import 'package:drivecam/widgets/setting_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

// TODO: add a warning if a high resolution is selected, there may be temp issues/quickly use storage
class _SettingsScreenState extends State<SettingsScreen> {
  // footage setting values
  String _framerate = '30 fps';
  String _quality = '720p';
  String _footageLimit = '2h';
  String _storageLimit = '8GB';

  // clip setting values
  String _preDurationLength = '2m';
  String _postDurationLength = '2m';
  String _clipStorageLimit = '4GB';

  @override
  Widget build(BuildContext context) {
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
            value: _framerate,
            options: const ['15 fps', '30 fps', '60 fps'],
            onChanged: (v) => setState(() => _framerate = v),
          ),
          SettingDropdown(
            label: 'Quality',
            value: _quality,
            options: const ['480p', '720p', '1080p', '1440p'],
            onChanged: (v) => setState(() => _quality = v),
          ),
          SettingDropdown(
            label: 'Rolling Footage Limit',
            value: _footageLimit,
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
            onChanged: (v) => setState(() => _footageLimit = v),
          ),
          SettingDropdown(
            label: 'Footage Storage Limit',
            value: _storageLimit,
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
            onChanged: (v) => setState(() => _storageLimit = v),
          ),

          Divider(),

          Text("Clipping", style: TextStyle(fontSize: 22)),
          SettingDropdown(
            label: 'Clip Pre-Duration',
            value: _preDurationLength,
            options: const ['30s', '1m', '2m', '3m', '5m'],
            onChanged: (v) => setState(() => _preDurationLength = v),
          ),
          SettingDropdown(
            label: 'Clip Post-Duration',
            value: _postDurationLength,
            options: const ['30s', '1m', '2m', '3m', '5m'],
            onChanged: (v) => setState(() => _postDurationLength = v),
          ),
          SettingDropdown(
            label: 'Clip Storage Limit',
            value: _clipStorageLimit,
            options: const ['1GB', '2GB', '4GB', '6GB', '8GB'],
            onChanged: (v) => setState(() => _clipStorageLimit = v),
          ),

          Divider(),

          Text("Misc", style: TextStyle(fontSize: 22)),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Dark Mode", style: Theme.of(context).textTheme.bodyLarge),
              Switch(
                value: isDark,
                onChanged: (value) => themeProvider.setDarkMode(value),
                thumbColor: WidgetStateProperty.all(Colors.black),
                trackColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return Theme.of(context).colorScheme.primary;
                  }
                  return Theme.of(context).colorScheme.primary;
                }),
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: const MyBottomNavBar(disableSettings: true),
    );
  }
}
