import 'package:drivecam/widgets/app_bar.dart';
import 'package:drivecam/widgets/bottom_app_bar.dart';
import 'package:flutter/material.dart';

class AllFootageDisplay extends StatelessWidget {
  const AllFootageDisplay({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      appBar: MyAppBar(title: 'Clip Manager'),
      body: Column(
        children: [
          Center(child: Text('Clips')),
          
          Center(child: Text('Recording'))
        ],
      ),
      bottomNavigationBar: MyBottomNavBar(),
    );
  }
}

class RecordingDisplay extends StatelessWidget {
  const RecordingDisplay({super.key});

  @override
  Widget build(BuildContext context) {
    return const Placeholder();
  }
}