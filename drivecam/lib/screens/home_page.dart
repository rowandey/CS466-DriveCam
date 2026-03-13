import 'package:camera/camera.dart';
import 'package:drivecam/provider/theme_provider.dart';
import 'package:drivecam/widgets/camera_preview.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class HomePage extends StatefulWidget {
  final CameraDescription camera;
  const HomePage({super.key, required this.camera});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    context.read<ThemeProvider>().loadDarkModePrefs();
  }

  @override
  Widget build(BuildContext context) {
    return CameraView(camera: widget.camera);
  }
}
