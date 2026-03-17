import 'package:camera/camera.dart';
import 'package:drivecam/database/database_helper.dart';
import 'package:drivecam/screens/home_page.dart';
import 'package:drivecam/widgets/app_bars/bottom_app_bar.dart';
import 'package:drivecam/provider/recording_provider.dart';
import 'package:drivecam/provider/settings_provider.dart';
import 'package:drivecam/provider/theme_provider.dart';
import 'package:drivecam/widgets/recording_indicator.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final cameras = await availableCameras();
  final firstCamera = cameras.first;

  final themeProvider = ThemeProvider();
  final settingsProvider = SettingsProvider();
  await Future.wait([
    themeProvider.loadDarkModePrefs(),
    settingsProvider.loadPrefs(),
    DatabaseHelper().database, // init the db
  ]);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProvider.value(value: settingsProvider),
        ChangeNotifierProvider(create: (_) => RecordingProvider()),
      ],
      child: MainApp(camera: firstCamera),
    ),
  );
}

class MainApp extends StatelessWidget {
  final CameraDescription camera;
  const MainApp({super.key, required this.camera});

  @override
  Widget build(BuildContext context) {
    final themeMode = context.select<ThemeProvider, ThemeMode>((p) => p.themeMode);
    final themeProvider = context.read<ThemeProvider>();
    return MaterialApp(
      theme: ThemeData(colorScheme: themeProvider.lightColorScheme),
      darkTheme: ThemeData(colorScheme: themeProvider.darkColorScheme),
      themeMode: themeMode,
      home: Scaffold(
        body: Stack(
          children: [
            HomePage(camera: camera),
            RecordingIndicator(),
          ],
        ),
        bottomNavigationBar: const MyBottomNavBar(),
      ),
    );
  }
}
