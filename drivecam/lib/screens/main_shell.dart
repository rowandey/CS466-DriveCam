import 'package:drivecam/provider/settings_provider.dart';
import 'package:drivecam/screens/home_page.dart';
import 'package:drivecam/screens/onboarding/onboarding.dart';
import 'package:drivecam/widgets/app_bars/bottom_app_bar.dart';
import 'package:drivecam/widgets/recording_indicator.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!context.read<SettingsProvider>().onboardingComplete) {
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const OnboardingScreen()));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [const HomePage(), RecordingIndicator()]),
      bottomNavigationBar: const MyBottomNavBar(),
    );
  }
}
