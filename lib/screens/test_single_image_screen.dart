import 'dart:io';
import 'dart:typed_data';
import 'dart:async'; // Para Completer
import 'dart:math' as math; // Para min, max, etc.
import 'dart:ui' as ui; // Para ui.Image, decodeImageFromList

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;

import '../pose_estimator_image.dart';

class TestSingleImageScreen extends StatefulWidget {
  const TestSingleImageScreen({Key? key}) : super(key: key);

  @override
  _TestSingleImageScreenState createState() => _TestSingleImageScreenState();
}

class _TestSingleImageScreenState extends State<TestSingleImageScreen> {
  Uint8List? orientedBytes;
  Map<String, Map<String, double>>? poseMap;
  int origWidth = 0;
  int origHeight = 0;

  Future<void> _pickAndProcessImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final file = File(picked.path);

    // 1) Detectar la pose
    final result = await PoseEstimatorimage.detectPoseOnOrientedImage(file);
    if (result == null) {
      print("No se pudo detectar pose.");
      return;
    }

    // 2) Convertimos la imagen reorientada a bytes
    final orientedImage = result['image'] as img.Image;
    final bytes = Uint8List.fromList(img.encodeJpg(orientedImage));

    setState(() {
      orientedBytes = bytes;
      poseMap = result['pose'] as Map<String, Map<String, double>>;
      origWidth = result['width'] as int;
      origHeight = result['height'] as int;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Test Single Image Pose'),
      ),
      body: Column(
        children: [
          ElevatedButton(
            onPressed: _pickAndProcessImage,
            child: Text('Seleccionar Imagen'),
          ),
          Expanded(
            child: Center(
              child: (orientedBytes == null || poseMap == null)
                  ? Text('No se ha seleccionado ninguna imagen')
                  : SingleChildScrollView(
                      child: Container(
                        // Damos un alto fijo para que la imagen quepa
                        // y se pueda scrollear si es más grande.
                        width: MediaQuery.of(context).size.width,
                        height: MediaQuery.of(context).size.height * 0.7,
                        child: FutureBuilder<ui.Image>(
                          future: _decodeToUiImage(orientedBytes!),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) {
                              return Center(child: CircularProgressIndicator());
                            }
                            final uiImage = snapshot.data!;
                            return CustomPaint(
                              painter: SingleImagePainter(
                                uiImage: uiImage,
                                poseMap: poseMap!,
                                origWidth: origWidth,
                                origHeight: origHeight,
                                rotationDeg: -90, // Prueba con 90, -90, 180...
                                flipH:
                                    true, // Activa si lo ves en espejo horizontal
                                flipV:
                                    false, // Activa si necesitas espejo vertical
                              ),
                            );
                          },
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// Decodifica los bytes a un ui.Image asíncrono
  Future<ui.Image> _decodeToUiImage(Uint8List bytes) async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(bytes, (ui.Image img) {
      completer.complete(img);
    });
    return completer.future;
  }
}

class SingleImagePainter extends CustomPainter {
  final ui.Image uiImage;
  final Map<String, Map<String, double>> poseMap;
  final int origWidth;
  final int origHeight;

  // Par de ajustes para la pose
  final double rotationDeg; // rotación en grados (por ej. -90)
  final bool flipH; // voltear horizontal
  final bool flipV; // voltear vertical

  SingleImagePainter({
    required this.uiImage,
    required this.poseMap,
    required this.origWidth,
    required this.origHeight,
    this.rotationDeg = 0.0, // 0 => no rota
    this.flipH = false,
    this.flipV = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1) Calculamos la escala tipo BoxFit.contain
    final scale = math.min(size.width / origWidth, size.height / origHeight);
    final dx = (size.width - origWidth * scale) / 2;
    final dy = (size.height - origHeight * scale) / 2;

    final paint = Paint();

    // 2) Dibujamos la imagen tal cual (sin rotarla)
    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(scale, scale);
    canvas.drawImage(uiImage, const Offset(0, 0), paint);

    // 3) Antes de pintar la pose, aplicamos la rotación/flip que necesites
    //    para “alinear” los keypoints con la foto real.
    canvas.save();

    // Queremos rotar/voltear alrededor del centro de la imagen
    final cx = origWidth / 2.0;
    final cy = origHeight / 2.0;

    // a) Movemos el origen al centro
    canvas.translate(cx, cy);

    // b) Rotamos
    final rad = rotationDeg * math.pi / 180.0;
    canvas.rotate(rad);

    // c) Flip horizontal/vertical (opcional)
    if (flipH) {
      canvas.scale(-1, 1);
    }
    if (flipV) {
      canvas.scale(1, -1);
    }

    // d) Regresamos el origen al (0,0) de la imagen
    canvas.translate(-cx, -cy);

    // 4) Ahora pintamos los keypoints en el nuevo sistema de coordenadas
    _drawPose(canvas);

    // Cerramos los saves
    canvas.restore();
    canvas.restore();
  }

  void _drawPose(Canvas canvas) {
    // Tus conexiones
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

    final linePaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 3;

    final circlePaint = Paint()..color = Colors.red;

    void drawLine(String kp1, String kp2) {
      if (!poseMap.containsKey(kp1) || !poseMap.containsKey(kp2)) return;
      final p1 = poseMap[kp1]!;
      final p2 = poseMap[kp2]!;
      canvas.drawLine(
        Offset(p1['x']!, p1['y']!),
        Offset(p2['x']!, p2['y']!),
        linePaint,
      );
    }

    void drawPoint(String kp) {
      if (!poseMap.containsKey(kp)) return;
      final p = poseMap[kp]!;
      canvas.drawCircle(
        Offset(p['x']!, p['y']!),
        5,
        circlePaint,
      );
    }

    // Dibujamos huesos
    for (var pair in bonePairs) {
      drawLine(pair[0], pair[1]);
    }
    // Dibujamos puntos
    for (var kp in poseMap.keys) {
      drawPoint(kp);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
