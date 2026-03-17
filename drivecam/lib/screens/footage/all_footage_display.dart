import 'package:drivecam/screens/footage/footage_viewer.dart';
import 'package:drivecam/screens/footage/recording_display.dart';
import 'package:drivecam/widgets/app_bars/app_bar.dart';
import 'package:drivecam/widgets/app_bars/bottom_app_bar.dart';
import 'package:flutter/material.dart';

class AllFootageDisplay extends StatelessWidget {
  const AllFootageDisplay({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const MyAppBar(title: 'Clip Manager'),
      body: Column(
        children: [
          const Center(child: Text('Clips')),
          const Center(child: Text('Recording')),
          InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FootageViewer()),
            ),
            child: const RecordingDisplay(),
          ),
        ],
      ),
      bottomNavigationBar: const MyBottomNavBar(activePage: NavPage.footage),
    );
  }
}
