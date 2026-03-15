import 'package:camera/camera.dart';
import 'package:drivecam/screens/home_page.dart';
import 'package:drivecam/widgets/bottom_app_bar.dart';
import 'package:drivecam/provider/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// general todos
// TODO1: Disable camera if a seperate screen is navigated to and a recording is NOT active
// TODO2: Force use of a specific color, rather than the general hue
// TODO3: Figure out datastructure

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final cameras = await availableCameras();
  final firstCamera = cameras.first;

  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (context) => ThemeProvider())],
      child: MainApp(camera: firstCamera),
    ),
  );
}

class MainApp extends StatelessWidget {
  final CameraDescription camera;
  const MainApp({super.key, required this.camera});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    return MaterialApp(
      theme: ThemeData(colorScheme: themeProvider.lightColorScheme),
      darkTheme: ThemeData(colorScheme: themeProvider.darkColorScheme),
      themeMode: themeProvider.themeMode,
      home: Scaffold(
        body: HomePage(camera: camera),
        bottomNavigationBar: const MyBottomNavBar(),
      ),
    );
  }
}
