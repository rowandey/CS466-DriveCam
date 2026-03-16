import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class RecordingProvider extends ChangeNotifier {
  bool isRecording = false;
  CameraController? _controller;

  void toggleRecording() {
    isRecording = !isRecording;
    notifyListeners();
    if (isRecording) {
      // TODO: start recording
    } else {
      // TODO: stop recording
    }
  }



  void setCameraController(CameraController controller) {
    _controller = controller;
  }
}
