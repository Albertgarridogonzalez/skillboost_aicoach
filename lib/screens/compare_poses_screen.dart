import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

// Importa tu modelo o clase de detección de pose
import '../pose_estimator_image.dart';

class ComparePosesScreen extends StatefulWidget {
  const ComparePosesScreen({Key? key}) : super(key: key);

  @override
  _ComparePosesScreenState createState() => _ComparePosesScreenState();
}

class _ComparePosesScreenState extends State<ComparePosesScreen> {
  // Imagen y pose de referencia
  Uint8List? _refBytes;
  Map<String, Map<String, double>>? _refPose;
  int _refWidth = 0;
  int _refHeight = 0;

  // Imagen y pose a analizar
  Uint8List? _analysisBytes;
  Map<String, Map<String, double>>? _analysisPose;
  int _analysisWidth = 0;
  int _analysisHeight = 0;

  // Colores para las poses
  Color _refColor = Colors.green;
  Color _analysisColor = Colors.red;

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

  // Botones para seleccionar imágenes
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

  // Cuerpo: muestra la imagen de análisis con ambas poses sobrepuestas
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
              fitContain: true,
              rotationDeg: -90,
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

  // Dos color pickers
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

  Future<void> _onDownloadPressed() async {
    try {
      final recordedImage = await _buildAnnotatedImage();
      final pngBytes = await _uiImageToPng(recordedImage);

      final directory = await _getDownloadDirectory();
      final path = directory.path;
      final fileName =
          'pose_comparison_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File('$path/$fileName');
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
    final extraHeight = 150;
    final finalWidth = _analysisWidth.toDouble();
    final finalHeight = _analysisHeight.toDouble() + extraHeight;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, finalWidth, finalHeight),
    );

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
      fitContain: false,
      rotationDeg: 0,
      flipH: false,
      flipV: false,
    );
    painter.paint(canvas, Size(finalWidth, _analysisHeight.toDouble()));

    final picture = recorder.endRecording();
    return picture.toImage(finalWidth.toInt(), finalHeight.toInt());
  }

  Future<Directory> _getDownloadDirectory() async {
    final Directory? extDir = await getExternalStorageDirectory();
    if (extDir == null) {
      throw Exception("No se pudo obtener el almacenamiento externo");
    }
    final List<String> paths = extDir.path.split("/");
    String newPath = "";
    for (int i = 1; i < paths.length; i++) {
      if (paths[i] == "Android") break;
      newPath += "/${paths[i]}";
    }
    newPath = "$newPath/Download";
    return Directory(newPath);
  }

  Future<Uint8List> _uiImageToPng(ui.Image image) async {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

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

  Future<ui.Image> _decodeToUiImage(Uint8List bytes) async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(bytes, (ui.Image img) {
      completer.complete(img);
    });
    return completer.future;
  }
}

