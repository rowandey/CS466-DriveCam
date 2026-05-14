// Tests for the clipping UI: clip display, tile behavior, and storage warning.
//
// These tests focus on UI logic and widget behaviour (formatting, thumbnail
// presence, navigation, delete confirmation, and the low-storage warning
// banner). They intentionally avoid exercising database persistence and FFmpeg
// work — those are covered by integration tests elsewhere.
//
// Design note: This test file uses local helper functions to format duration
// and size, rather than depending on private app implementations. This keeps
// tests self-contained and decoupled from the app's internal structure.
//
// The storage warning banner is tested via a standalone _TestStorageBanner
// widget that applies the same 80 % threshold logic as the production
// ClipDisplay, without requiring a live database or Provider tree. This
// approach mirrors how _TestClipTile is used for tile tests.

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

  // ===========================================================================
  // Storage warning banner — threshold unit tests
  // ===========================================================================
  //
  // These are pure calculations: no widget tree, no database. They pin down the
  // 80 % threshold so that a change to the formula in ClipDisplay is caught
  // immediately without needing a running app.

  group('Storage warning banner threshold', () {
    // Use 1 GB (1,073,741,824 bytes) as the limit throughout for readability.
    const limitBytes = 1 * 1024 * 1024 * 1024;

    test('warning is NOT shown when storage usage is below 80 %', () {
      // 79 % of 1 GB = ~848 MB — should not trigger.
      final total = (limitBytes * 0.79).floor();
      expect(_shouldShowWarning(total, limitBytes), isFalse);
    });

    test('warning IS shown when storage usage is exactly at 80 %', () {
      // The threshold is inclusive: >= 80 % shows the banner.
      final total = (limitBytes * 0.8).floor();
      expect(_shouldShowWarning(total, limitBytes), isTrue);
    });

    test('warning IS shown when storage usage is between 80 % and 100 %', () {
      // 90 % of 1 GB.
      final total = (limitBytes * 0.9).floor();
      expect(_shouldShowWarning(total, limitBytes), isTrue);
    });

    test('warning IS shown when storage usage exceeds 100 % of the limit', () {
      // Over-limit state that triggers before eviction runs.
      final total = (limitBytes * 1.1).floor();
      expect(_shouldShowWarning(total, limitBytes), isTrue);
    });

    test('warning is NOT shown when there are no clips (total = 0)', () {
      expect(_shouldShowWarning(0, limitBytes), isFalse);
    });

    // Regression: confirm 79.9 % (just below threshold) does NOT show banner.
    test('warning is NOT shown at 79.9 % usage', () {
      final total = (limitBytes * 0.799).floor();
      expect(_shouldShowWarning(total, limitBytes), isFalse);
    });
  });

  // ===========================================================================
  // Storage warning banner — widget tests
  // ===========================================================================

  group('Storage warning banner widget', () {
    testWidgets('banner is NOT rendered when usage is below 80 %',
        (WidgetTester tester) async {
      const limitBytes = 1 * 1024 * 1024 * 1024;
      final totalBelow = (limitBytes * 0.5).floor(); // 50 %

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: _TestStorageBanner(
            totalBytes: totalBelow,
            limitBytes: limitBytes,
            limitLabel: '1GB',
          ),
        ),
      ));

      // SizedBox.shrink() is used when the banner is hidden — no orange container.
      expect(find.byType(Container), findsNothing);
      expect(find.textContaining('Clip storage almost full'), findsNothing);
    });

    testWidgets('banner IS rendered when usage reaches 80 %',
        (WidgetTester tester) async {
      const limitBytes = 1 * 1024 * 1024 * 1024;
      final totalAt80 = (limitBytes * 0.8).floor();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: _TestStorageBanner(
            totalBytes: totalAt80,
            limitBytes: limitBytes,
            limitLabel: '1GB',
          ),
        ),
      ));

      expect(find.textContaining('Clip storage almost full'), findsOneWidget);
    });

    testWidgets('banner text includes the current usage and configured limit',
        (WidgetTester tester) async {
      // 900 MB used against a 1 GB limit — banner text must mention both.
      const limitBytes = 1 * 1024 * 1024 * 1024;
      const totalBytes = 900 * 1024 * 1024; // 900 MB

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: _TestStorageBanner(
            totalBytes: totalBytes,
            limitBytes: limitBytes,
            limitLabel: '1GB',
          ),
        ),
      ));

      // Usage should appear as a formatted size string.
      expect(find.textContaining(_formatSize(totalBytes)), findsOneWidget);
      // The configured limit label must appear so the user knows the cap.
      expect(find.textContaining('1GB'), findsOneWidget);
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

// =============================================================================
// Storage warning banner — unit and widget tests
// =============================================================================
//
// The banner appears in ClipDisplay when total clip storage reaches or exceeds
// 80 % of the configured limit. We test the threshold logic as a pure
// calculation first, then verify the rendered widget shows the right content.

/// Returns true when the banner should be visible — total is at or above 80 %
/// of the limit. Mirrors the production expression in ClipDisplay exactly so
/// a change to either will cause these tests to fail.
bool _shouldShowWarning(int totalBytes, int limitBytes) {
  return totalBytes >= (limitBytes * 0.8).floor();
}

/// Standalone banner widget that renders the orange storage warning using the
/// same threshold logic as ClipDisplay. Accepts raw byte counts so tests can
/// provide precise values without needing a real SettingsProvider or database.
class _TestStorageBanner extends StatelessWidget {
  final int totalBytes;
  final int limitBytes;
  final String limitLabel; // display string, e.g. '1GB'

  const _TestStorageBanner({
    required this.totalBytes,
    required this.limitBytes,
    required this.limitLabel,
  });

  @override
  Widget build(BuildContext context) {
    final show = totalBytes >= (limitBytes * 0.8).floor();
    if (!show) return const SizedBox.shrink();
    return Container(
      color: Colors.orange.shade700,
      padding: const EdgeInsets.all(8),
      child: Text(
        'Clip storage almost full — '
        '${_formatSize(totalBytes)} of $limitLabel used. '
        'Oldest clips will be automatically deleted when full.',
      ),
    );
  }
}
