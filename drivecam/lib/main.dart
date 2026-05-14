import 'package:drivecam/database/database_helper.dart';
import 'package:drivecam/provider/clip_provider.dart';
import 'package:drivecam/provider/recording_provider.dart';
import 'package:drivecam/provider/settings_provider.dart';
import 'package:drivecam/provider/theme_provider.dart';
import 'package:drivecam/screens/main_shell.dart';
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

  // RecordingProvider needs SettingsProvider to read footage time and storage
  // limits during rolling-buffer eviction without going through the widget tree.
  final recordingProvider = RecordingProvider(settingsProvider);
  final clipProvider = ClipProvider(recordingProvider);
  recordingProvider.onRecordingSaved = clipProvider.processPendingClip;

  runApp(
    MultiProvider(
      providers: [
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
