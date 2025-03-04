import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../pose_estimator_image.dart';

class ComparePosesScreen extends StatefulWidget {
  const ComparePosesScreen({Key? key}) : super(key: key);

  @override
  _ComparePosesScreenState createState() => _ComparePosesScreenState();
}

class _ComparePosesScreenState extends State<ComparePosesScreen> {
  // Datos de la imagen de referencia
  Uint8List? _refBytes;
  Map<String, Map<String, double>>? _refPose;
  int _refWidth = 0;
  int _refHeight = 0;

  // Datos de la imagen a analizar
  Uint8List? _analysisBytes;
  Map<String, Map<String, double>>? _analysisPose;
  int _analysisWidth = 0;
  int _analysisHeight = 0;

  // Colores para cada grupo
  Color _refColor = Colors.green; // Pose de referencia
  Color _analysisColor = Colors.red; // Pose de análisis

  // Keypoint de anclaje para alinear las poses (por ejemplo, 'leftWrist')
  final String _anchorKeypoint = 'rightWrist';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Comparar Poses'),
      ),
      body: Column(
        children: [
          _buildButtonsRow(),
          Expanded(child: _buildBody()),
          _buildColorPickers(),
          SizedBox(height: 10),
          ElevatedButton(
            onPressed: _onDownloadPressed,
            child: Text('Descargar Imagen'),
          ),
          SizedBox(height: 10),
        ],
      ),
    );
  }

  // --- Botones para seleccionar imágenes ---
  Widget _buildButtonsRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ElevatedButton(
          onPressed: _pickReferenceImage,
          child: Text('Seleccionar Imagen de Referencia'),
        ),
        SizedBox(width: 20),
        ElevatedButton(
          onPressed: _pickAnalysisImage,
          child: Text('Seleccionar Imagen a Analizar'),
        ),
      ],
    );
  }

  // --- Cuerpo: muestra la imagen de análisis con ambas poses sobrepuesta ---
  Widget _buildBody() {
    if (_analysisBytes == null || _analysisPose == null) {
      return Center(child: Text('No se ha seleccionado imagen a analizar'));
    }
    return FutureBuilder<ui.Image>(
      future: _decodeToUiImage(_analysisBytes!),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Center(child: CircularProgressIndicator());
        }
        final uiImage = snapshot.data!;
        return InteractiveViewer(
          minScale: 0.5,
          maxScale: 5.0,
          child: CustomPaint(
            painter: ComparePosesPainter(
              analysisImage: uiImage,
              analysisPose: _analysisPose!,
              analysisWidth: _analysisWidth,
              analysisHeight: _analysisHeight,
              referencePose: _refPose,
              refWidth: _refWidth.toDouble(),
              refHeight: _refHeight.toDouble(),
              refColor: _refColor,
              analysisColor: _analysisColor,
              anchorKeypoint: _anchorKeypoint,
              fitContain: true,
              rotationDeg: -90, // Ajusta según lo que necesites
              flipH: true,
              flipV: false,
            ),
            size: Size(
              MediaQuery.of(context).size.width,
              MediaQuery.of(context).size.height * 0.7,
            ),
          ),
        );
      },
    );
  }

  // --- Dos color pickers ---
  Widget _buildColorPickers() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildColorPickerButton(
          label: 'Color Referencia',
          currentColor: _refColor,
          onColorSelected: (c) {
            setState(() {
              _refColor = c;
            });
          },
        ),
        SizedBox(width: 20),
        _buildColorPickerButton(
          label: 'Color Análisis',
          currentColor: _analysisColor,
          onColorSelected: (c) {
            setState(() {
              _analysisColor = c;
            });
          },
        ),
      ],
    );
  }

  Widget _buildColorPickerButton({
    required String label,
    required Color currentColor,
    required ValueChanged<Color> onColorSelected,
  }) {
    return ElevatedButton(
      onPressed: () async {
        final c = await _showSimpleColorPicker(currentColor);
        if (c != null) {
          onColorSelected(c);
        }
      },
      child: Row(
        children: [
          Text(label),
          SizedBox(width: 10),
          Container(width: 24, height: 24, color: currentColor),
        ],
      ),
    );
  }

  Future<Color?> _showSimpleColorPicker(Color initial) async {
    final List<Color> colorOptions = [
      Colors.red,
      Colors.green,
      Colors.blue,
      Colors.orange,
      Colors.purple,
      Colors.pink,
      Colors.yellow,
      Colors.black,
    ];
    return showDialog<Color>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Elige un color'),
          content: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: colorOptions.map((c) {
              return GestureDetector(
                onTap: () => Navigator.of(ctx).pop(c),
                child: Container(
                  width: 36,
                  height: 36,
                  color: c,
                ),
              );
            }).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: Text('Cancelar'),
            ),
          ],
        );
      },
    );
  }

  // --- Botón Descargar: reconstruye la imagen final y la guarda en Downloads ---
  Future<void> _onDownloadPressed() async {
    if (_analysisBytes == null || _analysisPose == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No hay imagen para descargar')),
      );
      return;
    }
    Future<Uint8List> _uiImageToPng(ui.Image image) async {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData!.buffer.asUint8List();
    }

    try {
      final recordedImage = await _buildAnnotatedImage();
      final pngBytes = await _uiImageToPng(recordedImage);

      // Usamos una ruta fija para Android
      final downloadsPath = '/storage/emulated/0/Download';
      final fileName =
          'pose_comparison_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File('$downloadsPath/$fileName');
      await file.writeAsBytes(pngBytes);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imagen guardada en $fileName')),
      );
    } catch (e) {
      print("Error guardando imagen: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error guardando imagen: $e')),
      );
    }
  }

  Future<ui.Image> _buildAnnotatedImage() async {
    final uiImage = await _decodeToUiImage(_analysisBytes!);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(
          0, 0, _analysisWidth.toDouble(), _analysisHeight.toDouble()),
    );

    // Aquí usamos el mismo painter pero sin BoxFit (fitContain = false)
    final painter = ComparePosesPainter(
      analysisImage: uiImage,
      analysisPose: _analysisPose!,
      analysisWidth: _analysisWidth,
      analysisHeight: _analysisHeight,
      referencePose: _refPose,
      refWidth: _refWidth.toDouble(),
      refHeight: _refHeight.toDouble(),
      refColor: _refColor,
      analysisColor: _analysisColor,
      anchorKeypoint: _anchorKeypoint,
      fitContain: false,
    );
    painter.paint(
        canvas, Size(_analysisWidth.toDouble(), _analysisHeight.toDouble()));
    final picture = recorder.endRecording();
    return picture.toImage(_analysisWidth, _analysisHeight);
  }

  Future<ui.Image> _decodeToUiImage(Uint8List bytes) async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(bytes, (ui.Image img) {
      completer.complete(img);
    });
    return completer.future;
  }

  // --- Seleccionar Imagen de Referencia ---
  Future<void> _pickReferenceImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final file = File(picked.path);

    final result = await PoseEstimatorimage.detectPoseOnOrientedImage(file);
    if (result == null) {
      print("No se pudo detectar pose (referencia).");
      return;
    }
    final orientedImage = result['image'] as img.Image;
    final bytes = Uint8List.fromList(img.encodeJpg(orientedImage));
    setState(() {
      _refBytes = bytes;
      _refPose = result['pose'] as Map<String, Map<String, double>>;
      _refWidth = result['width'] as int;
      _refHeight = result['height'] as int;
    });
  }

  // --- Seleccionar Imagen a Analizar ---
  Future<void> _pickAnalysisImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final file = File(picked.path);

    final result = await PoseEstimatorimage.detectPoseOnOrientedImage(file);
    if (result == null) {
      print("No se pudo detectar pose (análisis).");
      return;
    }
    final orientedImage = result['image'] as img.Image;
    final bytes = Uint8List.fromList(img.encodeJpg(orientedImage));
    setState(() {
      _analysisBytes = bytes;
      _analysisPose = result['pose'] as Map<String, Map<String, double>>;
      _analysisWidth = result['width'] as int;
      _analysisHeight = result['height'] as int;
    });
  }
}

