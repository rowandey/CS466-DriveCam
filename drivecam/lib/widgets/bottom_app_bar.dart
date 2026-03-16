import 'package:drivecam/screens/all_footage_display.dart';
import 'package:drivecam/screens/settings.dart';
import 'package:drivecam/widgets/recording_button.dart';
import 'package:flutter/material.dart';

class MyBottomNavBar extends StatelessWidget {
  final bool disableSettings;
  const MyBottomNavBar({super.key, this.disableSettings = false});

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
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AllFootageDisplay()),
            ),
          ),
          const RecordingButton(),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: disableSettings
                ? null
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