/// --------------------------------------------------------------------------
/// PINTOR: Dibuja la pose de análisis y la pose de referencia transformada
/// --------------------------------------------------------------------------
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

  final bool fitContain;
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
    this.fitContain = true,
    this.rotationDeg = 0.0,
    this.flipH = false,
    this.flipV = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (fitContain) {
      final scale = math.min(
        size.width / analysisWidth,
        size.height / analysisHeight,
      );
      final dx = (size.width - analysisWidth * scale) / 2;
      final dy = (size.height - analysisHeight * scale) / 2;

      canvas.save();
      canvas.translate(dx, dy);
      canvas.scale(scale, scale);
      canvas.drawImage(analysisImage, Offset.zero, Paint());

      _drawTransformedPoses(canvas,
          imageWidth: analysisWidth.toDouble(),
          imageHeight: analysisHeight.toDouble());
      canvas.restore();
    } else {
      canvas.drawImage(analysisImage, Offset.zero, Paint());
      _drawTransformedPoses(canvas,
          imageWidth: analysisWidth.toDouble(),
          imageHeight: analysisHeight.toDouble());
    }
  }

  void _drawTransformedPoses(Canvas canvas,
      {required double imageWidth, required double imageHeight}) {
    Map<String, Map<String, double>>? finalRefPose;
    if (referencePose != null) {
      // Seleccionamos la muñeca más cercana (con la heurística)
      final refFacingLeft = isFacingLeft(referencePose!);
      final refWrist = pickClosestWrist(referencePose!, refFacingLeft);
      // Usamos ambos tobillos (sin filtrar) de la referencia
      final refLeftAnkle = 'leftAnkle';
      final refRightAnkle = 'rightAnkle';

      // Para la pose de análisis, usamos la misma lógica para la muñeca
      final anFacingLeft = isFacingLeft(analysisPose);
      final anWrist = pickClosestWrist(analysisPose, anFacingLeft);
      // Y tomamos ambos tobillos de la pose de análisis
      final anLeftAnkle = 'leftAnkle';
      final anRightAnkle = 'rightAnkle';

      // Calculamos la transformación afín usando tres puntos:
      // [wrist, leftAnkle, rightAnkle]
      finalRefPose = affineTransformRefPoseByThreePoints(
        refPose: referencePose!,
        srcAnchors: {
          'wrist': Offset(referencePose![refWrist]!['x']!,
              referencePose![refWrist]!['y']!),
          'leftAnkle': Offset(referencePose!['leftAnkle']!['x']!,
              referencePose!['leftAnkle']!['y']!),
          'rightAnkle': Offset(referencePose!['rightAnkle']!['x']!,
              referencePose!['rightAnkle']!['y']!),
        },
        dstAnchors: {
          'wrist': Offset(analysisPose[anWrist]!['x']!,
              analysisPose[anWrist]!['y']!),
          'leftAnkle': Offset(analysisPose['leftAnkle']!['x']!,
              analysisPose['leftAnkle']!['y']!),
          'rightAnkle': Offset(analysisPose['rightAnkle']!['x']!,
              analysisPose['rightAnkle']!['y']!),
        },
      );
    }

    canvas.save();
    final cx = imageWidth / 2;
    final cy = imageHeight / 2;
    final rad = rotationDeg * math.pi / 180.0;
    canvas.translate(cx, cy);
    canvas.rotate(rad);
    if (flipH) canvas.scale(-1, 1);
    if (flipV) canvas.scale(1, -1);
    canvas.translate(-cx, -cy);

    _drawPose(canvas, analysisPose, analysisColor, strokeWidth: 3);
    if (finalRefPose != null) {
      _drawPose(canvas, finalRefPose, refColor.withOpacity(0.8),
          strokeWidth: 4);
    }
    canvas.restore();
  }

  void _drawPose(Canvas canvas, Map<String, Map<String, double>> pose,
      Color color, {
    double strokeWidth = 3,
  }) {
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth;
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
          Offset(p1['x']!, p1['y']!), Offset(p2['x']!, p2['y']!), linePaint);
    }

    void drawPoint(String kp) {
      if (!pose.containsKey(kp)) return;
      final p = pose[kp]!;
      canvas.drawCircle(Offset(p['x']!, p['y']!), 5, circlePaint);
    }

    for (var pair in bonePairs) {
      drawLine(pair[0], pair[1]);
    }
    for (var kp in pose.keys) {
      drawPoint(kp);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// --------------------------------------------------------------------------
/// FUNCIONES AUXILIARES PARA SELECCIÓN DE PUNTOS
/// --------------------------------------------------------------------------

bool isFacingLeft(Map<String, Map<String, double>> pose) {
  if (!pose.containsKey('leftHip') || !pose.containsKey('rightHip')) {
    return false;
  }
  final lx = pose['leftHip']!['x']!;
  final rx = pose['rightHip']!['x']!;
  return (lx < rx);
}

String pickClosestWrist(Map<String, Map<String, double>> pose, bool facingLeft) {
  if (!pose.containsKey('leftWrist') || !pose.containsKey('rightWrist')) {
    return 'rightWrist'; // fallback
  }
  final lwx = pose['leftWrist']!['x']!;
  final rwx = pose['rightWrist']!['x']!;
  if (facingLeft) {
    return (lwx < rwx) ? 'leftWrist' : 'rightWrist';
  } else {
    return (lwx > rwx) ? 'leftWrist' : 'rightWrist';
  }
}

/// --------------------------------------------------------------------------
/// FUNCIONES DE TRANSFORMACIÓN AFÍN (TRES PUNTOS)
/// --------------------------------------------------------------------------

/// Calcula la matriz afín 2x3 que transforma tres puntos fuente (src) en tres
/// puntos destino (dst). La matriz tendrá la forma:
/// [ [a, b, c],
///   [d, e, f] ]
List<List<double>> computeAffineTransformMatrix(
    List<Offset> src, List<Offset> dst) {
  final x1 = src[0].dx, y1 = src[0].dy;
  final x2 = src[1].dx, y2 = src[1].dy;
  final x3 = src[2].dx, y3 = src[2].dy;

  // Matriz de src: 3x3
  // | x1  y1  1 |
  // | x2  y2  1 |
  // | x3  y3  1 |
  final det = x1 * (y2 - y3) -
      y1 * (x2 - x3) +
      (x2 * y3 - x3 * y2);

  if (det == 0) {
    // Si es 0, no se puede invertir: devolvemos la transformación identidad
    return [
      [1, 0, 0],
      [0, 1, 0]
    ];
  }

  // Calculamos la matriz inversa de la matriz src.
  final m11 = (y2 - y3);
  final m12 = (x3 - x2);
  final m13 = (x2 * y3 - x3 * y2);

  final m21 = (y3 - y1);
  final m22 = (x1 - x3);
  final m23 = (x3 * y1 - x1 * y3);

  final m31 = (y1 - y2);
  final m32 = (x2 - x1);
  final m33 = (x1 * y2 - x2 * y1);

  // Para los parámetros a, b, c de la primera fila:
  final a = (m11 * dst[0].dx + m21 * dst[1].dx + m31 * dst[2].dx) / det;
  final b = (m12 * dst[0].dx + m22 * dst[1].dx + m32 * dst[2].dx) / det;
  final c = (m13 * dst[0].dx + m23 * dst[1].dx + m33 * dst[2].dx) / det;

  // Para la segunda fila: d, e, f
  final d = (m11 * dst[0].dy + m21 * dst[1].dy + m31 * dst[2].dy) / det;
  final e = (m12 * dst[0].dy + m22 * dst[1].dy + m32 * dst[2].dy) / det;
  final f = (m13 * dst[0].dy + m23 * dst[1].dy + m33 * dst[2].dy) / det;

  return [
    [a, b, c],
    [d, e, f]
  ];
}

/// Aplica la matriz afín a un punto (x, y)
Offset applyAffineTransform(Offset pt, List<List<double>> matrix) {
  final a = matrix[0][0];
  final b = matrix[0][1];
  final c = matrix[0][2];
  final d = matrix[1][0];
  final e = matrix[1][1];
  final f = matrix[1][2];

  final newX = a * pt.dx + b * pt.dy + c;
  final newY = d * pt.dx + e * pt.dy + f;
  return Offset(newX, newY);
}

/// Transforma la pose de referencia usando tres puntos de anclaje:
/// - Fuente (refPose): [wrist, leftAnkle, rightAnkle]
/// - Destino (analysisPose): [wrist, leftAnkle, rightAnkle]
///
/// Devuelve una nueva pose con la transformación afín aplicada.
Map<String, Map<String, double>> affineTransformRefPoseByThreePoints({
  required Map<String, Map<String, double>> refPose,
  required Map<String, Offset> srcAnchors, // Ej: {'wrist': ..., 'leftAnkle': ..., 'rightAnkle': ...}
  required Map<String, Offset> dstAnchors, // Ej: {'wrist': ..., 'leftAnkle': ..., 'rightAnkle': ...}
}) {
  // Construir listas de puntos (en el mismo orden)
  final List<Offset> srcPoints = [
    srcAnchors['wrist']!,
    srcAnchors['leftAnkle']!,
    srcAnchors['rightAnkle']!,
  ];
  final List<Offset> dstPoints = [
    dstAnchors['wrist']!,
    dstAnchors['leftAnkle']!,
    dstAnchors['rightAnkle']!,
  ];

  final matrix = computeAffineTransformMatrix(srcPoints, dstPoints);

  final Map<String, Map<String, double>> newPose = {};
  refPose.forEach((kp, coords) {
    final pt = Offset(coords['x']!, coords['y']!);
    final transformed = applyAffineTransform(pt, matrix);
    newPose[kp] = {'x': transformed.dx, 'y': transformed.dy};
  });

  return newPose;
}
