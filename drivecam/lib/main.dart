import 'package:camera/camera.dart';
import 'package:drivecam/screens/home_page.dart';
import 'package:drivecam/widgets/bottom_app_bar.dart';
import 'package:drivecam/provider/settings_provider.dart';
import 'package:drivecam/provider/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// general todos
// TODO1: Disable camera if a seperate screen is navigated to and a recording is NOT active
// TODO2 - DONE: Force use of a specific color, rather than the general hue
// TODO3: Set up SQL structure
// TODO4: Fix dark mode
// TODO5: Make clip screen


void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final cameras = await availableCameras();
  final firstCamera = cameras.first;

  final themeProvider = ThemeProvider();
  final settingsProvider = SettingsProvider();
  await Future.wait([
    themeProvider.loadDarkModePrefs(),
    settingsProvider.loadPrefs(),
  ]);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProvider.value(value: settingsProvider),
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
