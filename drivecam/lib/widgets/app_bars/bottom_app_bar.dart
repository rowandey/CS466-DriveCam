import 'package:drivecam/screens/footage/all_footage_display.dart';
import 'package:drivecam/screens/settings.dart';
import 'package:drivecam/widgets/recording_button.dart';
import 'package:flutter/material.dart';

enum NavPage { footage, settings }

class MyBottomNavBar extends StatelessWidget {
  final NavPage? activePage;
  const MyBottomNavBar({super.key, this.activePage});

  @override
  Widget build(BuildContext context) {
    return BottomAppBar(
      color: Theme.of(context).colorScheme.primary,
      child: Row(
        spacing: 56,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.video_collection_rounded),
            onPressed: activePage == NavPage.footage
                ? () => Navigator.pop(context)
                : () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AllFootageDisplay()),
                    ),
          ),
          const RecordingButton(),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: activePage == NavPage.settings
                ? () => Navigator.pop(context)
                : () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    ),
          ),
        ],
      ),
    );
  }
}
