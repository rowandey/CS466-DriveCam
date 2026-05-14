// Displays the grid of saved clips and a low-storage warning banner.
//
// The grid is refreshed automatically whenever a clip is saved (via
// ClipProvider.clipSaved) or manually deleted. When the total clip storage
// reaches or exceeds 80 % of the configured limit an orange banner is shown
// at the top of the section so the user knows oldest clips will soon be
// auto-deleted.
import 'dart:io';
import 'package:drivecam/models/clip.dart';
import 'package:drivecam/screens/footage/footage_viewer.dart';
import 'package:drivecam/widgets/delete_button.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../provider/clip_provider.dart';
import '../../provider/settings_provider.dart';

class ClipDisplay extends StatefulWidget {
  const ClipDisplay({super.key});

  @override
  State<ClipDisplay> createState() => _ClipDisplayState();
}

class _ClipDisplayState extends State<ClipDisplay> {
  late Future<List<Clip>> _clipsFuture;

  @override
  void initState() {
    super.initState();
    _clipsFuture = Clip.loadAllClips();
  }

  void _refresh() {
    setState(() {
      _clipsFuture = Clip.loadAllClips();
    });
  }

  static String formatDuration(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  static String formatSize(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      final gb = bytes / (1024 * 1024 * 1024);
      return '${gb.toStringAsFixed(2)} GB';
    }
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ClipProvider>(builder: (context, cp, child) {
      if (cp.clipSaved) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _refresh();
          cp.dismissClipNotification();
        });
      }

      return FutureBuilder<List<Clip>>(
        future: _clipsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final clips = snapshot.data ?? [];
          if (clips.isEmpty) {
            return const Center(child: Text('No clips saved'));
          }

          // Compute total clip storage and decide whether to show the warning.
          // context.watch ensures the banner updates if the user changes the
          // clip storage limit in settings without leaving this screen.
          final settings = context.watch<SettingsProvider>();
          final limitBytes = SettingsProvider.clipStorageLimitToBytes(
              settings.clipStorageLimit);
          final totalBytes =
              clips.fold<int>(0, (sum, c) => sum + c.clipSize);

          // Show the warning when storage is at or above 80 % of the limit.
          final showStorageWarning = totalBytes >= (limitBytes * 0.8).floor();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Orange warning banner shown when clip storage is nearly full.
              // The threshold is 80 % so the user has time to act before
              // automatic eviction begins removing their oldest clips.
              if (showStorageWarning)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade700,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Clip storage almost full — '
                    '${formatSize(totalBytes)} of ${settings.clipStorageLimit} used. '
                    'Oldest clips will be automatically deleted when full.',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 12),
                  ),
                ),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 4,
                  mainAxisSpacing: 4,
                  childAspectRatio: 16 / 9,
                ),
                itemCount: clips.length,
                itemBuilder: (context, index) => _ClipTile(
                  clip: clips[index],
                  onDeleted: _refresh,
                ),
              ),
            ],
          );
        },
      );
  });
  }
}

class _ClipTile extends StatelessWidget {
  final Clip clip;
  final VoidCallback onDeleted;
  const _ClipTile({required this.clip, required this.onDeleted});

  @override
  Widget build(BuildContext context) {
    final durationText = _ClipDisplayState.formatDuration(clip.clipLength);
    final sizeText = _ClipDisplayState.formatSize(clip.clipSize);
    final hasThumbnail = File(clip.thumbnailLocation).existsSync();

    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FootageViewer(
            filePath: clip.clipLocation,
            title: clip.dateTimePretty,
          ),
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasThumbnail)
            Image.file(File(clip.thumbnailLocation), fit: BoxFit.cover)
          else
            const Placeholder(),
          Positioned(
            right: 4,
            bottom: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '$sizeText - $durationText',
                style: const TextStyle(color: Colors.white, fontSize: 10),
              ),
            ),
          ),
          DeleteButton(
            onDelete: () async {
              try {
                await File(clip.clipLocation).delete();
              } catch (_) {}
              try {
                await File(clip.thumbnailLocation).delete();
              } catch (_) {}
              await clip.deleteClipDB();
              onDeleted();
            },
          ),
        ],
      ),
    );
  }
}
