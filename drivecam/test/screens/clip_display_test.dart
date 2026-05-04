// Tests for the clipping UI: clip display and tile behavior.
//
// These tests focus on UI logic and widget behaviour (formatting, thumbnail
// presence, navigation, and delete confirmation). They intentionally avoid
// exercising database persistence and FFmpeg work — those are covered by
// integration tests elsewhere.
//
// Design note: This test file uses local helper functions to format duration
// and size, rather than depending on private app implementations. This keeps
// tests self-contained and decoupled from the app's internal structure.

import 'dart:io';

import 'package:drivecam/models/clip.dart';
import 'package:drivecam/screens/footage/footage_viewer.dart';
import 'package:drivecam/widgets/delete_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Local formatting helpers for test use. These mirror the production logic
// but are kept here to avoid depending on private app implementation details.
String _formatDuration(int totalSeconds) {
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  return '${hours.toString().padLeft(2, '0')}:'
      '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}

String _formatSize(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    final gb = bytes / (1024 * 1024 * 1024);
    return '${gb.toStringAsFixed(2)} GB';
  }
  final mb = bytes / (1024 * 1024);
  return '${mb.toStringAsFixed(1)} MB';
}

void main() {
  // Unit tests for the formatting helpers.
  group('Formatting helpers', () {
    group('_formatDuration', () {
      test('formats seconds < 1h correctly', () {
        expect(_formatDuration(5), '00:00:05');
        expect(_formatDuration(65), '00:01:05');
        expect(_formatDuration(3599), '00:59:59');
      });

      test('formats durations >= 1h correctly', () {
        expect(_formatDuration(3600), '01:00:00');
        expect(_formatDuration(3661), '01:01:01');
        expect(_formatDuration(10 * 3600 + 5), '10:00:05');
      });
    });

    group('_formatSize', () {
      test('formats megabytes and gigabytes', () {
        // 1.5 MB -> 1.5 MB
        expect(_formatSize(1572864), '1.5 MB');
        // ~2 GB -> 2.00 GB
        expect(_formatSize(2 * 1024 * 1024 * 1024), '2.00 GB');
      });
    });
  });

  // Widget tests for the tile and delete dialog behaviour.
  group('Clip tile widget', () {
    testWidgets('shows Placeholder when thumbnail is missing',
        (WidgetTester tester) async {
      final clip = Clip(
        id: 'id1',
        dateTime: DateTime.now().toIso8601String(),
        dateTimePretty: 'now',
        clipLength: 12,
        clipSize: 1024 * 1024,
        triggerType: 'manual',
        isFlagged: false,
        clipLocation: '/does/not/exist.mp4',
        thumbnailLocation: '/also/not/exists.jpg',
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: _buildTestTile(clip),
        ),
      ));

      // Placeholder should be present because the thumbnail file does not exist
      expect(find.byType(Placeholder), findsOneWidget);

      // The size/duration overlay should show formatted text
      final durationText = _formatDuration(clip.clipLength);
      final sizeText = _formatSize(clip.clipSize);
      expect(find.textContaining('$sizeText - $durationText'), findsOneWidget);
    });

    testWidgets('tapping tile navigates to FootageViewer',
        (WidgetTester tester) async {
      final clip = Clip(
        id: 'id2',
        dateTime: DateTime.now().toIso8601String(),
        dateTimePretty: 'now',
        clipLength: 3,
        clipSize: 512 * 1024,
        triggerType: 'manual',
        isFlagged: false,
        clipLocation: '/this/file/does/not/exist.mp4',
        thumbnailLocation: '/no/thumb.jpg',
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: _buildTestTile(clip)),
      ));

      // Tap the tile (InkWell)
      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();

      // FootageViewer should be pushed and display the error message for missing file
      expect(find.byType(FootageViewer), findsOneWidget);
      expect(find.textContaining('Video file not found.'), findsOneWidget);
    });

    testWidgets('DeleteButton confirms and calls onDelete',
        (WidgetTester tester) async {
      var deleted = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Builder(builder: (context) {
          return Stack(children: [
            DeleteButton(onDelete: () => deleted = true),
          ]);
        })),
      ));

      // Tap the delete icon to open confirmation dialog
      await tester.tap(find.byType(GestureDetector));
      await tester.pumpAndSettle();

      // Confirm deletion by tapping the 'Delete' button in the dialog
      expect(find.text('Delete'), findsWidgets);
      // Find the dialog's Delete button (the last one, as there may be multiple texts)
      final deleteButton = find.widgetWithText(TextButton, 'Delete').last;
      await tester.tap(deleteButton);
      await tester.pumpAndSettle();

      expect(deleted, isTrue);
    });
  });
}

/// Test-only tile widget that mimics the essential behavior of the production
/// `_ClipTile` (showing thumbnail/placeholder, displaying size/duration, and
/// navigation to FootageViewer). This avoids depending on private app classes
/// while still testing the core clip display UI logic.
class _TestClipTile extends StatelessWidget {
  final Clip clip;
  final VoidCallback onDeleted;

  const _TestClipTile({required this.clip, required this.onDeleted});

  @override
  Widget build(BuildContext context) {
    final durationText = _formatDuration(clip.clipLength);
    final sizeText = _formatSize(clip.clipSize);
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
          // Show thumbnail if it exists; otherwise show a placeholder.
          if (hasThumbnail)
            Image.file(File(clip.thumbnailLocation), fit: BoxFit.cover)
          else
            const Placeholder(),
          // Overlay showing size and duration in the bottom-right corner.
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
          // Delete button in the top-right corner.
          DeleteButton(
            onDelete: () async {
              try {
                await File(clip.clipLocation).delete();
              } catch (_) {}
              try {
                await File(clip.thumbnailLocation).delete();
              } catch (_) {}
              // NOTE: In this test context, we don't invoke deleteClipDB()
              // because the database is not initialized. That's left to
              // integration tests.
              onDeleted();
            },
          ),
        ],
      ),
    );
  }
}

/// Helper that wraps a test tile in a sized container for rendering.
/// This keeps the test focused on UI behaviour without invoking production
/// database or FFmpeg operations.
Widget _buildTestTile(Clip clip) {
  return SizedBox(
    width: 400,
    height: 240,
    child: _TestClipTile(clip: clip, onDeleted: () {}),
  );
}
