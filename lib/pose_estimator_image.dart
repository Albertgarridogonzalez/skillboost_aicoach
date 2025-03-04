import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

import 'drawing_utils.dart'; // Ajusta la ruta si está en otro directorio

class PoseEstimatorimage {
  static Interpreter? _interpreter;
  static TensorType? _inputType;

  static const double scoreThreshold = 0.0;

  /// Inicializa el intérprete una sola vez
  static Future<void> _initInterpreter() async {
    if (_interpreter == null) {
      // Carga tu modelo .tflite según corresponda
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

  /// NUEVO MÉTODO:
  /// 1) Lee el File de imagen.
  /// 2) Decodifica y aplica bakeOrientation para que quede físicamente derecha.
  /// 3) Corre la inferencia y obtiene la pose (coordenadas en la imagen reorientada).
  /// 4) Dibuja la pose sobre esa misma imagen reorientada.
  /// 5) Devuelve los bytes anotados (Uint8List) listos para mostrar en un Image.memory(...).
  static Future<Uint8List?> estimatePoseAndAnnotateFromFile(File file) async {
    await _initInterpreter();
    if (_interpreter == null) return null;

    // 1) Leer bytes y decodificar
    final originalBytes = await file.readAsBytes();
    final decoded = img.decodeImage(originalBytes);
    if (decoded == null) return null;

    // 2) Reorientar físicamente (bakeOrientation)
    final oriented = img.bakeOrientation(decoded);
    print("Oriented image size: ${oriented.width}x${oriented.height}");

    // 3) Inference: letterbox, buildInput, run...
    //    Obtenemos la pose en coordenadas de la imagen reorientada
    final poseMap = _estimatePoseFromImage(oriented);
    if (poseMap == null) {
      print("No pose detected or error in inference.");
      return null;
    }

    // 4) Dibujar la pose sobre la imagen reorientada
    //    - Re-encode oriented en bytes
    final orientedBytes = Uint8List.fromList(img.encodeJpg(oriented));
    final annotated = await DrawingUtils.annotateImage(
      orientedBytes,
      poseMap, // no hay pose de referencia
      null,
    );
    return annotated;
  }

  /// Inferencia "interna": dada una [img.Image] ya reorientada,
  /// corre el letterbox + run + remapeo y devuelve un Map con las coords.
  static Map<String, Map<String, double>>? _estimatePoseFromImage(img.Image oriented) {
    final origW = oriented.width;
    final origH = oriented.height;

    // 1) Obtener dims de entrada
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

    // 5) Run inference
    _interpreter!.run(inputTensor, output);
    //print("Raw output: $output");

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
        // descartar si quieres
      }

      final px = xNorm * targetW;
      final py = yNorm * targetH;

      double finalX = (px - offsetX) / ratio;
      double finalY = (py - offsetY) / ratio;

      // clamp
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

    //print("Pose: $poseMap");
    return poseMap;
  }

  /// Letterbox
  static Map<String, dynamic> _letterboxAndResize(
      img.Image src, int targetW, int targetH) {
    final origW = src.width;
    final origH = src.height;
    final ratio = math.min(targetW / origW, targetH / origH);
    final newW = (origW * ratio).round();
    final newH = (origH * ratio).round();

    final letterbox = img.Image(width: targetW, height: targetH);

    // fill black
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

  /// Construye el tensor 4D [1, targetH, targetW, 3]
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
      // float => normalizamos [0..1]
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
