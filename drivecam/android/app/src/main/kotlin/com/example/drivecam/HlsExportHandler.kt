// Android-side implementation of HLS-to-single-MP4 export.
//
// Called from Dart via MethodChannel("drivecam/hls_export"). The handler
// takes a list of absolute paths to MP4 segment files (all produced by the
// camera plugin within the same session, so they share codec/format) plus
// an output path, and copies their samples into one MP4 using MediaMuxer.
//
// No re-encoding happens here — we only rewrite container boxes and
// re-stamp sample presentation timestamps so the output plays as a single
// continuous file. This is effectively "ffmpeg -c copy" but implemented
// in the Android platform APIs so we don't need the ffmpeg library.
//
// Assumptions:
//   - Every segment has the same video track format (camera plugin
//     produces consistent output within a session).
//   - Segments may optionally carry an audio track; we detect per-segment
//     and skip the audio track if the first segment doesn't have one.
package com.example.drivecam

import android.graphics.Bitmap
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import android.util.Log
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer

object HlsExportHandler {
    private const val TAG = "HlsExportHandler"
    const val CHANNEL = "drivecam/hls_export"

    /**
     * Handle a single MethodChannel call from Dart. Only one method is
     * supported: `remuxSegments` with `segmentPaths: List<String>` and
     * `outputPath: String`.
     */
    fun handle(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "remuxSegments" -> handleRemux(call, result)
            "extractFirstFrame" -> handleExtractFirstFrame(call, result)
            else -> result.notImplemented()
        }
    }

    private fun handleRemux(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        val segmentPaths = call.argument<List<String>>("segmentPaths")
        val outputPath = call.argument<String>("outputPath")
        if (segmentPaths.isNullOrEmpty() || outputPath.isNullOrBlank()) {
            result.error("INVALID_ARGS", "segmentPaths and outputPath are required", null)
            return
        }
        try {
            remux(segmentPaths, outputPath)
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "remux failed", e)
            try { File(outputPath).delete() } catch (_: Exception) {}
            result.error("REMUX_FAILED", e.message ?: "unknown error", null)
        }
    }

    private fun handleExtractFirstFrame(
        call: io.flutter.plugin.common.MethodCall,
        result: MethodChannel.Result,
    ) {
        val videoPath = call.argument<String>("videoPath")
        val outputPath = call.argument<String>("outputPath")
        val quality = call.argument<Int>("quality") ?: 75
        if (videoPath.isNullOrBlank() || outputPath.isNullOrBlank()) {
            result.error("INVALID_ARGS", "videoPath and outputPath are required", null)
            return
        }
        try {
            extractFirstFrame(videoPath, outputPath, quality)
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "extractFirstFrame failed", e)
            try { File(outputPath).delete() } catch (_: Exception) {}
            result.error("THUMBNAIL_FAILED", e.message ?: "unknown error", null)
        }
    }

    /**
     * Extract the first video frame from [videoPath] and write it as a
     * JPEG to [outputPath]. Uses Android's MediaMetadataRetriever which
     * is the platform's built-in primitive for this — no FFmpeg, no
     * third-party deps.
     */
    private fun extractFirstFrame(videoPath: String, outputPath: String, quality: Int) {
        if (!File(videoPath).exists()) {
            throw IllegalStateException("Video missing: $videoPath")
        }
        val retriever = MediaMetadataRetriever()
        var bitmap: Bitmap? = null
        try {
            retriever.setDataSource(videoPath)
            // Time 0 + OPTION_CLOSEST_SYNC gives us the first keyframe,
            // which is the natural thumbnail choice and avoids forcing
            // the decoder to reconstruct an intermediate frame.
            bitmap = retriever.getFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                ?: throw IllegalStateException("No frame available in $videoPath")
            File(outputPath).parentFile?.mkdirs()
            FileOutputStream(outputPath).use { out ->
                bitmap.compress(Bitmap.CompressFormat.JPEG, quality, out)
            }
        } finally {
            bitmap?.recycle()
            retriever.release()
        }
    }

    /**
     * Remux [segmentPaths] into a single MP4 at [outputPath].
     *
     * Strategy:
     *  1. Open the first segment, inspect its tracks, add matching tracks
     *     to the muxer.
     *  2. For each segment in order:
     *      - open a MediaExtractor
     *      - for each selected track, read every sample and write it to
     *        the muxer with presentationTimeUs offset by the cumulative
     *        duration of prior segments for that track.
     *  3. Stop and release the muxer.
     */
    private fun remux(segmentPaths: List<String>, outputPath: String) {
        // Ensure the parent directory exists.
        File(outputPath).parentFile?.mkdirs()

        val muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        var muxerStarted = false

        // Track-index mappings from the first *valid* segment's extractor to
        // the muxer's indices. The same indices are reused for every subsequent
        // segment (all segments share the same codec/format within a session).
        var videoMuxerIdx = -1
        var audioMuxerIdx = -1

        // Running presentation time offsets, one per muxer track. After
        // each segment we advance by that segment's observed duration.
        var videoPtsOffsetUs = 0L
        var audioPtsOffsetUs = 0L

        // Reusable buffer big enough for any compressed sample we'll see.
        // 4 MB is generous; most single-frame samples are <100 KB.
        val sampleBuffer = ByteBuffer.allocate(4 * 1024 * 1024)
        val bufferInfo = MediaCodec.BufferInfo()

        // Tracks whether the muxer has been configured with the first valid
        // segment yet. We use this flag instead of segIdx == 0 so that a
        // corrupt or empty first segment (e.g. from a MediaRecorder.stop()
        // failure) does not prevent the rest of the recording from playing.
        var firstValidSegment = true

        try {
            for (path in segmentPaths) {
                // Skip segments that don't exist on disk.
                if (!File(path).exists()) {
                    Log.w(TAG, "Segment missing, skipping: $path")
                    continue
                }
                // A file smaller than 100 bytes cannot contain encoded video
                // data. This catches the empty files left behind when
                // MediaRecorder.stop() throws before writing any frames.
                if (File(path).length() < 100) {
                    Log.w(TAG, "Segment too small to be valid " +
                        "(${File(path).length()} bytes), skipping: $path")
                    continue
                }

                val extractor = MediaExtractor()
                // setDataSource can throw if the file is not a parseable
                // media container (e.g. a truncated MP4 from a failed stop).
                // Skip it rather than aborting the whole remux.
                val opened = try {
                    extractor.setDataSource(path)
                    true
                } catch (e: Exception) {
                    Log.w(TAG, "Segment not parseable, skipping: $path — ${e.message}")
                    extractor.release()
                    false
                }
                if (!opened) continue

                // Identify the video and audio tracks in THIS segment.
                var segVideoTrack = -1
                var segAudioTrack = -1
                for (t in 0 until extractor.trackCount) {
                    val fmt = extractor.getTrackFormat(t)
                    val mime = fmt.getString(MediaFormat.KEY_MIME) ?: ""
                    when {
                        segVideoTrack < 0 && mime.startsWith("video/") -> segVideoTrack = t
                        segAudioTrack < 0 && mime.startsWith("audio/") -> segAudioTrack = t
                    }
                }

                if (segVideoTrack < 0) {
                    extractor.release()
                    Log.w(TAG, "Segment has no video track, skipping: $path")
                    continue
                }

                // On the first valid segment only: register tracks on the muxer.
                // Later segments MUST have the same track shape; we take this
                // on faith since all segments come from one camera session.
                if (firstValidSegment) {
                    firstValidSegment = false

                    // MediaMuxer does NOT automatically copy container-level metadata
                    // such as the rotation/orientation hint. We must read it from the
                    // source segment and apply it explicitly before start(). Without
                    // this, every remuxed file defaults to 0° (landscape) regardless
                    // of how the phone was held during recording.
                    val retriever = MediaMetadataRetriever()
                    try {
                        retriever.setDataSource(path)
                        val rotStr = retriever.extractMetadata(
                            MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION,
                        )
                        // toIntOrNull() returns null for missing/malformed metadata;
                        // fall back to 0 (no rotation) so the output is still valid.
                        val rotation = rotStr?.toIntOrNull() ?: 0
                        muxer.setOrientationHint(rotation)
                    } finally {
                        retriever.release()
                    }

                    videoMuxerIdx = muxer.addTrack(extractor.getTrackFormat(segVideoTrack))
                    if (segAudioTrack >= 0) {
                        audioMuxerIdx = muxer.addTrack(extractor.getTrackFormat(segAudioTrack))
                    }
                    muxer.start()
                    muxerStarted = true
                }

                // Copy video samples.
                val segVideoDurUs = copyTrack(
                    extractor = extractor,
                    extractorTrackIdx = segVideoTrack,
                    muxer = muxer,
                    muxerTrackIdx = videoMuxerIdx,
                    ptsOffsetUs = videoPtsOffsetUs,
                    sampleBuffer = sampleBuffer,
                    bufferInfo = bufferInfo,
                )
                videoPtsOffsetUs += segVideoDurUs

                // Copy audio samples if both this segment and the first
                // valid segment had audio tracks.
                if (segAudioTrack >= 0 && audioMuxerIdx >= 0) {
                    val segAudioDurUs = copyTrack(
                        extractor = extractor,
                        extractorTrackIdx = segAudioTrack,
                        muxer = muxer,
                        muxerTrackIdx = audioMuxerIdx,
                        ptsOffsetUs = audioPtsOffsetUs,
                        sampleBuffer = sampleBuffer,
                        bufferInfo = bufferInfo,
                    )
                    audioPtsOffsetUs += segAudioDurUs
                }

                extractor.release()
            }

            // If every segment was skipped (all corrupt/missing), there is
            // nothing to play back — surface this as an error rather than
            // silently producing an empty file.
            if (!muxerStarted) {
                throw IllegalStateException("No valid segments found in recording")
            }
        } finally {
            if (muxerStarted) {
                try { muxer.stop() } catch (e: Exception) { Log.w(TAG, "muxer.stop failed", e) }
            }
            try { muxer.release() } catch (e: Exception) { Log.w(TAG, "muxer.release failed", e) }
        }
    }

    /**
     * Walk [extractorTrackIdx] in [extractor], writing every sample to
     * [muxer]'s [muxerTrackIdx] with presentation timestamps shifted by
     * [ptsOffsetUs]. Returns the observed duration of this track in this
     * segment, in microseconds, so the caller can advance its running
     * offset for the next segment.
     */
    private fun copyTrack(
        extractor: MediaExtractor,
        extractorTrackIdx: Int,
        muxer: MediaMuxer,
        muxerTrackIdx: Int,
        ptsOffsetUs: Long,
        sampleBuffer: ByteBuffer,
        bufferInfo: MediaCodec.BufferInfo,
    ): Long {
        extractor.selectTrack(extractorTrackIdx)
        // Seek to 0 to make sure we start at the beginning of the track.
        extractor.seekTo(0, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)

        var firstPts = -1L
        var lastPts = 0L
        while (true) {
            sampleBuffer.clear()
            val size = extractor.readSampleData(sampleBuffer, 0)
            if (size < 0) break // end of track
            val pts = extractor.sampleTime
            if (firstPts < 0) firstPts = pts
            lastPts = pts

            bufferInfo.offset = 0
            bufferInfo.size = size
            bufferInfo.presentationTimeUs = pts + ptsOffsetUs - firstPts.coerceAtLeast(0)
            bufferInfo.flags = extractor.sampleFlags
            muxer.writeSampleData(muxerTrackIdx, sampleBuffer, bufferInfo)
            if (!extractor.advance()) break
        }
        extractor.unselectTrack(extractorTrackIdx)

        // Approx duration: last sample timestamp minus first. Good enough;
        // the next segment's first sample usually starts near 0 again.
        return (lastPts - firstPts.coerceAtLeast(0)).coerceAtLeast(0)
    }
}
