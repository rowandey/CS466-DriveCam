import 'package:flutter/material.dart';

class MyAppBar extends StatelessWidget implements PreferredSizeWidget {
  const MyAppBar({super.key, required this.title});

  final String title;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    // Wrap AppBar with Padding to add top spacing and avoid overlaying system status bar icons
    return SafeArea(
      minimum: EdgeInsets.only(top: 8.0),
      child: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        title: Text(title),
        actions: [
          IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openEndDrawer(),
          ),
        ],
      ),
    );
  }
}