/*clase comparepainter*/
/// Función auxiliar para calcular el ángulo entre tres puntos A, B (vértice) y C
double computeAngle(Offset A, Offset B, Offset C) {
  final BA = A - B;
  final BC = C - B;
  final dot = BA.dx * BC.dx + BA.dy * BC.dy;
  final magBA = BA.distance;
  final magBC = BC.distance;
  if (magBA == 0 || magBC == 0) return 0.0;
  final cosAngle = dot / (magBA * magBC);
  // Aseguramos que el valor esté en [-1,1]
  final clamped = cosAngle.clamp(-1.0, 1.0);
  final angleRad = math.acos(clamped);
  return angleRad * 180 / math.pi;
}

class ComparePosesPainter extends CustomPainter {
  final ui.Image analysisImage;
  final Map<String, Map<String, double>> analysisPose;
  final int analysisWidth;
  final int analysisHeight;

  final Map<String, Map<String, double>>? referencePose;
  final double refWidth;
  final double refHeight;

  final Color refColor;
  final Color analysisColor;
  final String anchorKeypoint;
  final bool fitContain;

  // Parámetros para transformar la pose (rotación/flip)
  final double rotationDeg;
  final bool flipH;
  final bool flipV;

  ComparePosesPainter({
    required this.analysisImage,
    required this.analysisPose,
    required this.analysisWidth,
    required this.analysisHeight,
    this.referencePose,
    required this.refWidth,
    required this.refHeight,
    required this.refColor,
    required this.analysisColor,
    required this.anchorKeypoint,
    this.fitContain = true,
    this.rotationDeg = 0.0,
    this.flipH = false,
    this.flipV = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (fitContain) {
      final scale = math.min(size.width / analysisWidth, size.height / analysisHeight);
      final dx = (size.width - analysisWidth * scale) / 2;
      final dy = (size.height - analysisHeight * scale) / 2;
      canvas.save();
      canvas.translate(dx, dy);
      canvas.scale(scale, scale);
      canvas.drawImage(analysisImage, Offset.zero, Paint());
      _drawTransformedPoses(canvas, analysisWidth.toDouble(), analysisHeight.toDouble());
      canvas.restore();
    } else {
      canvas.drawImage(analysisImage, Offset.zero, Paint());
      _drawTransformedPoses(canvas, analysisWidth.toDouble(), analysisHeight.toDouble());
    }
  }

  void _drawTransformedPoses(Canvas canvas, double w, double h) {
    Map<String, Map<String, double>>? scaledRefPose;
    if (referencePose != null) {
      scaledRefPose = _scalePose(referencePose!, refWidth, refHeight, w, h);
    }
    final scaledAnalysisPose = analysisPose;

    // Alinear la pose de referencia usando el keypoint ancla
    if (scaledRefPose != null &&
        scaledRefPose.containsKey(anchorKeypoint) &&
        scaledAnalysisPose.containsKey(anchorKeypoint)) {
      final rx = scaledRefPose[anchorKeypoint]!['x']!;
      final ry = scaledRefPose[anchorKeypoint]!['y']!;
      final ax = scaledAnalysisPose[anchorKeypoint]!['x']!;
      final ay = scaledAnalysisPose[anchorKeypoint]!['y']!;
      final shiftX = ax - rx;
      final shiftY = ay - ry;
      scaledRefPose = _shiftPose(scaledRefPose, shiftX, shiftY);
    }

    canvas.save();
    // Aplicamos la transformación a los keypoints (rotación/flip)
    final cx = w / 2;
    final cy = h / 2;
    canvas.translate(cx, cy);
    final rad = rotationDeg * math.pi / 180.0;
    canvas.rotate(rad);
    if (flipH) canvas.scale(-1, 1);
    if (flipV) canvas.scale(1, -1);
    canvas.translate(-cx, -cy);

    // Dibujar poses
    _drawPose(canvas, scaledAnalysisPose, analysisColor, strokeWidth: 3);
    if (scaledRefPose != null) {
      _drawPose(canvas, scaledRefPose, refColor.withOpacity(0.8), strokeWidth: 4);
      _drawAngles(canvas, scaledRefPose, refColor.withOpacity(0.8));
    }
    _drawAngles(canvas, scaledAnalysisPose, analysisColor);
    canvas.restore();
  }

  Map<String, Map<String, double>> _scalePose(
    Map<String, Map<String, double>> pose,
    double wSrc,
    double hSrc,
    double wDst,
    double hDst,
  ) {
    if (wSrc == 0 || hSrc == 0) return pose;
    final scaleX = wDst / wSrc;
    final scaleY = hDst / hSrc;
    final Map<String, Map<String, double>> scaled = {};
    pose.forEach((kp, val) {
      scaled[kp] = {
        'x': val['x']! * scaleX,
        'y': val['y']! * scaleY,
      };
    });
    return scaled;
  }

  Map<String, Map<String, double>> _shiftPose(
      Map<String, Map<String, double>> pose, double shiftX, double shiftY) {
    final Map<String, Map<String, double>> shifted = {};
    pose.forEach((kp, val) {
      shifted[kp] = {
        'x': val['x']! + shiftX,
        'y': val['y']! + shiftY,
      };
    });
    return shifted;
  }

  void _drawPose(Canvas canvas, Map<String, Map<String, double>> pose, Color color, {double strokeWidth = 3}) {
    final linePaint = Paint()..color = color..strokeWidth = strokeWidth;
    final circlePaint = Paint()..color = color;

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

    void drawLine(String kp1, String kp2) {
      if (!pose.containsKey(kp1) || !pose.containsKey(kp2)) return;
      final p1 = pose[kp1]!;
      final p2 = pose[kp2]!;
      canvas.drawLine(
        Offset(p1['x']!, p1['y']!),
        Offset(p2['x']!, p2['y']!),
        linePaint,
      );
    }

    void drawPoint(String kp) {
      if (!pose.containsKey(kp)) return;
      final p = pose[kp]!;
      canvas.drawCircle(
        Offset(p['x']!, p['y']!),
        5,
        circlePaint,
      );
    }

    for (var pair in bonePairs) {
      drawLine(pair[0], pair[1]);
    }
    for (var kp in pose.keys) {
      drawPoint(kp);
    }
  }

  // Dibuja ángulos en ciertos keypoints, por ejemplo:
  // - Ángulo de la cadera: entre hombro, cadera y rodilla.
  // - Ángulo de la rodilla: entre cadera, rodilla y tobillo.
  // Ajusta los nombres de keypoints según tu modelo.
  void _drawAngles(Canvas canvas, Map<String, Map<String, double>> pose, Color color) {
    final textStyle = TextStyle(color: color, fontSize: 14);
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    
    // Ejemplo: ángulo de cadera izquierda: entre leftShoulder, leftHip, leftKnee.
    if (pose.containsKey('leftShoulder') &&
        pose.containsKey('leftHip') &&
        pose.containsKey('leftKnee')) {
      final A = Offset(pose['leftShoulder']!['x']!, pose['leftShoulder']!['y']!);
      final B = Offset(pose['leftHip']!['x']!, pose['leftHip']!['y']!);
      final C = Offset(pose['leftKnee']!['x']!, pose['leftKnee']!['y']!);
      final angle = computeAngle(A, B, C);
      textPainter.text = TextSpan(text: '${angle.toStringAsFixed(1)}°', style: textStyle);
      textPainter.layout();
      // Dibujamos el ángulo cerca de la cadera
      canvas.drawParagraph(
          _buildParagraph('${angle.toStringAsFixed(1)}°', color), Offset(B.dx, B.dy));
    }
    // Ejemplo: ángulo de rodilla izquierda: entre leftHip, leftKnee, leftAnkle.
    if (pose.containsKey('leftHip') &&
        pose.containsKey('leftKnee') &&
        pose.containsKey('leftAnkle')) {
      final A = Offset(pose['leftHip']!['x']!, pose['leftHip']!['y']!);
      final B = Offset(pose['leftKnee']!['x']!, pose['leftKnee']!['y']!);
      final C = Offset(pose['leftAnkle']!['x']!, pose['leftAnkle']!['y']!);
      final angle = computeAngle(A, B, C);
      textPainter.text = TextSpan(text: '${angle.toStringAsFixed(1)}°', style: textStyle);
      textPainter.layout();
      canvas.drawParagraph(
          _buildParagraph('${angle.toStringAsFixed(1)}°', color), Offset(B.dx, B.dy));
    }
  }

  ui.Paragraph _buildParagraph(String text, Color color) {
    final paragraphStyle = ui.ParagraphStyle(
      textAlign: TextAlign.center,
      maxLines: 1,
    );
    final textStyle = ui.TextStyle(
      color: color,
      fontSize: 14,
    );
    final paragraphBuilder = ui.ParagraphBuilder(paragraphStyle)
      ..pushStyle(textStyle)
      ..addText(text);
    final paragraph = paragraphBuilder.build();
    paragraph.layout(ui.ParagraphConstraints(width: 50));
    return paragraph;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}