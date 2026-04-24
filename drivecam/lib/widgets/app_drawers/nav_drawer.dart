import 'package:drivecam/screens/footage/all_footage_display.dart';
import 'package:drivecam/screens/privacy_page.dart';
import 'package:drivecam/screens/settings.dart';
import 'package:flutter/material.dart';

/// Navigation drawer widget that provides access to the main app screens.
/// 
/// This widget displays a list of navigation options (Camera, Clips, and Settings)
/// that allow users to navigate between the home screen (camera view), clips manager,
/// and settings screen. Each navigation option closes the drawer and navigates to
/// the appropriate screen.
class NavDrawer extends StatelessWidget {
  const NavDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        children: [
          // Camera option - navigates back to the home page (camera view) by popping
          // back to the root MainShell which contains the camera. This avoids creating
          // a duplicate HomePage instance which would cause navigation conflicts.
          ListTile(
            leading: const Icon(Icons.camera),
            title: const Text('Camera'),
            onTap: () {
              Navigator.of(context).pop();
              // Pop back to root (MainShell) if not already there
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
          ),
          // Clips option - navigates to the clips manager and footage display screen.
          ListTile(
            leading: const Icon(Icons.video_collection),
            title: const Text('Clips'),
            onTap: () {
              Navigator.of(context).pop();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AllFootageDisplay()),
              );
            },
          ),
          // Settings option - navigates to the settings configuration screen.
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('Settings'),
            onTap: () {
              Navigator.of(context).pop();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
          // Privacy Page option - navigates to transparency details about
          // what data the app collects, does not collect, and does not share.
          ListTile(
            leading: const Icon(Icons.privacy_tip),
            title: const Text('Privacy Page'),
            onTap: () {
              Navigator.of(context).pop();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PrivacyPageScreen()),
              );
            },
          ),
        ],
      ),
    );
  }
}
