// HLS native recorder — Camera2 + MediaRecorder with setNextOutputFile.
//
// Why this file exists instead of using the Flutter camera plugin:
//   The camera plugin's stopVideoRecording() / startVideoRecording() cycle
//   stops and restarts the MediaRecorder (and briefly its capture session)
//   every time we rotate to a new segment. MediaRecorder.stop() finalises
//   the MP4 file synchronously on the platform thread, which is the same
//   thread Flutter uses for rendering coordination. The result is a visible
//   freeze in the camera preview every 5 seconds.
//
//   MediaRecorder.setNextOutputFile() (API 26+) solves this: the encoder
//   keeps running and simply switches its output file at the next sync
//   (keyframe) boundary — no session teardown, no platform-thread stall,
//   no preview interruption whatsoever. The transition takes ≤ 1 frame
//   (~33 ms at 30 fps), which is invisible to the human eye.
//
// Architecture:
//   • Camera2 API owns the CameraDevice and CameraCaptureSession.
//   • A Flutter SurfaceTexture (registered via TextureRegistry) is the
//     preview target. Dart renders it with a Texture widget.
//   • MediaRecorder writes directly to the session-directory paths that
//     Dart specifies, so no file-rename step is needed in Dart.
//   • MethodChannel "drivecam/hls_recorder" exposes five methods:
//       initialize  → open camera, return textureId + preview dimensions
//       startRecording  → configure session with recorder surface, start
//       rotateSegment   → setNextOutputFile, return elapsed segment time
//       stopRecording   → finalize last segment, return its duration
//       dispose         → release all resources
//
// Threading:
//   MethodChannel calls arrive on Android's main (UI) thread.
//   All camera state callbacks run on [cameraHandler] (background thread).
//   result.success / result.error must be called on the main thread;
//   use [mainHandler.post { ... }] for any callback that calls result.
package com.example.drivecam

import android.content.Context
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.hardware.camera2.CameraDevice.StateCallback
import android.hardware.camera2.CameraCaptureSession
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.util.Log
import android.util.Size
import android.view.Surface
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.io.File
import kotlin.math.abs

object HlsRecorderHandler {
    private const val TAG = "HlsRecorderHandler"
    const val CHANNEL = "drivecam/hls_recorder"

    // Provided by MainActivity during engine setup so we can create Flutter textures.
    private var textureRegistry: TextureRegistry? = null
    private var appContext: Context? = null

    // Dispatches callbacks back to the Android main thread so result.*() is called
    // from the correct thread (Flutter's MethodChannel requirement).
    private val mainHandler = Handler(Looper.getMainLooper())

    // Dedicated background thread for Camera2 state callbacks and blocking I/O.
    // Camera2 requires a non-null Handler for its callbacks; using the main thread
    // would block rendering while waiting for camera hardware.
    private var cameraThread: HandlerThread? = null
    private var cameraHandler: Handler? = null

    // Camera2 objects.
    private var cameraDevice: CameraDevice? = null
    private var captureSession: CameraCaptureSession? = null

    // Flutter preview texture.
    private var surfaceTextureEntry: TextureRegistry.SurfaceTextureEntry? = null
    private var previewSurface: Surface? = null

    // Recording objects.
    private var mediaRecorder: MediaRecorder? = null
    private var isRecording = false

    // Timestamp of when the current segment started (wall clock, ms).
    // Used to compute the elapsed segment duration returned by rotateSegment/stopRecording.
    private var segmentStartMs = 0L

    // Camera settings stored on initialize() and reused by startRecording().
    private var videoWidth = 1280
    private var videoHeight = 720
    private var videoFps = 30
    private var audioEnabled = true
    private var sensorOrientation = 90  // degrees; 90 for most back cameras

    /**
     * Must be called once from MainActivity before any MethodChannel calls.
     * Provides the resources needed to create preview textures.
     *
     * Parameters:
     *   [registry] — Flutter's TextureRegistry for registering preview surfaces.
     *   [ctx]      — Application context (survives activity recreation).
     */
    fun init(registry: TextureRegistry, ctx: Context) {
        textureRegistry = registry
        appContext = ctx.applicationContext
    }

