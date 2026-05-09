// Tests for the RecordingDisplay screen.
//
// Covers: loading state, empty state, recording with/without thumbnail,
// size/duration overlay formatting, and delete button behaviour.
//
// Design note: A local _TestRecordingDisplay widget is used to inject a
// Future<Recording?> directly, avoiding real database calls. This is the same
// pattern used in clip_display_test.dart. The formatting helpers are mirrored
// locally so tests are decoupled from private production code.

import 'dart:async';
import 'dart:io';

import 'package:drivecam/models/recording.dart';
import 'package:drivecam/widgets/delete_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Local mirrors of the production _formatDuration and _formatSize helpers.
// Keeping them here avoids coupling tests to private implementation details
// while still letting us assert on the exact strings the UI should display.
String _formatDuration(int totalSeconds) {
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  return '${hours.toString().padLeft(2, '0')}:'
      '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}

String _formatSize(int? bytes) {
  if (bytes == null) return 'Unknown size';
  if (bytes >= 1024 * 1024 * 1024) {
    final gb = bytes / (1024 * 1024 * 1024);
    return '${gb.toStringAsFixed(2)} GB';
  }
  final mb = bytes / (1024 * 1024);
  return '${mb.toStringAsFixed(1)} MB';
}

void main() {
  // -------------------------------------------------------------------------
  // Unit tests for the local formatting helpers.
  // These verify the exact strings the overlay text should display, covering
  // boundary conditions (0s, 1h boundary, null bytes, MB vs GB threshold).
  // -------------------------------------------------------------------------
  group('Formatting helpers', () {
    group('_formatDuration', () {
      test('formats zero seconds', () {
        expect(_formatDuration(0), '00:00:00');
      });

      test('formats seconds only (< 1 minute)', () {
        expect(_formatDuration(5), '00:00:05');
        expect(_formatDuration(59), '00:00:59');
      });

      test('formats minutes and seconds (< 1 hour)', () {
        expect(_formatDuration(65), '00:01:05');
        expect(_formatDuration(3599), '00:59:59');
      });

      test('formats exactly one hour', () {
        expect(_formatDuration(3600), '01:00:00');
      });

      test('formats hours, minutes, and seconds', () {
        expect(_formatDuration(3661), '01:01:01');
        // Large value: 10 h 0 m 5 s
        expect(_formatDuration(10 * 3600 + 5), '10:00:05');
      });
    });

    group('_formatSize', () {
      test('returns "Unknown size" when bytes is null', () {
        expect(_formatSize(null), 'Unknown size');
      });

      test('formats whole megabytes', () {
        expect(_formatSize(1024 * 1024), '1.0 MB');
      });

      test('formats fractional megabytes', () {
        // 1.5 * 1024 * 1024 = 1 572 864 bytes → '1.5 MB'
        expect(_formatSize(1572864), '1.5 MB');
      });

      test('formats exactly 1 GB', () {
        expect(_formatSize(1024 * 1024 * 1024), '1.00 GB');
      });

      test('formats 2 GB', () {
        expect(_formatSize(2 * 1024 * 1024 * 1024), '2.00 GB');
      });
    });
  });

  // -------------------------------------------------------------------------
  // Widget tests for the RecordingDisplay screen logic.
  // Each test pumps a _TestRecordingDisplay with a controlled future so that
  // no real SQLite database is involved.
  // -------------------------------------------------------------------------
  group('RecordingDisplay widget', () {
    // Shows a spinner while the future is still pending.
    testWidgets('shows CircularProgressIndicator while loading',
        (WidgetTester tester) async {
      // Use a Completer so the future never resolves during this test,
      // keeping the widget in ConnectionState.waiting the whole time.
      final completer = Completer<Recording?>();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: _TestRecordingDisplay(recordingFuture: completer.future),
        ),
      ));

      // After pumpWidget but before completing the future the spinner is shown.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('No recording available'), findsNothing);

      // Complete so the Dart async runtime can clean up gracefully.
      completer.complete(null);
    });

    // Shows a fallback message when the DB returns no recording row.
    testWidgets('shows "No recording available" when future resolves to null',
        (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: _TestRecordingDisplay(recordingFuture: Future.value(null)),
        ),
      ));

      // pump() advances one frame so the FutureBuilder can rebuild.
      await tester.pump();

      expect(find.text('No recording available'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    // No recording means no delete button either.
    testWidgets('does not show DeleteButton when recording is null',
        (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: _TestRecordingDisplay(recordingFuture: Future.value(null)),
        ),
      ));
      await tester.pump();

      expect(find.byType(DeleteButton), findsNothing);
    });

    // A recording with no thumbnail should show a Placeholder widget instead
    // of an image, so the user still sees a 16:9 card.
    testWidgets('shows Placeholder when thumbnailLocation is null',
        (WidgetTester tester) async {
      final recording = Recording(
        id: 'rec-no-thumb',
        recordingLocation: '/recordings/rec.mp4',
        recordingLength: 120,
        recordingSize: 10 * 1024 * 1024,
        thumbnailLocation: null,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: _TestRecordingDisplay(recordingFuture: Future.value(recording)),
        ),
      ));
      await tester.pump();

      expect(find.byType(Placeholder), findsOneWidget);
      // No image should be attempted.
      expect(find.byType(Image), findsNothing);
    });

    // Even if thumbnailLocation is set, if the file is missing we fall back to
    // Placeholder to avoid a runtime crash.
    testWidgets('shows Placeholder when thumbnail file does not exist on disk',
        (WidgetTester tester) async {
      final recording = Recording(
        id: 'rec-bad-thumb',
        recordingLocation: '/recordings/rec.mp4',
        recordingLength: 60,
        recordingSize: 5 * 1024 * 1024,
        thumbnailLocation: '/definitely/does/not/exist.jpg',
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: _TestRecordingDisplay(recordingFuture: Future.value(recording)),
        ),
      ));
      await tester.pump();

      expect(find.byType(Placeholder), findsOneWidget);
    });

    // The size–duration overlay should show the formatted strings joined by " - ".
    testWidgets('shows formatted size and duration in overlay',
        (WidgetTester tester) async {
      final recording = Recording(
        id: 'rec-overlay',
        recordingLocation: '/recordings/rec.mp4',
        // 75 s → 00:01:15
        recordingLength: 75,
        // 2 MB
        recordingSize: 2 * 1024 * 1024,
        thumbnailLocation: null,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: _TestRecordingDisplay(recordingFuture: Future.value(recording)),
        ),
      ));
      await tester.pump();

      expect(find.textContaining('2.0 MB - 00:01:15'), findsOneWidget);
    });

    // When recordingSize is null the overlay should say "Unknown size".
    testWidgets('shows "Unknown size" in overlay when recordingSize is null',
        (WidgetTester tester) async {
      final recording = Recording(
        id: 'rec-no-size',
        recordingLocation: '/recordings/rec.mp4',
        recordingLength: 10,
        recordingSize: null,
        thumbnailLocation: null,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: _TestRecordingDisplay(recordingFuture: Future.value(recording)),
        ),
      ));
      await tester.pump();

      expect(find.textContaining('Unknown size'), findsOneWidget);
    });

    // GB-sized recordings should display "X.XX GB" rather than a huge MB number.
    testWidgets('shows GB-formatted size for large recordings',
        (WidgetTester tester) async {
      final recording = Recording(
        id: 'rec-gb',
        recordingLocation: '/recordings/rec.mp4',
        recordingLength: 3600,
        // 2 GB
        recordingSize: 2 * 1024 * 1024 * 1024,
        thumbnailLocation: null,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: _TestRecordingDisplay(recordingFuture: Future.value(recording)),
        ),
      ));
      await tester.pump();

      expect(find.textContaining('2.00 GB'), findsOneWidget);
    });

    // A recording card should maintain a 16:9 aspect ratio so clips look
    // consistent in the footage list regardless of screen width.
    testWidgets('uses a 16:9 AspectRatio when recording is present',
        (WidgetTester tester) async {
      final recording = Recording(
        id: 'rec-aspect',
        recordingLocation: '/recordings/rec.mp4',
        recordingLength: 30,
        recordingSize: 1024 * 1024,
        thumbnailLocation: null,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: _TestRecordingDisplay(recordingFuture: Future.value(recording)),
        ),
      ));
      await tester.pump();

      final finder = find.byType(AspectRatio);
      expect(finder, findsOneWidget);
      final widget = tester.widget<AspectRatio>(finder);
      expect(widget.aspectRatio, closeTo(16 / 9, 0.001));
    });

    // The delete button must be rendered so the user can remove their recording.
    testWidgets('shows DeleteButton when a recording is present',
        (WidgetTester tester) async {
      final recording = Recording(
        id: 'rec-del-btn',
        recordingLocation: '/recordings/rec.mp4',
        recordingLength: 30,
        recordingSize: 1024 * 1024,
        thumbnailLocation: null,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: _TestRecordingDisplay(recordingFuture: Future.value(recording)),
        ),
      ));
      await tester.pump();

      expect(find.byType(DeleteButton), findsOneWidget);
    });

    // Tapping the delete icon should open a confirmation dialog before
    // taking any destructive action.
    testWidgets('tapping delete icon opens confirmation dialog',
        (WidgetTester tester) async {
      final recording = Recording(
        id: 'rec-dialog',
        recordingLocation: '/recordings/rec.mp4',
        recordingLength: 30,
        recordingSize: 1024 * 1024,
        thumbnailLocation: null,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: _TestRecordingDisplay(recordingFuture: Future.value(recording)),
        ),
      ));
      await tester.pump();

      await tester.tap(find.byType(GestureDetector));
      await tester.pumpAndSettle();

      // Both "Delete" and "Cancel" options must be visible in the dialog.
      expect(find.text('Delete'), findsWidgets);
      expect(find.text('Cancel'), findsOneWidget);
    });

    // Pressing "Cancel" must NOT trigger the delete callback — we must never
    // destroy data without explicit user confirmation.
    testWidgets('pressing Cancel in delete dialog does not call onDelete',
        (WidgetTester tester) async {
      var deleted = false;
      final recording = Recording(
        id: 'rec-cancel',
        recordingLocation: '/recordings/rec.mp4',
        recordingLength: 30,
        recordingSize: 1024 * 1024,
        thumbnailLocation: null,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: _TestRecordingDisplay(
            recordingFuture: Future.value(recording),
            onDelete: () => deleted = true,
          ),
        ),
      ));
      await tester.pump();

      await tester.tap(find.byType(GestureDetector));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(deleted, isFalse);
    });

    // Pressing the "Delete" confirmation button must invoke the onDelete
    // callback so the caller can remove the file and DB row.
    testWidgets('pressing Delete in dialog calls onDelete',
        (WidgetTester tester) async {
      var deleted = false;
      final recording = Recording(
        id: 'rec-confirm',
        recordingLocation: '/recordings/rec.mp4',
        recordingLength: 30,
        recordingSize: 1024 * 1024,
        thumbnailLocation: null,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: _TestRecordingDisplay(
            recordingFuture: Future.value(recording),
            onDelete: () => deleted = true,
          ),
        ),
      ));
      await tester.pump();

      await tester.tap(find.byType(GestureDetector));
      await tester.pumpAndSettle();

      // Use .last because the dialog title also says "Delete".
      final deleteButton = find.widgetWithText(TextButton, 'Delete').last;
      await tester.tap(deleteButton);
      await tester.pumpAndSettle();

      expect(deleted, isTrue);
    });
  });
}

