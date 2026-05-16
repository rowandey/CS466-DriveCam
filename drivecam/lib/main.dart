// App entry point that wires providers, persistence, and optional analytics.
// Analytics is only enabled for Android and iOS builds, and only after the
// user explicitly opts in.
import 'package:drivecam/analytics/analytics_client.dart';
import 'package:drivecam/analytics/analytics_config.dart';
import 'package:drivecam/analytics/analytics_controller.dart';
import 'package:drivecam/database/database_helper.dart';
import 'package:drivecam/provider/clip_provider.dart';
import 'package:drivecam/provider/recording_provider.dart';
import 'package:drivecam/provider/settings_provider.dart';
import 'package:drivecam/provider/theme_provider.dart';
import 'package:drivecam/screens/main_shell.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final themeProvider = ThemeProvider();
  final settingsProvider = SettingsProvider();
  await Future.wait([
    themeProvider.loadDarkModePrefs(),
    settingsProvider.loadPrefs(),
    DatabaseHelper().database, // init the db
  ]);

  final analyticsClient =
      _supportsAnalyticsOnCurrentPlatform() && amplitudeApiKey.trim().isNotEmpty
      ? AmplitudeAnalyticsClient(amplitudeApiKey)
      : const NoopAnalyticsClient();
  final analyticsController = AnalyticsController(analyticsClient);
  await analyticsController.initialize(
    consentGranted: settingsProvider.analyticsEnabled,
    settings: settingsProvider,
  );

  final recordingProvider = RecordingProvider(analyticsController);
  final clipProvider = ClipProvider(recordingProvider, analyticsController);
  recordingProvider.onRecordingSaved = clipProvider.processPendingClip;

  runApp(
    MultiProvider(
      providers: [
        Provider.value(value: analyticsController),
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProvider.value(value: settingsProvider),
        ChangeNotifierProvider.value(value: recordingProvider),
        ChangeNotifierProvider.value(value: clipProvider),
      ],
      child: const MainApp(),
    ),
  );
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeMode = context.select<ThemeProvider, ThemeMode>((p) => p.themeMode);
    final themeProvider = context.read<ThemeProvider>();
    return MaterialApp(
      theme: ThemeData(colorScheme: themeProvider.lightColorScheme),
      darkTheme: ThemeData(colorScheme: themeProvider.darkColorScheme),
      themeMode: themeMode,
      home: const MainShell(),
    );
  }
}

// Returns true only for the mobile platforms this app is approved to track.
bool _supportsAnalyticsOnCurrentPlatform() {
  if (kIsWeb) return false;

  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}