    /**
     * Route an incoming MethodChannel call to the appropriate handler.
     * Unknown methods return [MethodChannel.Result.notImplemented].
     */
    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize"     -> initialize(call, result)
            "startRecording" -> startRecording(call, result)
            "rotateSegment"  -> rotateSegment(call, result)
            "stopRecording"  -> stopRecording(result)
            "updateSettings" -> updateSettings(call, result)
            "dispose"        -> dispose(result)
            else             -> result.notImplemented()
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // initialize
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Open the back camera, create a Flutter SurfaceTexture for the preview,
     * and start a preview-only capture session.
     *
     * Parameters (from Dart):
     *   width        — requested preview / recording width in pixels
     *   height       — requested preview / recording height in pixels
     *   fps          — target frame rate
     *   audioEnabled — whether the microphone should be captured
     *
     * Returns a map: { textureId: Long, width: Int, height: Int, sensorOrientation: Int }
     * The Dart side uses textureId for the Texture widget and the dimensions
     * to compute the correct aspect ratio and rotation correction.
     */
    private fun initialize(call: MethodCall, result: MethodChannel.Result) {
        videoWidth   = call.argument<Int>("width")           ?: 1280
        videoHeight  = call.argument<Int>("height")          ?: 720
        videoFps     = call.argument<Int>("fps")             ?: 30
        audioEnabled = call.argument<Boolean>("audioEnabled") ?: true

        ensureCameraThread()

        val ctx      = appContext      ?: return result.error("NO_CONTEXT",  "Call init() first", null)
        val registry = textureRegistry ?: return result.error("NO_REGISTRY", "Call init() first", null)
        val manager  = ctx.getSystemService(Context.CAMERA_SERVICE) as CameraManager

        // Find the back camera and read its sensor orientation.
        val cameraId = backCameraId(manager)
            ?: return result.error("NO_CAMERA", "No back camera found", null)
        val characteristics = manager.getCameraCharacteristics(cameraId)
        sensorOrientation = characteristics.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 90

        // Select the closest supported preview size to what Dart requested.
        val cfg = characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
        val previewSizes = cfg?.getOutputSizes(android.graphics.SurfaceTexture::class.java)
        val chosen = chooseBestSize(previewSizes, videoWidth, videoHeight)
        videoWidth  = chosen.width
        videoHeight = chosen.height

        // Log what we're actually using so orientation bugs are diagnosable.
        Log.d(TAG, "initialize: sensorOrientation=$sensorOrientation " +
              "size=${videoWidth}x${videoHeight} (requested ${call.argument<Int>("width")}x${call.argument<Int>("height")})")

        // Register a SurfaceTexture with Flutter so frames can be displayed
        // in a Texture widget on the Dart side.
        val entry = registry.createSurfaceTexture()
        surfaceTextureEntry = entry
        entry.surfaceTexture().setDefaultBufferSize(videoWidth, videoHeight)
        previewSurface = Surface(entry.surfaceTexture())

        // Guard against double-reply: Camera2 can call both onOpened (which triggers
        // result.success via startPreviewOnlySession) and then onError if the device
        // is lost shortly after opening. The second call to result.* would crash with
        // "Reply already submitted". AtomicBoolean ensures only the first reply wins.
        val replied = java.util.concurrent.atomic.AtomicBoolean(false)

        // Open the camera device asynchronously; the state callback fires on cameraHandler.
        manager.openCamera(cameraId, object : StateCallback() {
            override fun onOpened(camera: CameraDevice) {
                cameraDevice = camera
                startPreviewOnlySession(result, entry.id(), replied)
            }
            override fun onDisconnected(camera: CameraDevice) {
                camera.close()
                cameraDevice = null
            }
            override fun onError(camera: CameraDevice, error: Int) {
                camera.close()
                cameraDevice = null
                if (replied.compareAndSet(false, true)) {
                    mainHandler.post {
                        result.error("CAMERA_ERROR", "Camera open failed: $error", null)
                    }
                }
            }
        }, cameraHandler)
    }

