import 'package:camera/camera.dart';
import 'package:drivecam/database/database_helper.dart';
import 'package:drivecam/screens/home_page.dart';
import 'package:drivecam/widgets/bottom_app_bar.dart';
import 'package:drivecam/provider/recording_provider.dart';
import 'package:drivecam/provider/settings_provider.dart';
import 'package:drivecam/provider/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// general todos
// TODO1: Disable camera if a seperate screen is navigated to and a recording is NOT active
// TODO2 - DONE: Force use of a specific color, rather than the general hue
// TODO3 - DONE: Set up SQL structure
// TODO4: Fix dark mode
// TODO5: Make clip screen
// TODO6 - DONE: Setup recording capability
// TODO7: Be able to take a clip on the fly
// TODO8: Be able to make a clip from the main recording
// TODO9: Be able to edit a clip (should probably use the same system that TODO8 uses)
// TODO10: Add footage viewer
// TODO11: Add dynamic screen adaption (rotation, etc)


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
        body: HomePage(camera: camera),
        bottomNavigationBar: const MyBottomNavBar(),
      ),
    );
  }
}
