import 'dart:typed_data';
import 'package:image/image.dart' as img;

class DrawingUtils {
  /// Decodifica [originalBytes] con package:image, dibuja líneas
  /// según [poseData], y retorna la imagen resultante como JPEG (Uint8List).
  static Future<Uint8List> annotateImage(
    Uint8List originalBytes,
    Map<String, dynamic> poseData,
  ) async {
    // Decodificar la imagen en una estructura de package:image
    final originalImage = img.decodeImage(originalBytes);
    if (originalImage == null) {
      return originalBytes;
    }

    // Convertir los keypoints a un Map con la forma:
    // { key: {"x": double, "y": double}, ... }
    final Map<String, Map<String, double>> points = {};
    poseData.forEach((key, value) {
      if (value is Map) {
        final x = value['x']?.toDouble() ?? 0.0;
        final y = value['y']?.toDouble() ?? 0.0;
        points[key] = {'x': x, 'y': y};
      }
    });

    // Ejemplo: dibuja una línea entre 'left_hip' y 'left_knee'
    if (points.containsKey('left_hip') && points.containsKey('left_knee')) {
      final hipX = points['left_hip']!['x']!.toInt();
      final hipY = points['left_hip']!['y']!.toInt();
      final kneeX = points['left_knee']!['x']!.toInt();
      final kneeY = points['left_knee']!['y']!.toInt();

      // Llama a la función drawLine usando parámetros nombrados.
      // Pasa la imagen como el primer argumento posicional.
      img.drawLine(
        originalImage,
        x1: hipX,
        y1: hipY,
        x2: kneeX,
        y2: kneeY,
        color: img.ColorRgb8(255, 0, 0), // Rojo
        thickness: 3,
      );
    }

    // Re-encodea la imagen a JPEG
    final annotatedBytes = img.encodeJpg(originalImage);
    return Uint8List.fromList(annotatedBytes);
  }
}