    /**
     * Find the ID of the first back-facing camera, or null if none exists.
     *
     * Parameters:
     *   [manager] — the system CameraManager.
     */
    private fun backCameraId(manager: CameraManager): String? =
        manager.cameraIdList.firstOrNull { id ->
            manager.getCameraCharacteristics(id)
                .get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK
        }

    /**
     * From [available] sizes, pick the one whose area is closest to the requested
     * dimensions and whose aspect ratio matches within a 10% tolerance.
     * Falls back to the closest by area if no aspect-ratio match is found,
     * and to the requested size if the array is null or empty.
     *
     * Parameters:
     *   [available]  — camera-supported output sizes (may be null).
     *   [requestedW] — desired width in pixels.
     *   [requestedH] — desired height in pixels.
     */
    private fun chooseBestSize(available: Array<Size>?, requestedW: Int, requestedH: Int): Size {
        if (available.isNullOrEmpty()) return Size(requestedW, requestedH)
        val requestedArea   = requestedW * requestedH
        val requestedAspect = requestedW.toDouble() / requestedH
        val sameAspect = available.filter {
            abs(it.width.toDouble() / it.height - requestedAspect) < 0.1
        }
        val pool = sameAspect.ifEmpty { available.toList() }
        return pool.minByOrNull { abs(it.width * it.height - requestedArea) }
            ?: Size(requestedW, requestedH)
    }

