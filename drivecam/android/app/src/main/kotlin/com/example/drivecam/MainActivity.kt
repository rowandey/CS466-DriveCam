package com.example.drivecam

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // Register both MethodChannels during Flutter engine setup so the Dart
    // layer can use them as soon as the first frame is drawn.
    //
    // HlsExportHandler  — remuxes HLS segments into a single MP4 for gallery
    //                     export, and extracts first frames for thumbnails.
    //                     Does NOT need the TextureRegistry because it only
    //                     processes files on disk.
    //
    // HlsRecorderHandler — owns the Camera2 + MediaRecorder recording pipeline.
    //                      Needs the TextureRegistry to create a SurfaceTexture
    //                      that Flutter can render with a Texture widget.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Wire up the export / thumbnail channel.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, HlsExportHandler.CHANNEL)
            .setMethodCallHandler { call, result -> HlsExportHandler.handle(call, result) }

        // Provide the recorder with the texture registry and context before
        // registering its channel so init() is guaranteed to run first.
        HlsRecorderHandler.init(
            registry = flutterEngine.renderer,
            ctx      = applicationContext,
        )
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, HlsRecorderHandler.CHANNEL)
            .setMethodCallHandler { call, result -> HlsRecorderHandler.handle(call, result) }
    }
}
