import 'dart:async';

import 'package:drivecam/provider/clip_provider.dart';
import 'package:drivecam/provider/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ClipSavedNotification extends StatefulWidget {
  const ClipSavedNotification({super.key});

  @override
  State<ClipSavedNotification> createState() => _ClipSavedNotificationState();
}

class _ClipSavedNotificationState extends State<ClipSavedNotification> {
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _ensureTimer(bool inProgress) {
    if (inProgress && _timer == null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() {});
      });
    } else if (!inProgress && _timer != null) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ClipProvider>(
      builder: (context, clip, _) {
        _ensureTimer(clip.clipInProgress);

        if (clip.clipInProgress && clip.clipProgressEndTime != null) {
          final remaining = clip.clipProgressEndTime!
              .difference(DateTime.now())
              .inSeconds
              .clamp(0, 9999);
          return _Pill(
            color: Colors.orange,
            text: 'Clip in progress $remaining',
          );
        }

        if (clip.clipSaved) {
          final green = context.read<ThemeProvider>().clipSavedColor;
          return _Pill(
            color: green,
            text: 'Clip Saved',
            onTap: clip.dismissClipNotification,
          );
        }

        return const SizedBox.shrink();
      },
    );
  }
}

class _Pill extends StatelessWidget {
  final Color color;
  final String text;
  final VoidCallback? onTap;

  const _Pill({required this.color, required this.text, this.onTap});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 12, top: 52),
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
