// Unit tests for RecordingProvider's rolling-buffer eviction logic.

import 'dart:io';

import 'package:drivecam/provider/recording_provider.dart';
import 'package:drivecam/provider/settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  // Use in-memory SharedPreferences so that any SettingsProvider setter that
  // calls SharedPreferencesAsync internally doesn't fail trying to reach the
  // real platform plugin in the unit-test environment.
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  /// Creates a [SettingsProvider] with the given footage time and storage limits.
  ///
  /// [footageLimit] and [storageLimit] accept the same string values that appear
  /// in the settings UI (e.g. '30min', '1GB'). Both default to very large values
  /// so neither accidentally triggers eviction in tests that only care about one
  /// of the two constraints.
  SettingsProvider makeSettings({
    String footageLimit = '6h',   // high default so time won't interfere
    String storageLimit = '64GB', // high default so storage won't interfere
  }) {
    final s = SettingsProvider();
    // Set fields directly rather than calling the async setters, since we only
    // need the in-memory value for eviction checks — no persistence required.
    s.footageLimit = footageLimit;
    s.storageLimit = storageLimit;
    return s;
  }

  // ===========================================================================
  // addSegment — basic accumulation (no eviction expected)
  // ===========================================================================
  group('RecordingProvider.addSegment — accumulation', () {
    // When no bitrate has been set yet, estimatedBytes falls back to 0.
    // This is intentional: the storage limit can never be exceeded if we
    // don't know the bitrate, so it's safer to under-count than over-count.
    test('without a bitrate set, accumulates duration but estimates 0 bytes', () {
      final provider = RecordingProvider(makeSettings());

      provider.addSegment('/fake/seg1.mp4', 120);

      expect(provider.segmentCount, 1);
      expect(provider.totalSegmentDurationSeconds, 120);
      expect(provider.totalSegmentEstimatedBytes, 0);
    });

    // bytes = bitrate_bps × duration_seconds ÷ 8 (bits to bytes conversion).
    // Example: 5 Mbps × 10 s ÷ 8 = 6,250,000 bytes.
    test('with a bitrate set, estimates bytes as bitrate × duration ÷ 8', () {
      final provider = RecordingProvider(makeSettings());
      provider.setVideoBitrate(5000000); // 5 Mbps

      provider.addSegment('/fake/seg1.mp4', 10); // 10 seconds

      // 5,000,000 × 10 ÷ 8 = 6,250,000 bytes
      expect(provider.totalSegmentEstimatedBytes, 6250000);
      expect(provider.totalSegmentDurationSeconds, 10);
    });

    // Calling addSegment multiple times should grow both running totals.
    test('multiple calls accumulate duration and bytes correctly', () {
      final provider = RecordingProvider(makeSettings());
      provider.setVideoBitrate(8000000); // 8 Mbps

      provider.addSegment('/fake/s1.mp4', 300); // 300,000,000 bytes
      provider.addSegment('/fake/s2.mp4', 300);
      provider.addSegment('/fake/s3.mp4', 300);

      expect(provider.segmentCount, 3);
      expect(provider.totalSegmentDurationSeconds, 900);
      // 8,000,000 × 300 ÷ 8 = 300,000,000 per segment; × 3 = 900,000,000
      expect(provider.totalSegmentEstimatedBytes, 900000000);
    });
  });

  // ===========================================================================
  // addSegment — time-limit eviction
  // ===========================================================================
  group('RecordingProvider.addSegment — time-limit eviction', () {
    // When total duration is still under the limit, nothing should be evicted.
    test('no eviction when total duration is within the limit', () {
      // 30min = 1800s. Two 600s segments = 1200s ≤ 1800s — safe.
      final provider = RecordingProvider(makeSettings(footageLimit: '30min'));

      provider.addSegment('/fake/s1.mp4', 600);
      provider.addSegment('/fake/s2.mp4', 600);

      expect(provider.segmentCount, 2);
      expect(provider.totalSegmentDurationSeconds, 1200);
    });

    // When the running total exceeds the limit, the oldest segment is dropped.
    // This mirrors the dashcam rolling-window behaviour: old footage is
    // discarded to make room for newer footage.
    test('evicts the oldest segment once the time limit is exceeded', () {
      // 30min = 1800s. Two 1000s segments → 2000 > 1800 → evict s1 → 1000s.
      final provider = RecordingProvider(makeSettings(footageLimit: '30min'));

      provider.addSegment('/fake/s1.mp4', 1000); // oldest — will be evicted
      provider.addSegment('/fake/s2.mp4', 1000); // triggers eviction of s1

      expect(provider.segmentCount, 1);
      expect(provider.totalSegmentDurationSeconds, 1000);
    });

    // Eviction loops until BOTH constraints are satisfied, so multiple
    // segments may be dropped in a single addSegment call.
    test('evicts multiple oldest segments until within the time limit', () {
      // 30min = 1800s. Three 700s segments → total 2100 > 1800.
      // Evict s1 (oldest) → 1400 ≤ 1800 → stop. s2 and s3 survive.
      final provider = RecordingProvider(makeSettings(footageLimit: '30min'));

      provider.addSegment('/fake/s1.mp4', 700);
      provider.addSegment('/fake/s2.mp4', 700);
      provider.addSegment('/fake/s3.mp4', 700);

      expect(provider.segmentCount, 2);
      expect(provider.totalSegmentDurationSeconds, 1400);
    });

    // The eviction order must be FIFO (oldest-first), not random or newest-first.
    // Dropping the newest segment would defeat the purpose of a rolling buffer.
    test('eviction is FIFO — oldest segments are dropped first', () {
      // Three 1000s segments with a 1800s limit.
      // Adding s3: total 3000 > 1800. Evict s1 → 2000 > 1800. Evict s2 → 1000 ≤ 1800.
      // Only s3 (the newest) should survive.
      final provider = RecordingProvider(makeSettings(footageLimit: '30min'));

      provider.addSegment('/fake/s1.mp4', 1000);
      provider.addSegment('/fake/s2.mp4', 1000);
      provider.addSegment('/fake/s3.mp4', 1000);

      expect(provider.segmentCount, 1);
      expect(provider.totalSegmentDurationSeconds, 1000);
    });

    // After an eviction the running total is correct, so subsequent segments
    // are evaluated against an accurate accumulated duration — not a stale one.
    test('subsequent segments accumulate on top of the evicted-corrected total', () {
      final provider = RecordingProvider(makeSettings(footageLimit: '30min')); // 1800s

      provider.addSegment('/fake/s1.mp4', 1000); // s1 evicted when s2 arrives
      provider.addSegment('/fake/s2.mp4', 1000); // remaining: 1000s
      provider.addSegment('/fake/s3.mp4', 500);  // 1000 + 500 = 1500 ≤ 1800 → no eviction

      expect(provider.segmentCount, 2);
      expect(provider.totalSegmentDurationSeconds, 1500);
    });
  });

  // ===========================================================================
  // addSegment — storage-limit eviction
  // ===========================================================================
  group('RecordingProvider.addSegment — storage-limit eviction', () {
    // No eviction when estimated bytes are still within the storage limit.
    // At 8 Mbps, 300s → 8,000,000 × 300 ÷ 8 = 300,000,000 bytes ≈ 286 MB.
    // Three segments → ~858 MB, which is under 1 GB (1,073,741,824 bytes).
    test('no eviction when total bytes are within the storage limit', () {
      final provider = RecordingProvider(makeSettings(storageLimit: '1GB'));
      provider.setVideoBitrate(8000000);

      provider.addSegment('/fake/s1.mp4', 300);
      provider.addSegment('/fake/s2.mp4', 300);
      provider.addSegment('/fake/s3.mp4', 300);

      expect(provider.segmentCount, 3);
    });

    // A fourth 300s segment at 8 Mbps pushes the total to ~1,200 MB, which
    // exceeds the 1 GB limit. s1 is evicted, bringing the total back to ~858 MB.
    test('evicts the oldest segment when the storage limit is exceeded', () {
      final provider = RecordingProvider(makeSettings(storageLimit: '1GB'));
      provider.setVideoBitrate(8000000); // 8 Mbps — ~286 MB per 300s segment

      provider.addSegment('/fake/s1.mp4', 300);
      provider.addSegment('/fake/s2.mp4', 300);
      provider.addSegment('/fake/s3.mp4', 300);
      provider.addSegment('/fake/s4.mp4', 300); // triggers eviction of s1

      // s1 evicted: 3 segments remain, 900s total, 900,000,000 bytes total.
      expect(provider.segmentCount, 3);
      expect(provider.totalSegmentDurationSeconds, 900);
      expect(provider.totalSegmentEstimatedBytes, 900000000);
    });

    // Confirm that storage eviction fires independently of the time limit —
    // a large footage limit must not suppress a storage-driven eviction.
    test('storage eviction fires even when time limit is not approached', () {
      // footageLimit: 6h (21600s) — time will never be exceeded in this test.
      // storageLimit: 1GB — this will be exceeded.
      final provider = RecordingProvider(
        makeSettings(footageLimit: '6h', storageLimit: '1GB'),
      );
      provider.setVideoBitrate(8000000);

      for (var i = 0; i < 3; i++) {
        provider.addSegment('/fake/s$i.mp4', 300); // no eviction yet
      }
      expect(provider.segmentCount, 3);

      provider.addSegment('/fake/s3.mp4', 300); // triggers storage eviction

      expect(provider.segmentCount, 3); // 4 added, 1 evicted = 3 remaining
    });
  });

  // ===========================================================================
  // addSegment — both limits active simultaneously
  // ===========================================================================
  group('RecordingProvider.addSegment — both limits active', () {
    // When storage is set very high, time should be the binding constraint.
    test('time limit is the binding constraint when hit before storage', () {
      // footageLimit: 30min (1800s) — will trigger first.
      // storageLimit: 64GB — unreachably high for this test.
      // Bitrate: 1 Mbps — tiny, so byte accumulation stays negligible.
      final provider = RecordingProvider(
        makeSettings(footageLimit: '30min', storageLimit: '64GB'),
      );
      provider.setVideoBitrate(1000000); // 1 Mbps

      provider.addSegment('/fake/s1.mp4', 1000); // 1000s, ~125 MB
      provider.addSegment('/fake/s2.mp4', 1000); // total 2000 > 1800 → evict s1

      expect(provider.segmentCount, 1);
      expect(provider.totalSegmentDurationSeconds, 1000);
    });

    // When time is set very high, storage should be the binding constraint.
    test('storage limit is the binding constraint when hit before time', () {
      // storageLimit: 1GB — will trigger first.
      // footageLimit: 6h (21600s) — unreachably high for this test.
      final provider = RecordingProvider(
        makeSettings(footageLimit: '6h', storageLimit: '1GB'),
      );
      provider.setVideoBitrate(8000000); // 8 Mbps — ~286 MB per 300s segment

      // 3 segments: ~858 MB ≤ 1 GB (no eviction). 4th: ~1144 MB > 1 GB (evicts s1).
      for (var i = 0; i < 4; i++) {
        provider.addSegment('/fake/s$i.mp4', 300);
      }

      // Time: 4 × 300 = 1200s ≤ 21600s — would not evict by itself.
      // Storage: triggered eviction of one segment.
      expect(provider.segmentCount, 3);
    });
  });

  // ===========================================================================
  // File deletion on eviction
  // ===========================================================================
  group('RecordingProvider.addSegment — file deletion on eviction', () {
    // When a segment is evicted, its file must be permanently deleted from disk.
    // This is the key dashcam behaviour: old footage is not just removed from
    // the index — the actual bytes are freed so storage stays bounded.
    test('evicted segment file is deleted from disk', () async {
      final provider = RecordingProvider(makeSettings(footageLimit: '30min')); // 1800s

      // Create real temporary files so we can assert on disk state after eviction.
      final tmpDir = Directory.systemTemp.createTempSync('rp_eviction_test_');
      try {
        final seg1 = File('${tmpDir.path}/seg1.mp4');
        final seg2 = File('${tmpDir.path}/seg2.mp4');
        await seg1.writeAsString('fake video content');
        await seg2.writeAsString('fake video content');

        provider.addSegment(seg1.path, 1000); // no eviction yet
        expect(seg1.existsSync(), isTrue);    // file must still be present

        provider.addSegment(seg2.path, 1000); // 2000 > 1800 → evicts seg1
        expect(seg1.existsSync(), isFalse);   // seg1 deleted from disk
        expect(seg2.existsSync(), isTrue);    // seg2 is the newest — survives
      } finally {
        // Always clean up the temp directory, even if the test fails.
        // Without this a failed test would leave files behind on disk.
        if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
      }
    });

    // If the segment file has already been deleted (e.g. by the OS or a prior
    // crash), _evictOldestIfNeeded wraps the delete in a try/catch so the app
    // doesn't crash — the segment is still removed from the in-memory list.
    test('eviction with a non-existent path does not throw', () {
      final provider = RecordingProvider(makeSettings(footageLimit: '30min')); // 1800s

      // Use paths that definitely don't exist on the file system.
      expect(
        () {
          provider.addSegment('/no/such/path/seg1.mp4', 1000);
          provider.addSegment('/no/such/path/seg2.mp4', 1000);
        },
        returnsNormally,
      );

      // Eviction still removed seg1 from the in-memory list.
      expect(provider.segmentCount, 1);
    });
  });

  // ===========================================================================
  // Segment start time tracking
  // ===========================================================================
  group('RecordingProvider segment start time', () {
    // segmentStartTime is used by CameraView and ClipProvider to calculate the
    // duration of the current in-progress segment when it needs to be flushed.

    test('segmentStartTime is null before any recording starts', () {
      final provider = RecordingProvider(makeSettings());
      expect(provider.segmentStartTime, isNull);
    });

    test('setSegmentStartTime stores the provided DateTime', () {
      final provider = RecordingProvider(makeSettings());
      final t = DateTime(2026, 5, 14, 10, 0, 0);

      provider.setSegmentStartTime(t);

      expect(provider.segmentStartTime, t);
    });

    test('setSegmentStartTime can be updated after the first set', () {
      final provider = RecordingProvider(makeSettings());
      final t1 = DateTime(2026, 5, 14, 10, 0, 0);
      final t2 = DateTime(2026, 5, 14, 10, 5, 0);

      provider.setSegmentStartTime(t1);
      provider.setSegmentStartTime(t2);

      expect(provider.segmentStartTime, t2);
    });
  });

  // ===========================================================================
  // onFlushRequested callback
  // ===========================================================================
  group('RecordingProvider.onFlushRequested', () {
    // RecordingProvider's flush timer calls onFlushRequested without holding a
    // direct reference to the CameraController. This keeps camera I/O in the
    // widget layer and makes the callback mechanism itself unit-testable.

    test('onFlushRequested callback is null by default', () {
      final provider = RecordingProvider(makeSettings());
      expect(provider.onFlushRequested, isNull);
    });

    test('assigned callback is stored and retrievable', () {
      final provider = RecordingProvider(makeSettings());
      var called = false;
      provider.onFlushRequested = () { called = true; };

      provider.onFlushRequested?.call();

      expect(called, isTrue);
    });

    test('callback can be cleared by setting it to null', () {
      final provider = RecordingProvider(makeSettings());
      provider.onFlushRequested = () {};

      provider.onFlushRequested = null;

      expect(provider.onFlushRequested, isNull);
    });
  });
}
