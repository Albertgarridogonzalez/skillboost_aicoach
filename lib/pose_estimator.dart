import 'dart:io';
import 'dart:typed_data';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:image/image.dart' as img;

import 'video_processor.dart';

class PoseEstimator {
  static Interpreter? _interpreter;
  static List<Map<String, dynamic>> referencePoses = [];

  static Future<void> _initInterpreter() async {
    if (_interpreter == null) {
      _interpreter = await Interpreter.fromAsset('assets/models/pose_model.tflite');
    }
  }

  static Future<String> _extractFrames(String videoPath) async {
    final framesDir = await VideoProcessor.processVideo(videoPath);
    return framesDir;
  }

  static Future<void> loadReferencePoses(String referenceVideoPath) async {
    referencePoses.clear();
    final framesDir = await _extractFrames(referenceVideoPath);
    final frameFiles = Directory(framesDir)
        .listSync()
        .whereType<File>()
        .where((f) => p.extension(f.path).toLowerCase() == '.jpg')
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    for (var frame in frameFiles) {
      final bytes = await frame.readAsBytes();
      final poseData = await estimatePose(bytes);
      referencePoses.add(poseData);
    }
    print("📌 Referencias cargadas con ${referencePoses.length} frames.");
  }

  static Future<Map<String, dynamic>> estimatePose(Uint8List imageBytes) async {
    await _initInterpreter();
    if (_interpreter == null) return {};

    final decodedImage = img.decodeImage(imageBytes);
    if (decodedImage == null) return {};

    final resized = img.copyResize(decodedImage, width: 256, height: 256);

    final inputShape = _interpreter!.getInputTensor(0).shape;
    final inputBuffer =
        Float32List(inputShape[1] * inputShape[2] * inputShape[3]).buffer;
    final inputAsList = inputBuffer.asFloat32List();

    int idx = 0;
    for (int y = 0; y < 256; y++) {
      for (int x = 0; x < 256; x++) {
        final pixel = resized.getPixel(x, y);
        final r = pixel.r;
        final g = pixel.g;
        final b = pixel.b;

        inputAsList[idx++] = (r / 127.5) - 1.0;
        inputAsList[idx++] = (g / 127.5) - 1.0;
        inputAsList[idx++] = (b / 127.5) - 1.0;
      }
    }

    final outputShape = _interpreter!.getOutputTensor(0).shape;
    final outputBuffer =
        Float32List(outputShape[1] * outputShape[2]).buffer;
    final outputs = [outputBuffer];

    _interpreter!.run(inputAsList, outputs);
    final outputAsList = outputBuffer.asFloat32List();

    if (outputAsList.isEmpty || outputAsList.length % 3 != 0) {
      print("⚠️ Error: El modelo devolvió una salida vacía o inválida.");
      return {};
    }

    final int numKeypoints = outputAsList.length ~/ 3;
    print("📌 Modelo detectó $numKeypoints keypoints.");

    final Map<String, Map<String, double>> poseMap = {};
    final double origW = decodedImage.width.toDouble();
    final double origH = decodedImage.height.toDouble();

    for (int kp = 0; kp < numKeypoints; kp++) {
      final ix = kp * 3;

      if (ix + 1 >= outputAsList.length) {
        print("⚠️ Advertencia: índice $ix fuera de rango en la salida del modelo.");
        break;
      }

      final xNorm = outputAsList[ix];    
      final yNorm = outputAsList[ix + 1];

      final px = xNorm * origW;
      final py = yNorm * origH;

      poseMap['keypoint_$kp'] = {
        'x': px,
        'y': py,
      };
    }

    return poseMap;
  }
}
