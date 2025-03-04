import 'dart:typed_data';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

class DrawingUtils {
  /// Dibuja líneas y puntos sobre la misma imagen (en memoria) que le pasamos.
  /// Se asume que las coordenadas en poseData ya están en píxeles de esa imagen.
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

    // Imprimimos dimensiones de la imagen donde se va a dibujar
    print(
        "annotateImage -> width: ${originalImage.width}, height: ${originalImage.height}");

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

    // Dibujar los puntos de la pose principal
    for (var kp in points.keys) {
      drawPoint(kp);
    }

    // Dibujar los puntos de la pose de referencia (si existe)
    if (referencePose != null) {
      for (var kp in referencePoints.keys) {
        drawPoint(kp, isRef: true);
      }
    }

    // Codificamos la imagen final con los dibujos
    final annotatedBytes = img.encodeJpg(originalImage);
    return Uint8List.fromList(annotatedBytes);
  }

  /// Calcula el ángulo entre tres keypoints A, B, C (B es el vértice).
  static double computeAngle(
      String A, String B, String C, Map<String, Map<String, double>> points) {
    if (!points.containsKey(A) ||
        !points.containsKey(B) ||
        !points.containsKey(C)) {
      return 0.0;
    }

    final ax = points[A]!['x']!;
    final ay = points[A]!['y']!;
    final bx = points[B]!['x']!;
    final by = points[B]!['y']!;
    final cx = points[C]!['x']!;
    final cy = points[C]!['y']!;

    final bax = ax - bx;
    final bay = ay - by;
    final bcx = cx - bx;
    final bcy = cy - by;

    final dot = (bax * bcx) + (bay * bcy);
    final magBA = math.sqrt(bax * bax + bay * bay);
    final magBC = math.sqrt(bcx * bcx + bcy * bcy);
    if (magBA == 0 || magBC == 0) return 0.0;

    final cosAngle = dot / (magBA * magBC);
    final clamped = cosAngle.clamp(-1.0, 1.0) as double;
    final angleRad = math.acos(clamped);
    return angleRad * (180.0 / math.pi);
  }

  /// (Opcional) Traslada la pose para anclarla a la cadera, etc.
  static Map<String, Map<String, double>> translateToHip(
    Map<String, Map<String, double>> points,
    String hipName,
  ) {
    if (!points.containsKey(hipName)) return points;
    final hipX = points[hipName]!['x']!;
    final hipY = points[hipName]!['y']!;

    final Map<String, Map<String, double>> translated = {};
    points.forEach((key, val) {
      translated[key] = {
        'x': val['x']! - hipX,
        'y': val['y']! - hipY,
      };
    });
    return translated;
  }
}
