import 'dart:math' as math;
import 'dart:ui' as ui;

/// Aplica una transformación de similitud para alinear la pose de referencia
/// con la pose de destino. Se usan como anclaje los keypoints 'rightWrist',
/// 'leftAnkle' y 'rightAnkle'.
Map<String, Map<String, double>> similarityTransformRefPose({
  required Map<String, Map<String, double>> refPose,
  required Map<String, Map<String, double>> dstPose,
}) {
  // Extraemos los puntos ancla de la pose de referencia.
  List<ui.Offset> src = [
    ui.Offset(refPose['rightWrist']!['x']!, refPose['rightWrist']!['y']!),
    ui.Offset(refPose['leftAnkle']!['x']!, refPose['leftAnkle']!['y']!),
    ui.Offset(refPose['rightAnkle']!['x']!, refPose['rightAnkle']!['y']!),
  ];
  // Extraemos los puntos ancla correspondientes de la pose de destino.
  List<ui.Offset> dst = [
    ui.Offset(dstPose['rightWrist']!['x']!, dstPose['rightWrist']!['y']!),
    ui.Offset(dstPose['leftAnkle']!['x']!, dstPose['leftAnkle']!['y']!),
    ui.Offset(dstPose['rightAnkle']!['x']!, dstPose['rightAnkle']!['y']!),
  ];

  // Calculamos los centroides de ambos conjuntos.
  ui.Offset centroidSrc = ui.Offset(0, 0);
  ui.Offset centroidDst = ui.Offset(0, 0);
  for (var pt in src) {
    centroidSrc = ui.Offset(centroidSrc.dx + pt.dx, centroidSrc.dy + pt.dy);
  }
  for (var pt in dst) {
    centroidDst = ui.Offset(centroidDst.dx + pt.dx, centroidDst.dy + pt.dy);
  }
  centroidSrc = ui.Offset(centroidSrc.dx / src.length, centroidSrc.dy / src.length);
  centroidDst = ui.Offset(centroidDst.dx / dst.length, centroidDst.dy / dst.length);

  // Centramos los puntos.
  List<ui.Offset> srcCentered = src.map((pt) => pt - centroidSrc).toList();
  List<ui.Offset> dstCentered = dst.map((pt) => pt - centroidDst).toList();

  double A = 0, B = 0, normSrc = 0;
  for (int i = 0; i < srcCentered.length; i++) {
    A += srcCentered[i].dx * dstCentered[i].dx + srcCentered[i].dy * dstCentered[i].dy;
    B += srcCentered[i].dx * dstCentered[i].dy - srcCentered[i].dy * dstCentered[i].dx;
    normSrc += srcCentered[i].dx * srcCentered[i].dx + srcCentered[i].dy * srcCentered[i].dy;
  }
  double theta = math.atan2(B, A);
  double scale = (A * math.cos(theta) + B * math.sin(theta)) / normSrc;

  double cosTheta = math.cos(theta);
  double sinTheta = math.sin(theta);
  ui.Offset t = centroidDst - ui.Offset(
      scale * (cosTheta * centroidSrc.dx - sinTheta * centroidSrc.dy),
      scale * (sinTheta * centroidSrc.dx + cosTheta * centroidSrc.dy)
  );

  // Aplicamos la transformación a todos los keypoints de la pose de referencia.
  Map<String, Map<String, double>> newPose = {};
  refPose.forEach((kp, coords) {
    double x = coords['x']!;
    double y = coords['y']!;
    double newX = scale * (cosTheta * x - sinTheta * y) + t.dx;
    double newY = scale * (sinTheta * x + cosTheta * y) + t.dy;
    newPose[kp] = {'x': newX, 'y': newY};
  });

  return newPose;
}
