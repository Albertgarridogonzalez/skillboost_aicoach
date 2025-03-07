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
import 'package:skillboost_aicoach/drawing_utils.dart';
import 'package:skillboost_aicoach/pose_utils.dart';

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
          _buildAnglesText(),
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
      Container(
        width: 160, // Ajusta el ancho según necesites
        child: ElevatedButton(
          onPressed: _pickReferenceImage,
          child: Text('Img Referencia'),
        ),
      ),
      SizedBox(width: 10),
      Container(
        width: 160, // Ajusta el ancho según necesites
        child: ElevatedButton(
          onPressed: _pickAnalysisImage,
          child: Text('Img Análisis'),
        ),
      ),
    ],
  );
}
Widget _buildAnglesText() {
  if (_analysisPose == null) return SizedBox();
  // Calculamos los ángulos para Análisis y Referencia (si está disponible)
  final analysisAngles = DrawingUtils.computeSelectedAngles(_analysisPose!);
  final refAngles = _refPose != null
      ? DrawingUtils.computeSelectedAngles(_refPose!)
      : {};

  // Creamos dos columnas: una para "Referencia" y otra para "Análisis"
  return Container(
    padding: EdgeInsets.all(8),
    color: Colors.white.withOpacity(0.8), // fondo para mejorar legibilidad
    child: Row(
      children: [
        // Columna izquierda: Referencia
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Referencia:",
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black)),
              Text("Cadera Izq: ${refAngles['Cadera Izquierda']?.toStringAsFixed(1) ?? '-'}°",
                  style: TextStyle(fontSize: 16, color: Colors.black)),
              Text("Cadera Der: ${refAngles['Cadera Derecha']?.toStringAsFixed(1) ?? '-'}°",
                  style: TextStyle(fontSize: 16, color: Colors.black)),
              Text("Rodilla Izq: ${refAngles['Rodilla Izquierda']?.toStringAsFixed(1) ?? '-'}°",
                  style: TextStyle(fontSize: 16, color: Colors.black)),
              Text("Rodilla Der: ${refAngles['Rodilla Derecha']?.toStringAsFixed(1) ?? '-'}°",
                  style: TextStyle(fontSize: 16, color: Colors.black)),
            ],
          ),
        ),
        // Columna derecha: Análisis
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Análisis:",
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black)),
              Text("Cadera Izq: ${analysisAngles['Cadera Izquierda']?.toStringAsFixed(1) ?? '-'}°",
                  style: TextStyle(fontSize: 16, color: Colors.black)),
              Text("Cadera Der: ${analysisAngles['Cadera Derecha']?.toStringAsFixed(1) ?? '-'}°",
                  style: TextStyle(fontSize: 16, color: Colors.black)),
              Text("Rodilla Izq: ${analysisAngles['Rodilla Izquierda']?.toStringAsFixed(1) ?? '-'}°",
                  style: TextStyle(fontSize: 16, color: Colors.black)),
              Text("Rodilla Der: ${analysisAngles['Rodilla Derecha']?.toStringAsFixed(1) ?? '-'}°",
                  style: TextStyle(fontSize: 16, color: Colors.black)),
            ],
          ),
        ),
      ],
    ),
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
            // En pantalla mostramos overlays (líneas y círculos)
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
              drawOverlays: true,
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
  // Altura extra para el bloque de texto
  final extraHeight = 150;
  final finalWidth = _analysisWidth.toDouble();
  final finalHeight = _analysisHeight.toDouble() + extraHeight.toDouble();

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, finalWidth, finalHeight));

  // Dibuja la imagen base sin overlays
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
    drawOverlays: false,
  );
  painter.paint(canvas, Size(finalWidth, _analysisHeight.toDouble()));

  // Calculamos los ángulos de cadera y rodilla para cada pose
  final analysisAngles = computeSelectedAngles(_analysisPose!);
  final refAngles = _refPose != null ? computeSelectedAngles(_refPose!) : {};

  // Imprime en consola para verificar
  print("Ángulos análisis: $analysisAngles");
  print("Ángulos referencia: $refAngles");

  // Creamos dos bloques de texto: uno para "Referencia" y otro para "Análisis"
  final refText = StringBuffer()..writeln("Referencia:");
  refText.writeln("Cadera Izq: ${refAngles['Cadera Izquierda']?.toStringAsFixed(1) ?? '-'}°");
  refText.writeln("Cadera Der: ${refAngles['Cadera Derecha']?.toStringAsFixed(1) ?? '-'}°");
  refText.writeln("Rodilla Izq: ${refAngles['Rodilla Izquierda']?.toStringAsFixed(1) ?? '-'}°");
  refText.writeln("Rodilla Der: ${refAngles['Rodilla Derecha']?.toStringAsFixed(1) ?? '-'}°");

  final analysisText = StringBuffer()..writeln("Análisis:");
  analysisText.writeln("Cadera Izq: ${analysisAngles['Cadera Izquierda']?.toStringAsFixed(1) ?? '-'}°");
  analysisText.writeln("Cadera Der: ${analysisAngles['Cadera Derecha']?.toStringAsFixed(1) ?? '-'}°");
  analysisText.writeln("Rodilla Izq: ${analysisAngles['Rodilla Izquierda']?.toStringAsFixed(1) ?? '-'}°");
  analysisText.writeln("Rodilla Der: ${analysisAngles['Rodilla Derecha']?.toStringAsFixed(1) ?? '-'}°");

  // Configuramos el estilo del texto y el ancho para cada columna
  final textStyle = ui.TextStyle(
    color: Colors.black, // Prueba con negro o cambia a otro color si es necesario
    fontSize: 18,
    fontWeight: FontWeight.bold,
  );
  final paragraphStyle = ui.ParagraphStyle(textAlign: TextAlign.left);
  final double columnWidth = finalWidth / 2 - 20;

  final refParagraphBuilder = ui.ParagraphBuilder(paragraphStyle)
    ..pushStyle(textStyle)
    ..addText(refText.toString());
  final refParagraph = refParagraphBuilder.build();
  refParagraph.layout(ui.ParagraphConstraints(width: columnWidth));

  final analysisParagraphBuilder = ui.ParagraphBuilder(paragraphStyle)
    ..pushStyle(textStyle)
    ..addText(analysisText.toString());
  final analysisParagraph = analysisParagraphBuilder.build();
  analysisParagraph.layout(ui.ParagraphConstraints(width: columnWidth));

  // (Opcional) Dibujar un fondo semitransparente para el bloque de texto
  final backgroundPaint = Paint()..color = Colors.white.withOpacity(0.7);
  canvas.drawRect(Rect.fromLTWH(0, _analysisHeight.toDouble(), finalWidth, extraHeight.toDouble()), backgroundPaint);

  // DESCOMENTA ESTA PARTE PARA PROBAR CON TEXTO FIJO:
  /*
  final testText = "Prueba de texto";
  final testParagraphBuilder = ui.ParagraphBuilder(paragraphStyle)
    ..pushStyle(textStyle)
    ..addText(testText);
  final testParagraph = testParagraphBuilder.build();
  testParagraph.layout(ui.ParagraphConstraints(width: columnWidth));
  canvas.drawParagraph(testParagraph, Offset(10, _analysisHeight.toDouble() + 10));
  */

  // Dibujamos los párrafos en la parte inferior de la imagen
  final double textY = _analysisHeight.toDouble() + 10;
  canvas.drawParagraph(refParagraph, Offset(10, textY));
  canvas.drawParagraph(analysisParagraph, Offset(finalWidth / 2 + 10, textY));

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
  // Nuevo parámetro para decidir si se dibujan los overlays (líneas y puntos)
  final bool drawOverlays;

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
    this.drawOverlays = true,
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
      // Usamos ambos tobillos y ambas muñecas como anclaje
      finalRefPose = similarityTransformRefPose(
        refPose: referencePose!,
        dstPose: analysisPose,
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

    if (drawOverlays) {
      _drawPose(canvas, analysisPose, analysisColor, strokeWidth: 3);
      if (finalRefPose != null) {
        _drawPose(canvas, finalRefPose, refColor.withOpacity(0.8), strokeWidth: 4);
      }
    }
    canvas.restore();
  }

  void _drawPose(Canvas canvas, Map<String, Map<String, double>> pose, Color color,
      {double strokeWidth = 3}) {
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
/// FUNCIONES AUXILIARES PARA LA TRANSFORMACIÓN DE SIMILITUD
/// --------------------------------------------------------------------------

/// Calcula una transformación de similitud (traslación, rotación y escala uniformes)
/// que alinea los cuatro keypoints: leftWrist, rightWrist, leftAnkle y rightAnkle
/// de la pose de referencia con los correspondientes en la pose de destino.
/// Calcula una transformación de similitud (traslación, rotación y escala uniformes)
/// que alinea los tres keypoints: rightWrist, leftAnkle y rightAnkle
/// de la pose de referencia con los correspondientes en la pose de destino.
//Map<String, Map<String, double>> similarityTransformRefPose({
//  required Map<String, Map<String, double>> refPose,
//  required Map<String, Map<String, double>> dstPose,
//}) {
//  // Extraemos los tres keypoints de la pose de referencia:
//  // Usamos rightWrist (siempre) y ambos tobillos.
//  List<ui.Offset> src = [
//    ui.Offset(refPose['rightWrist']!['x']!, refPose['rightWrist']!['y']!),
//    ui.Offset(refPose['leftAnkle']!['x']!, refPose['leftAnkle']!['y']!),
//    ui.Offset(refPose['rightAnkle']!['x']!, refPose['rightAnkle']!['y']!),
//  ];
//  // Y de la pose de destino, usamos los mismos keypoints.
//  List<ui.Offset> dst = [
//    ui.Offset(dstPose['rightWrist']!['x']!, dstPose['rightWrist']!['y']!),
//    ui.Offset(dstPose['leftAnkle']!['x']!, dstPose['leftAnkle']!['y']!),
//    ui.Offset(dstPose['rightAnkle']!['x']!, dstPose['rightAnkle']!['y']!),
//  ];
//
//  // Calculamos los centroides de cada conjunto.
//  ui.Offset centroidSrc = ui.Offset(0, 0);
//  ui.Offset centroidDst = ui.Offset(0, 0);
//  for (var pt in src) {
//    centroidSrc = ui.Offset(centroidSrc.dx + pt.dx, centroidSrc.dy + pt.dy);
//  }
//  for (var pt in dst) {
//    centroidDst = ui.Offset(centroidDst.dx + pt.dx, centroidDst.dy + pt.dy);
//  }
//  centroidSrc = ui.Offset(centroidSrc.dx / src.length, centroidSrc.dy / src.length);
//  centroidDst = ui.Offset(centroidDst.dx / dst.length, centroidDst.dy / dst.length);
//
//  // Centramos los puntos.
//  List<ui.Offset> srcCentered = src.map((pt) => pt - centroidSrc).toList();
//  List<ui.Offset> dstCentered = dst.map((pt) => pt - centroidDst).toList();
//
//  double A = 0, B = 0, normSrc = 0;
//  for (int i = 0; i < srcCentered.length; i++) {
//    A += srcCentered[i].dx * dstCentered[i].dx + srcCentered[i].dy * dstCentered[i].dy;
//    B += srcCentered[i].dx * dstCentered[i].dy - srcCentered[i].dy * dstCentered[i].dx;
//    normSrc += srcCentered[i].dx * srcCentered[i].dx + srcCentered[i].dy * srcCentered[i].dy;
//  }
//  double theta = math.atan2(B, A);
//  double scale = (A * math.cos(theta) + B * math.sin(theta)) / normSrc;
//
//  // Calculamos la traslación.
//  double cosTheta = math.cos(theta);
//  double sinTheta = math.sin(theta);
//  ui.Offset t = centroidDst - ui.Offset(
//      scale * (cosTheta * centroidSrc.dx - sinTheta * centroidSrc.dy),
//      scale * (sinTheta * centroidSrc.dx + cosTheta * centroidSrc.dy)
//  );
//
//  // Aplicamos la transformación a todos los keypoints de refPose.
//  Map<String, Map<String, double>> newPose = {};
//  refPose.forEach((kp, coords) {
//    double x = coords['x']!;
//    double y = coords['y']!;
//    double newX = scale * (cosTheta * x - sinTheta * y) + t.dx;
//    double newY = scale * (sinTheta * x + cosTheta * y) + t.dy;
//    newPose[kp] = {'x': newX, 'y': newY};
//  });
//
//  return newPose;
//}

/// --------------------------------------------------------------------------
/// FUNCIONES AUXILIARES (otras ya existentes)
/// --------------------------------------------------------------------------

bool isFacingLeft(Map<String, Map<String, double>> pose) {
  if (!pose.containsKey('leftHip') || !pose.containsKey('rightHip')) {
    return false;
  }
  final lx = pose['leftHip']!['x']!;
  final rx = pose['rightHip']!['x']!;
  return (lx < rx);
}

/// (Opcional) Transformación afín por tres puntos (se deja como referencia)
Map<String, Map<String, double>> affineTransformRefPoseByThreePoints({
  required Map<String, Map<String, double>> refPose,
  required Map<String, Offset> srcAnchors,
  required Map<String, Offset> dstAnchors,
}) {
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

/// Calcula la matriz afín 2x3 que transforma tres puntos fuente en tres puntos destino.
List<List<double>> computeAffineTransformMatrix(List<Offset> src, List<Offset> dst) {
  final x1 = src[0].dx, y1 = src[0].dy;
  final x2 = src[1].dx, y2 = src[1].dy;
  final x3 = src[2].dx, y3 = src[2].dy;

  final det = x1 * (y2 - y3) - y1 * (x2 - x3) + (x2 * y3 - x3 * y2);
  if (det == 0) {
    return [
      [1, 0, 0],
      [0, 1, 0]
    ];
  }

  final m11 = (y2 - y3);
  final m12 = (x3 - x2);
  final m13 = (x2 * y3 - x3 * y2);

  final m21 = (y3 - y1);
  final m22 = (x1 - x3);
  final m23 = (x3 * y1 - x1 * y3);

  final m31 = (y1 - y2);
  final m32 = (x2 - x1);
  final m33 = (x1 * y2 - x2 * y1);

  final a = (m11 * dst[0].dx + m21 * dst[1].dx + m31 * dst[2].dx) / det;
  final b = (m12 * dst[0].dx + m22 * dst[1].dx + m32 * dst[2].dx) / det;
  final c = (m13 * dst[0].dx + m23 * dst[1].dx + m33 * dst[2].dx) / det;
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
  final newX = matrix[0][0] * pt.dx + matrix[0][1] * pt.dy + matrix[0][2];
  final newY = matrix[1][0] * pt.dx + matrix[1][1] * pt.dy + matrix[1][2];
  return Offset(newX, newY);
}

/// --------------------------------------------------------------------------
/// FUNCIONES PARA CALCULAR ÁNGULOS (CADERA Y RODILLA)
/// --------------------------------------------------------------------------
/// Calcula el ángulo entre tres puntos A, B (vértice) y C (en grados)
double computeAngle(Offset A, Offset B, Offset C) {
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

/// Calcula los ángulos de la cadera y de la rodilla para cada lado
Map<String, double> computeSelectedAngles(Map<String, Map<String, double>> pose) {
  Map<String, double> angles = {};
  // Ángulo de cadera izquierda: entre leftShoulder, leftHip, leftKnee
  if (pose.containsKey('leftShoulder') &&
      pose.containsKey('leftHip') &&
      pose.containsKey('leftKnee')) {
    angles['Cadera Izquierda'] = computeAngle(
      Offset(pose['leftShoulder']!['x']!, pose['leftShoulder']!['y']!),
      Offset(pose['leftHip']!['x']!, pose['leftHip']!['y']!),
      Offset(pose['leftKnee']!['x']!, pose['leftKnee']!['y']!),
    );
  }
  // Ángulo de cadera derecha: entre rightShoulder, rightHip, rightKnee
  if (pose.containsKey('rightShoulder') &&
      pose.containsKey('rightHip') &&
      pose.containsKey('rightKnee')) {
    angles['Cadera Derecha'] = computeAngle(
      Offset(pose['rightShoulder']!['x']!, pose['rightShoulder']!['y']!),
      Offset(pose['rightHip']!['x']!, pose['rightHip']!['y']!),
      Offset(pose['rightKnee']!['x']!, pose['rightKnee']!['y']!),
    );
  }
  // Ángulo de rodilla izquierda: entre leftHip, leftKnee, leftAnkle
  if (pose.containsKey('leftHip') &&
      pose.containsKey('leftKnee') &&
      pose.containsKey('leftAnkle')) {
    angles['Rodilla Izquierda'] = computeAngle(
      Offset(pose['leftHip']!['x']!, pose['leftHip']!['y']!),
      Offset(pose['leftKnee']!['x']!, pose['leftKnee']!['y']!),
      Offset(pose['leftAnkle']!['x']!, pose['leftAnkle']!['y']!),
    );
  }
  // Ángulo de rodilla derecha: entre rightHip, rightKnee, rightAnkle
  if (pose.containsKey('rightHip') &&
      pose.containsKey('rightKnee') &&
      pose.containsKey('rightAnkle')) {
    angles['Rodilla Derecha'] = computeAngle(
      Offset(pose['rightHip']!['x']!, pose['rightHip']!['y']!),
      Offset(pose['rightKnee']!['x']!, pose['rightKnee']!['y']!),
      Offset(pose['rightAnkle']!['x']!, pose['rightAnkle']!['y']!),
    );
  }
  return angles;
}