    /**
     * Create a Camera2 capture session with only the preview surface.
     * Called at startup and after recording stops.
     *
     * Parameters:
     *   [result]    — MethodChannel result to call once the session is ready.
     *   [textureId] — Flutter texture ID to return to Dart.
     *   [replied]   — shared AtomicBoolean preventing double-reply when both
     *                 onOpened and onError fire for the same openCamera call.
     */
    private fun startPreviewOnlySession(
        result: MethodChannel.Result,
        textureId: Long,
        replied: java.util.concurrent.atomic.AtomicBoolean = java.util.concurrent.atomic.AtomicBoolean(false),
    ) {
        val camera  = cameraDevice  ?: return
        val surface = previewSurface ?: return

        camera.createCaptureSession(
            listOf(surface),
            object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(session: CameraCaptureSession) {
                    captureSession = session
                    setRepeating(session, listOf(surface))
                    if (replied.compareAndSet(false, true)) {
                        mainHandler.post {
                            result.success(mapOf(
                                "textureId"         to textureId,
                                "width"             to videoWidth,
                                "height"            to videoHeight,
                                "sensorOrientation" to sensorOrientation,
                            ))
                        }
                    }
                }
                override fun onConfigureFailed(session: CameraCaptureSession) {
                    if (replied.compareAndSet(false, true)) {
                        mainHandler.post {
                            result.error("SESSION_ERROR", "Preview session configuration failed", null)
                        }
                    }
                }
            },
            cameraHandler,
        )
    }

    /**
     * Set a repeating capture request that writes frames to [targets].
     * TEMPLATE_RECORD enables auto-exposure tuned for video.
     * CONTROL_AF_MODE_CONTINUOUS_VIDEO keeps the scene in focus without
     * the discrete focus-lock steps that still-image autofocus uses.
     *
     * Parameters:
     *   [session] — the active CameraCaptureSession.
     *   [targets] — list of Surfaces that should receive every frame.
     */
    private fun setRepeating(session: CameraCaptureSession, targets: List<Surface>) {
        val camera = cameraDevice ?: return
        val request = camera.createCaptureRequest(CameraDevice.TEMPLATE_RECORD).apply {
            targets.forEach { addTarget(it) }
            set(CaptureRequest.CONTROL_MODE,   CaptureRequest.CONTROL_MODE_AUTO)
            set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_VIDEO)
            set(CaptureRequest.CONTROL_AE_MODE, CaptureRequest.CONTROL_AE_MODE_ON)
        }.build()
        session.setRepeatingRequest(request, null, cameraHandler)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // startRecording
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Begin recording to [outputPath]. This reconfigures the camera session to
     * include the MediaRecorder's input surface alongside the preview surface.
     *
     * This causes ONE brief preview interruption (the session must be rebuilt to
     * add the recorder surface). All subsequent segment rotations are freeze-free
     * — see rotateSegment().
     *
     * Parameters (from Dart):
     *   outputPath     — absolute path of the first HLS segment (.mp4).
     *   deviceRotation — current device rotation in degrees (0=portrait,
     *                    90=landscape-right) used for the MP4 orientation hint.
     */
    private fun startRecording(call: MethodCall, result: MethodChannel.Result) {
        val outputPath     = call.argument<String>("outputPath")
            ?: return result.error("INVALID_ARG", "outputPath required", null)
        val deviceRotation = call.argument<Int>("deviceRotation") ?: 0
        val camera         = cameraDevice
            ?: return result.error("NOT_INITIALIZED", "Call initialize() first", null)
        val prevSurface    = previewSurface
            ?: return result.error("NOT_INITIALIZED", "No preview surface", null)

        // Build and prepare a fresh MediaRecorder for this recording session.
        // prepare() must be called before accessing recorder.surface.
        val recorder = buildRecorder(outputPath, deviceRotation)
        try {
            recorder.prepare()
        } catch (e: Exception) {
            recorder.release()
            return result.error("RECORDER_ERROR", "MediaRecorder.prepare() failed: ${e.message}", null)
        }
        val recSurface = recorder.surface
        mediaRecorder  = recorder

        // Close the preview-only session; rebuild it with both surfaces.
        // This is the only intentional preview gap in the entire recording lifecycle.
        captureSession?.close()
        captureSession = null

        camera.createCaptureSession(
            listOf(prevSurface, recSurface),
            object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(session: CameraCaptureSession) {
                    captureSession = session
                    setRepeating(session, listOf(prevSurface, recSurface))
                    recorder.start()
                    isRecording    = true
                    segmentStartMs = System.currentTimeMillis()
                    mainHandler.post { result.success(null) }
                }
                override fun onConfigureFailed(session: CameraCaptureSession) {
                    recorder.release()
                    mediaRecorder = null
                    mainHandler.post {
                        result.error("SESSION_ERROR", "Recording session configuration failed", null)
                    }
                }
            },
            cameraHandler,
        )
    }

    /**
     * Configure a MediaRecorder for HLS segment output.
     *
     * Key settings:
     *   - VIDEO_SOURCE_SURFACE: the encoder reads from a Surface fed by the
     *     camera session (no extra copy / decode step).
     *   - MPEG_4 container: compatible with MediaMuxer for the export path.
     *   - H264 / AAC: universally decodable; ExoPlayer and the gallery handle both.
     *   - Bitrate is scaled proportionally to the pixel count so 720p/1080p/4K
     *     each get an appropriate quality-to-file-size trade-off.
     *   - setOrientationHint encodes the rotation metadata in the container so
     *     media players display the video upright without additional transforms.
     *
     * Parameters:
     *   [outputPath]     — absolute path for this segment's .mp4 file.
     *   [deviceRotation] — device rotation in degrees (0, 90, 180, 270).
     */
    @Suppress("DEPRECATION")
    private fun buildRecorder(outputPath: String, deviceRotation: Int): MediaRecorder {
        val recorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
            MediaRecorder(appContext!!)
        else
            MediaRecorder()

        if (audioEnabled) recorder.setAudioSource(MediaRecorder.AudioSource.MIC)
        recorder.setVideoSource(MediaRecorder.VideoSource.SURFACE)
        recorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
        recorder.setOutputFile(outputPath)
        recorder.setVideoEncoder(MediaRecorder.VideoEncoder.H264)
        recorder.setVideoSize(videoWidth, videoHeight)
        recorder.setVideoFrameRate(videoFps)

        // Scale bitrate by pixel count relative to 1080p. Clamp to a safe range
        // so the encoder doesn't under-budget ultra-low resolutions or blow out
        // memory on ultra-high ones.
        val pixels  = videoWidth.toLong() * videoHeight
        val bitrate = (pixels.toDouble() / (1920L * 1080) * 10_000_000).toInt()
            .coerceIn(2_000_000, 20_000_000)
        recorder.setVideoEncodingBitRate(bitrate)

        // Compute the rotation hint so the recorded file plays back upright in
        // media players without requiring the caller to apply a transform.
        // Formula: the sensor captures at sensorOrientation degrees; the device
        // display is rotated deviceRotation degrees; subtracting gives the net
        // clockwise rotation the player needs to apply.
        val hint = (sensorOrientation - deviceRotation + 360) % 360
        recorder.setOrientationHint(hint)

        if (audioEnabled) {
            recorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            recorder.setAudioSamplingRate(44_100)
            recorder.setAudioEncodingBitRate(128_000)
        }
        return recorder
    }

    // ─────────────────────────────────────────────────────────────────────────
    // rotateSegment  ←  the freeze fix
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Seamlessly switch the recording output to [nextOutputPath].
     *
     * This is the core of the freeze fix. [MediaRecorder.setNextOutputFile]
     * tells the encoder to switch its output file at the next sync (keyframe)
     * boundary. The encoder runs continuously; the camera session is NOT
     * touched; the preview surface keeps receiving frames without interruption.
     * The visual stutter that occurred with stop/startVideoRecording is gone.
     *
     * The transition happens within one video frame (~33 ms at 30 fps), which
     * is imperceptible. The previous segment's MP4 file is finalised by the
     * encoder at the keyframe boundary and is readable immediately after.
     *
     * Returns (to Dart) the wall-clock elapsed time of the segment that just
     * ended, in seconds. This value is used for the #EXTINF entry in the
     * HLS manifest. It is a close approximation — the true encoded duration
     * may differ by up to one frame interval because the file transition
     * happens at the next keyframe after this call returns.
     *
     * Requires API 26 (Android 8.0, 2017). The minSdkVersion in
     * build.gradle.kts must be at least 26 for this path to be reachable.
     *
     * Parameters (from Dart):
     *   nextOutputPath — absolute path for the next segment .mp4 file.
     */
    private fun rotateSegment(call: MethodCall, result: MethodChannel.Result) {
        val nextPath = call.argument<String>("nextOutputPath")
            ?: return result.error("INVALID_ARG", "nextOutputPath required", null)
        val recorder = mediaRecorder
            ?: return result.error("NOT_RECORDING", "Not currently recording", null)
        val handler  = cameraHandler
            ?: return result.error("NOT_INITIALIZED", "Camera thread unavailable", null)

        // Measure elapsed time here, before dispatching, so the clock is read
        // as close as possible to when the rotation was actually requested.
        val elapsedMs = System.currentTimeMillis() - segmentStartMs

        // Dispatch to the camera background thread — the same thread that calls
        // recorder.start() inside startRecording()'s onConfigured callback.
        // MediaRecorder is NOT thread-safe: calling setNextOutputFile() from
        // the Android main thread (where MethodChannel calls arrive) while
        // start()/stop() run on the camera thread produces INVALID_OPERATION
        // (-38). This mirrors the dispatch pattern used in stopRecording().
        handler.post {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                try {
                    // The key API call — zero camera interaction, zero preview interruption.
                    recorder.setNextOutputFile(File(nextPath))
                } catch (e: Exception) {
                    mainHandler.post {
                        result.error("ROTATE_ERROR", "setNextOutputFile failed: ${e.message}", null)
                    }
                    return@post
                }
            } else {
                // This branch is unreachable if minSdkVersion >= 26, but kept as a
                // safety net so the app fails gracefully on unexpectedly old devices
                // rather than crashing silently.
                mainHandler.post {
                    result.error(
                        "UNSUPPORTED",
                        "setNextOutputFile requires API 26+. Update minSdkVersion.",
                        null,
                    )
                }
                return@post
            }

            // Reset the clock for the next segment on the camera thread so
            // segmentStartMs is always written by the same thread that reads it
            // for subsequent rotations or the final stopRecording() call.
            segmentStartMs = System.currentTimeMillis()
            mainHandler.post { result.success(elapsedMs.toDouble() / 1000.0) }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // stopRecording
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Finalise the last segment and drop back to preview-only mode.
     *
     * [MediaRecorder.stop] is called on [cameraHandler] (background thread) to
     * avoid blocking the Android main thread during the MP4 finalisation step.
     * The preview-only session is rebuilt on the same background thread before
     * the result is posted to the main thread, so the camera preview resumes
     * as quickly as possible after the recording ends.
     *
     * Returns (to Dart) the elapsed duration of the final segment in seconds.
     */
    private fun stopRecording(result: MethodChannel.Result) {
        val recorder    = mediaRecorder
            ?: return result.error("NOT_RECORDING", "Not currently recording", null)
        val prevSurface = previewSurface
            ?: return result.error("NOT_INITIALIZED", "No preview surface", null)
        val camera      = cameraDevice
            ?: return result.error("NOT_INITIALIZED", "No camera", null)

        val elapsedMs = System.currentTimeMillis() - segmentStartMs

        // Run the blocking stop() on the camera background thread so Flutter's
        // platform thread (main thread) stays responsive during finalization.
        cameraHandler?.post {
            try {
                recorder.stop()
            } catch (e: Exception) {
                // MediaRecorder.stop() can throw RuntimeException if no data
                // was recorded (e.g. the recording was stopped immediately after
                // starting). Log and continue — the caller handles empty segments.
                Log.w(TAG, "recorder.stop() threw (possibly no data): ${e.message}")
            } finally {
                recorder.release()
                mediaRecorder = null
                isRecording   = false
            }

            // Rebuild the preview-only session now that the recorder surface is released.
            captureSession?.close()
            captureSession = null

            camera.createCaptureSession(
                listOf(prevSurface),
                object : CameraCaptureSession.StateCallback() {
                    override fun onConfigured(session: CameraCaptureSession) {
                        captureSession = session
                        setRepeating(session, listOf(prevSurface))
                        mainHandler.post { result.success(elapsedMs.toDouble() / 1000.0) }
                    }
                    override fun onConfigureFailed(session: CameraCaptureSession) {
                        // Best-effort: return the duration even if session rebuild fails.
                        mainHandler.post { result.success(elapsedMs.toDouble() / 1000.0) }
                    }
                },
                cameraHandler,
            )
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // updateSettings
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Update recorder settings (currently just audioEnabled) without closing
     * the camera. Called when the user toggles the audio setting mid-recording:
     * Dart calls pauseSessionForSwap() → stopRecording() → updateSettings() →
     * resumeSessionWith() → startRecording(). The camera stays open throughout
     * so there is no full camera re-initialisation.
     *
     * Parameters (from Dart):
     *   audioEnabled — new audio recording preference.
     */
    private fun updateSettings(call: MethodCall, result: MethodChannel.Result) {
        audioEnabled = call.argument<Boolean>("audioEnabled") ?: audioEnabled
        result.success(null)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // dispose
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Release every resource owned by this handler. Safe to call while
     * recording; it will stop the recorder first. Safe to call multiple times.
     *
     * Must be called when the Flutter camera view is disposed to avoid leaking
     * the CameraDevice, MediaRecorder, and SurfaceTexture.
     */
    private fun dispose(result: MethodChannel.Result) {
        cameraHandler?.post {
            // Stop the recorder before releasing the camera session.
            if (mediaRecorder != null) {
                try { mediaRecorder?.stop() } catch (_: Exception) {}
                mediaRecorder?.release()
                mediaRecorder = null
                isRecording   = false
            }
            captureSession?.close()
            captureSession = null
            cameraDevice?.close()
            cameraDevice   = null
            previewSurface?.release()
            previewSurface = null
            surfaceTextureEntry?.release()
            surfaceTextureEntry = null
            stopCameraThread()
            mainHandler.post { result.success(null) }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Camera thread helpers
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Start the camera background thread if it is not already running.
     * Idempotent — safe to call multiple times.
     */
    private fun ensureCameraThread() {
        if (cameraThread == null) {
            cameraThread = HandlerThread("HlsCamera").also { it.start() }
            cameraHandler = Handler(cameraThread!!.looper)
        }
    }

    /**
     * Shut down the camera background thread and clear the references.
     * Called from dispose() after all camera resources have been released.
     */
    private fun stopCameraThread() {
        cameraThread?.quitSafely()
        cameraThread  = null
        cameraHandler = null
    }
}
