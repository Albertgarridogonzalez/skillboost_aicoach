import 'dart:typed_data';
import 'dart:math' as math;
import 'package:image/image.dart' as img;
import 'dart:ui' as ui; // Usamos ui.Offset

class DrawingUtils {
  /// Dibuja líneas y puntos sobre la imagen (en memoria) a partir de los keypoints.
  /// (Este método se deja casi sin cambios; lo usamos para anotar la imagen si se desea).
  static Future<Uint8List> annotateImage(
    Uint8List originalBytes,
    Map<String, dynamic> poseData,
    Map<String, dynamic>? referencePose,
  ) async {
    final originalImage = img.decodeImage(originalBytes);
    if (originalImage == null) {
      print("No se pudo decodificar la imagen en annotateImage");
      return originalBytes;
    }
    // Se asume que poseData['x'] y poseData['y'] ya están en la escala de la imagen original.
    final Map<String, Map<String, double>> points = {};
    poseData.forEach((key, value) {
      if (value is Map) {
        final double rawX = (value['x'] ?? 0.0) as double;
        final double rawY = (value['y'] ?? 0.0) as double;
        points[key] = {'x': rawX, 'y': rawY};
      }
    });

    final Map<String, Map<String, double>> referencePoints = {};
    referencePose?.forEach((key, value) {
      if (value is Map) {
        final double rawX = (value['x'] ?? 0.0) as double;
        final double rawY = (value['y'] ?? 0.0) as double;
        referencePoints[key] = {'x': rawX, 'y': rawY};
      }
    });

    // Función para dibujar una línea entre dos keypoints
    void drawLineBetween(String kp1, String kp2, {bool isRef = false}) {
      final data = isRef ? referencePoints : points;
      if (data.containsKey(kp1) && data.containsKey(kp2)) {
        final x1 = data[kp1]!['x']!.toInt();
        final y1 = data[kp1]!['y']!.toInt();
        final x2 = data[kp2]!['x']!.toInt();
        final y2 = data[kp2]!['y']!.toInt();

        img.drawLine(
          originalImage,
          x1: x1,
          y1: y1,
          x2: x2,
          y2: y2,
          color: isRef
              ? img.ColorRgb8(0, 255, 0) // verde para la referencia
              : img.ColorRgb8(255, 0, 0), // rojo para la imagen principal
          thickness: 3,
        );
      }
    }

    // Función para dibujar un punto
    void drawPoint(String kp, {bool isRef = false}) {
      final data = isRef ? referencePoints : points;
      if (data.containsKey(kp)) {
        final x = data[kp]!['x']!.toInt();
        final y = data[kp]!['y']!.toInt();
        img.fillCircle(
          originalImage,
          x: x,
          y: y,
          radius: 5,
          color: isRef
              ? img.ColorRgb8(0, 255, 0)
              : img.ColorRgb8(255, 0, 0),
        );
      }
    }

    // Conexiones (huesos) entre keypoints
    const bonePairs = [
      ['leftShoulder', 'rightShoulder'],
      ['leftShoulder', 'leftHip'],
      ['rightShoulder', 'rightHip'],
      ['leftHip', 'rightHip'],
      ['leftShoulder', 'leftElbow'],
      ['leftElbow', 'leftWrist'],
      ['rightShoulder', 'rightElbow'],
      ['rightElbow', 'rightWrist'],
      ['leftHip', 'leftKnee'],
      ['leftKnee', 'leftAnkle'],
      ['rightHip', 'rightKnee'],
      ['rightKnee', 'rightAnkle'],
    ];

    // Dibujar las líneas (huesos)
    for (var pair in bonePairs) {
      drawLineBetween(pair[0], pair[1]);
      if (referencePose != null) {
        drawLineBetween(pair[0], pair[1], isRef: true);
      }
    }

    // Dibujar los puntos
    for (var kp in points.keys) {
      drawPoint(kp);
    }
    if (referencePose != null) {
      for (var kp in referencePoints.keys) {
        drawPoint(kp, isRef: true);
      }
    }

    // Codificamos y retornamos la imagen final
    final annotatedBytes = img.encodeJpg(originalImage);
    return Uint8List.fromList(annotatedBytes);
  }

  /// Calcula el ángulo entre tres puntos A, B (vértice) y C (en grados).
  static double computeAngle(ui.Offset A, ui.Offset B, ui.Offset C) {
    final BA = A - B;
    final BC = C - B;
    final dot = BA.dx * BC.dx + BA.dy * BC.dy;
    final magBA = BA.distance;
    final magBC = BC.distance;
    if (magBA == 0 || magBC == 0) return 0.0;
    final cosAngle = dot / (magBA * magBC);
    final clamped = cosAngle.clamp(-1.0, 1.0);
    final angleRad = math.acos(clamped);
    return angleRad * 180 / math.pi;
  }

  /// Calcula y devuelve los ángulos de la cadera y de la rodilla para cada lado.
  ///
  /// Las claves devueltas son:
  /// - "Cadera Izquierda": ángulo entre leftShoulder, leftHip y leftKnee.
  /// - "Cadera Derecha": ángulo entre rightShoulder, rightHip y rightKnee.
  /// - "Rodilla Izquierda": ángulo entre leftHip, leftKnee y leftAnkle.
  /// - "Rodilla Derecha": ángulo entre rightHip, rightKnee y rightAnkle.
  static Map<String, double> computeSelectedAngles(Map<String, Map<String, double>> pose) {
    Map<String, double> angles = {};

    if (pose.containsKey('leftShoulder') &&
        pose.containsKey('leftHip') &&
        pose.containsKey('leftKnee')) {
      angles['Cadera Izquierda'] = computeAngle(
        ui.Offset(pose['leftShoulder']!['x']!, pose['leftShoulder']!['y']!),
        ui.Offset(pose['leftHip']!['x']!, pose['leftHip']!['y']!),
        ui.Offset(pose['leftKnee']!['x']!, pose['leftKnee']!['y']!),
      );
    }

    if (pose.containsKey('rightShoulder') &&
        pose.containsKey('rightHip') &&
        pose.containsKey('rightKnee')) {
      angles['Cadera Derecha'] = computeAngle(
        ui.Offset(pose['rightShoulder']!['x']!, pose['rightShoulder']!['y']!),
        ui.Offset(pose['rightHip']!['x']!, pose['rightHip']!['y']!),
        ui.Offset(pose['rightKnee']!['x']!, pose['rightKnee']!['y']!),
      );
    }

    if (pose.containsKey('leftHip') &&
        pose.containsKey('leftKnee') &&
        pose.containsKey('leftAnkle')) {
      angles['Rodilla Izquierda'] = computeAngle(
        ui.Offset(pose['leftHip']!['x']!, pose['leftHip']!['y']!),
        ui.Offset(pose['leftKnee']!['x']!, pose['leftKnee']!['y']!),
        ui.Offset(pose['leftAnkle']!['x']!, pose['leftAnkle']!['y']!),
      );
    }

    if (pose.containsKey('rightHip') &&
        pose.containsKey('rightKnee') &&
        pose.containsKey('rightAnkle')) {
      angles['Rodilla Derecha'] = computeAngle(
        ui.Offset(pose['rightHip']!['x']!, pose['rightHip']!['y']!),
        ui.Offset(pose['rightKnee']!['x']!, pose['rightKnee']!['y']!),
        ui.Offset(pose['rightAnkle']!['x']!, pose['rightAnkle']!['y']!),
      );
    }

    return angles;
  }
}
