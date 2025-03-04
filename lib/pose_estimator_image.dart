import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

class PoseEstimatorimage {
  static Interpreter? _interpreter;
  static TensorType? _inputType;

  static const double scoreThreshold = 0.0;

  /// Inicializa el intérprete una sola vez
  static Future<void> _initInterpreter() async {
    if (_interpreter == null) {
      _interpreter = await Interpreter.fromAsset(
        'assets/models/singlepose_thunder_float16.tflite',
      );
      _inputType = _interpreter!.getInputTensor(0).type;
      print("Tipo de entrada del tensor: $_inputType");

      final inputShape = _interpreter!.getInputTensor(0).shape;
      final outputShape = _interpreter!.getOutputTensor(0).shape;
      print("Input shape: $inputShape");
      print("Output shape: $outputShape");
    }
  }

  /// Lee el File, hornea la orientación EXIF en los píxeles (bakeOrientation),
  /// corre la inferencia y devuelve:
  /// {
  ///   'image': img.Image (ya físicamente en la orientación correcta),
  ///   'pose': { 'nose':{'x':..,'y':..,'score':..}, ... },
  ///   'width': int,
  ///   'height': int
  /// }
  static Future<Map<String, dynamic>?> detectPoseOnOrientedImage(File file) async {
    await _initInterpreter();
    if (_interpreter == null) return null;

    // 1) Leer bytes y decodificar
    final bytes = await file.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    // 2) Hornear la orientación: gira físicamente la imagen si el EXIF dice que está rotada
    final oriented = img.bakeOrientation(decoded);
    print("Oriented image: ${oriented.width} x ${oriented.height} (bakeOrientation aplicado)");
    final origW = oriented.width;
    final origH = oriented.height;
    print("Oriented image: $origW x $origH (bakeOrientation aplicado)");

    // 3) Corre la inferencia (letterbox + run) sobre la imagen ya reorientada
    final poseMap = _runInferenceOnImage(oriented);
    if (poseMap == null) return null;

    // Devolvemos la imagen reorientada y la pose
    return {
      'image': oriented,
      'pose': poseMap,
      'width': origW,
      'height': origH,
    };
  }

  /// Hace la inferencia en la imagen reorientada: letterbox, buildInput, run, remap coords
  static Map<String, Map<String, double>>? _runInferenceOnImage(img.Image oriented) {
    if (_interpreter == null) return null;

    final origW = oriented.width;
    final origH = oriented.height;

    // 1) Input shape
    final inputShape = _interpreter!.getInputTensor(0).shape;
    final targetH = inputShape[1];
    final targetW = inputShape[2];

    // 2) Letterbox
    final letterboxData = _letterboxAndResize(oriented, targetW, targetH);
    final letterboxImage = letterboxData['image'] as img.Image;
    final ratio = letterboxData['ratio'] as double;
    final offsetX = letterboxData['offsetX'] as int;
    final offsetY = letterboxData['offsetY'] as int;

    // 3) Build input
    final inputTensor = _buildInput(letterboxImage, targetW, targetH);

    // 4) Output buffer
    final output = List.generate(
      1,
      (_) => List.generate(
        1,
        (_) => List.generate(
          17,
          (_) => List.filled(3, 0.0),
        ),
      ),
    );

    // 5) Run
    _interpreter!.run(inputTensor, output);

    // 6) Keypoint names
    final keypointNames = [
      'nose', 'leftEye', 'rightEye', 'leftEar', 'rightEar',
      'leftShoulder', 'rightShoulder', 'leftElbow', 'rightElbow',
      'leftWrist', 'rightWrist', 'leftHip', 'rightHip',
      'leftKnee', 'rightKnee', 'leftAnkle', 'rightAnkle'
    ];

    // 7) Remap coords
    final poseMap = <String, Map<String, double>>{};
    for (int i = 0; i < keypointNames.length; i++) {
      final xNorm = output[0][0][i][0];
      final yNorm = output[0][0][i][1];
      final score = output[0][0][i][2];

      if (score < scoreThreshold) {
        // filtrar si quieres
      }

      final px = xNorm * targetW;
      final py = yNorm * targetH;

      double finalX = (px - offsetX) / ratio;
      double finalY = (py - offsetY) / ratio;

      if (finalX < 0) finalX = 0;
      if (finalX > origW - 1) finalX = (origW - 1).toDouble();
      if (finalY < 0) finalY = 0;
      if (finalY > origH - 1) finalY = (origH - 1).toDouble();

      poseMap[keypointNames[i]] = {
        'x': finalX,
        'y': finalY,
        'score': score,
      };
    }

    return poseMap;
  }

  /// Aplica letterbox a la imagen [src] para adaptarla al tamaño [targetW, targetH].
  static Map<String, dynamic> _letterboxAndResize(
      img.Image src, int targetW, int targetH) {
    final origW = src.width;
    final origH = src.height;
    final ratio = math.min(targetW / origW, targetH / origH);
    final newW = (origW * ratio).round();
    final newH = (origH * ratio).round();

    final letterbox = img.Image(width: targetW, height: targetH);

    // Rellenar con negro
    for (int y = 0; y < targetH; y++) {
      for (int x = 0; x < targetW; x++) {
        letterbox.setPixel(x, y, img.ColorRgb8(0, 0, 0));
      }
    }

    final resized = img.copyResize(src, width: newW, height: newH);

    final offX = ((targetW - newW) / 2).round();
    final offY = ((targetH - newH) / 2).round();

    for (int y = 0; y < newH; y++) {
      for (int x = 0; x < newW; x++) {
        final color = resized.getPixel(x, y);
        letterbox.setPixel(offX + x, offY + y, color);
      }
    }

    return {
      'image': letterbox,
      'ratio': ratio,
      'offsetX': offX,
      'offsetY': offY,
    };
  }

  /// Construye el tensor de entrada [1, targetH, targetW, 3].
  /// Si es uint8 => [0..255], si es float => [0..1].
  static dynamic _buildInput(img.Image letterboxImage, int targetW, int targetH) {
    if (_inputType == TensorType.uint8) {
      return [
        List.generate(
          targetH,
          (y) => List.generate(
            targetW,
            (x) {
              final p = letterboxImage.getPixel(x, y);
              return [p.r.toInt(), p.g.toInt(), p.b.toInt()];
            },
          ),
        )
      ];
    } else {
      // float => normalizamos
      return [
        List.generate(
          targetH,
          (y) => List.generate(
            targetW,
            (x) {
              final p = letterboxImage.getPixel(x, y);
              return [
                p.r.toDouble() / 255.0,
                p.g.toDouble() / 255.0,
                p.b.toDouble() / 255.0
              ];
            },
          ),
        )
      ];
    }
  }
}