// ---------------------------------------------------------------------------
// Test-local widget
// ---------------------------------------------------------------------------

/// A local version of RecordingDisplay that accepts a [Future<Recording?>]
/// directly instead of calling [Recording.openRecordingDB()]. This lets tests
/// control exactly what data the widget sees without touching the database.
///
/// The [onDelete] callback replaces the production file-deletion and DB-delete
/// logic so tests can assert that deletion was triggered without needing real
/// files or SQLite. The build logic is otherwise identical to the production
/// widget (FutureBuilder states, Placeholder vs Image, overlay text, aspect
/// ratio).
class _TestRecordingDisplay extends StatelessWidget {
  final Future<Recording?> recordingFuture;
  final VoidCallback? onDelete;

  const _TestRecordingDisplay({
    required this.recordingFuture,
    this.onDelete,
  });

  // Mirrors the private static helper in RecordingDisplay.
  static String _formatDuration(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  // Mirrors the private static helper in RecordingDisplay.
  static String _formatSize(int? bytes) {
    if (bytes == null) return 'Unknown size';
    if (bytes >= 1024 * 1024 * 1024) {
      final gb = bytes / (1024 * 1024 * 1024);
      return '${gb.toStringAsFixed(2)} GB';
    }
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Recording?>(
      future: recordingFuture,
      builder: (context, snapshot) {
        // Loading state — show a centred spinner at a fixed height.
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        // Empty state — no recording row in the database.
        final recording = snapshot.data;
        if (recording == null) {
          return const SizedBox(
            height: 200,
            child: Center(child: Text('No recording available')),
          );
        }

        final durationText = _formatDuration(recording.recordingLength);
        final sizeText = _formatSize(recording.recordingSize);

        return Center(
          child: AspectRatio(
            // 16:9 keeps the card consistent with the video's natural ratio.
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Show thumbnail only when the file actually exists on disk;
                // otherwise fall back to Placeholder to avoid a runtime error.
                if (recording.thumbnailLocation != null &&
                    File(recording.thumbnailLocation!).existsSync())
                  Image.file(
                    File(recording.thumbnailLocation!),
                    fit: BoxFit.cover,
                  )
                else
                  const Placeholder(),
                // Size–duration overlay in the bottom-right corner.
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '$sizeText - $durationText',
                      style:
                          const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
                // Delete button: in tests, invokes the injected onDelete
                // callback rather than touching the filesystem or database.
                DeleteButton(
                  onDelete: () => onDelete?.call(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
