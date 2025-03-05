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
import '../image_downloader.dart';
//import 'package:image_gallery_saver/image_gallery_saver.dart';
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
              rotationDeg: -90, // Ajusta según sea necesario
              flipH: true,
              flipV: false,
              angleTextColor:
                  Colors.yellow, // Por ejemplo, para el texto de ángulos
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

  Future<Directory> _getDownloadDirectory() async {
    final Directory? extDir = await getExternalStorageDirectory();
    if (extDir == null)
      throw Exception("No se pudo obtener el almacenamiento externo");
    // Extraer la parte de la ruta hasta 'Android'
    final List<String> paths = extDir.path.split("/");
    String newPath = "";
    for (int i = 1; i < paths.length; i++) {
      if (paths[i] == "Android") break;
      newPath += "/${paths[i]}";
    }
    // Agregamos la carpeta de descargas
    newPath = "$newPath/Download";
    return Directory(newPath);
  }
  Future<Uint8List> _uiImageToPng(ui.Image image) async {
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}
Future<bool> _requestStoragePermission() async {
  PermissionStatus status = await Permission.storage.status;

  // Si el permiso está denegado, solicitarlo
  if (status.isDenied || status.isRestricted) {
    status = await Permission.storage.request();
    //await openAppSettings();
  }

  // Si está denegado permanentemente, abrir configuración
  if (status.isPermanentlyDenied) {
    print("⚠️ Permiso de almacenamiento denegado permanentemente. Abriendo configuración...");
    await openAppSettings();
    return false;
  }

  // Verificar si se concedió el permiso
  if (status.isGranted) {
    print("✅ Permiso de almacenamiento concedido.");
    return true;
  } else {
    print("❌ Permiso de almacenamiento no concedido.");
    return false;
  }
}


  // --- Botón Descargar: reconstruye la imagen final y la guarda en Downloads ---
   Future<void> _onDownloadPressed() async {
    
    // Solicita permisos antes de proceder
    //bool hasPermission = await _requestStoragePermission();
    //if (!hasPermission) {
    //  ScaffoldMessenger.of(context).showSnackBar(
    //    SnackBar(content: Text('Permiso de almacenamiento denegado')),
    //  );
    //  return;
    //}

    try {
      final recordedImage = await _buildAnnotatedImage();
      final pngBytes = await _uiImageToPng(recordedImage);
      
      // Usamos la función que construye la ruta deseada o una ruta fija
      final directory = await _getDownloadDirectory(); // o usa una ruta fija si lo prefieres
      final path = directory.path;
      print("Guardando en: $path");
      
      final fileName = 'pose_comparison_${DateTime.now().millisecondsSinceEpoch}.png';
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

    // Definimos un extra de altura para el bloque de texto (por ejemplo, 150 px)
    final extraHeight = 150;
    final finalWidth = _analysisWidth.toDouble();
    final finalHeight = _analysisHeight.toDouble() + extraHeight;

    // Creamos un PictureRecorder con la nueva altura
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, finalWidth, finalHeight),
    );

    // Dibujamos la imagen de análisis con las poses en la parte superior (1:1)
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
      fitContain: false, // Dibujar 1:1
      rotationDeg: -90,
      flipH: true,
      flipV: false,
      angleTextColor: Colors.yellow,
    );
    painter.paint(
        canvas, Size(_analysisWidth.toDouble(), _analysisHeight.toDouble()));

    // Calculamos los ángulos para ambas poses (si existen)
    final analysisAngles =
        _analysisPose != null ? computePoseAngles(_analysisPose!) : {};
    final refAngles = _refPose != null ? computePoseAngles(_refPose!) : {};

    // Construimos el texto a mostrar en el bloque inferior.
    // Por ejemplo, mostramos ángulos para "Rodilla Derecha", "Rodilla Izquierda", "Cadera Derecha", "Cadera Izquierda".
    // Puedes modificar los keypoints y el formato según necesites.
    String text = '';
    if (refAngles.isNotEmpty) {
      text += 'Referencia:\n';
      refAngles.forEach((key, value) {
        text += '$key: ${value.toStringAsFixed(1)}°\n';
      });
    }
    if (analysisAngles.isNotEmpty) {
      text += '\nAnálisis:\n';
      analysisAngles.forEach((key, value) {
        text += '$key: ${value.toStringAsFixed(1)}°\n';
      });
    }

    // Configuramos el estilo del texto (en negrita, mayor tamaño y con el color configurado)
    final paragraphStyle = ui.ParagraphStyle(
      textAlign: TextAlign.left,
    );
    final textStyle = ui.TextStyle(
      color: Colors.yellow,
      fontSize: 18,
      fontWeight: FontWeight.bold,
    );
    final paragraphBuilder = ui.ParagraphBuilder(paragraphStyle)
      ..pushStyle(textStyle)
      ..addText(text);
    final paragraph = paragraphBuilder.build();
    // Ajustamos el ancho del párrafo al ancho de la imagen
    paragraph.layout(ui.ParagraphConstraints(width: finalWidth));

    // Dibujamos el párrafo en la parte inferior del canvas.
    // Por ejemplo, en la posición (0, _analysisHeight + 10)
    canvas.drawParagraph(
        paragraph, Offset(10, _analysisHeight.toDouble() + 10));

    final picture = recorder.endRecording();
    return picture.toImage(finalWidth.toInt(), finalHeight.toInt());
  }

  /// Función auxiliar para calcular algunos ángulos de interés de una pose.
  /// Devuelve un Map con nombres de ángulos y sus valores en grados.
  Map<String, double> computePoseAngles(Map<String, Map<String, double>> pose) {
    Map<String, double> angles = {};

    // Ejemplo: Rodilla izquierda: ángulo entre leftHip, leftKnee, leftAnkle.
    if (pose.containsKey('leftHip') &&
        pose.containsKey('leftKnee') &&
        pose.containsKey('leftAnkle')) {
      final angleLeftKnee = computeAngle(
        Offset(pose['leftHip']!['x']!, pose['leftHip']!['y']!),
        Offset(pose['leftKnee']!['x']!, pose['leftKnee']!['y']!),
        Offset(pose['leftAnkle']!['x']!, pose['leftAnkle']!['y']!),
      );
      angles['Rodilla Izquierda'] = angleLeftKnee;
    }
    // Ejemplo: Rodilla derecha: ángulo entre rightHip, rightKnee, rightAnkle.
    if (pose.containsKey('rightHip') &&
        pose.containsKey('rightKnee') &&
        pose.containsKey('rightAnkle')) {
      final angleRightKnee = computeAngle(
        Offset(pose['rightHip']!['x']!, pose['rightHip']!['y']!),
        Offset(pose['rightKnee']!['x']!, pose['rightKnee']!['y']!),
        Offset(pose['rightAnkle']!['x']!, pose['rightAnkle']!['y']!),
      );
      angles['Rodilla Derecha'] = angleRightKnee;
    }
    // Ejemplo: Cadera izquierda: ángulo entre leftShoulder, leftHip, leftKnee.
    if (pose.containsKey('leftShoulder') &&
        pose.containsKey('leftHip') &&
        pose.containsKey('leftKnee')) {
      final angleLeftHip = computeAngle(
        Offset(pose['leftShoulder']!['x']!, pose['leftShoulder']!['y']!),
        Offset(pose['leftHip']!['x']!, pose['leftHip']!['y']!),
        Offset(pose['leftKnee']!['x']!, pose['leftKnee']!['y']!),
      );
      angles['Cadera Izquierda'] = angleLeftHip;
    }
    // Ejemplo: Cadera derecha: ángulo entre rightShoulder, rightHip, rightKnee.
    if (pose.containsKey('rightShoulder') &&
        pose.containsKey('rightHip') &&
        pose.containsKey('rightKnee')) {
      final angleRightHip = computeAngle(
        Offset(pose['rightShoulder']!['x']!, pose['rightShoulder']!['y']!),
        Offset(pose['rightHip']!['x']!, pose['rightHip']!['y']!),
        Offset(pose['rightKnee']!['x']!, pose['rightKnee']!['y']!),
      );
      angles['Cadera Derecha'] = angleRightHip;
    }
    return angles;
  }

  /// Función auxiliar para calcular el ángulo entre tres puntos A, B (vértice) y C.
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
/// Función auxiliar para calcular el ángulo entre tres puntos A, B (vértice) y C
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

/// Transforma un punto [pt] aplicando rotación y flips alrededor del centro [center].
Offset transformPoint(
    Offset pt, Offset center, double rad, bool flipH, bool flipV) {
  // Traslada al origen
  final x0 = pt.dx - center.dx;
  final y0 = pt.dy - center.dy;
  // Aplica rotación
  final x1 = x0 * math.cos(rad) - y0 * math.sin(rad);
  final y1 = x0 * math.sin(rad) + y0 * math.cos(rad);
  // Aplica flip
  final x2 = flipH ? -x1 : x1;
  final y2 = flipV ? -y1 : y1;
  // Vuelve a trasladar
  return Offset(x2 + center.dx, y2 + center.dy);
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

  // Parámetros para transformar la pose (rotación y flip)
  final double rotationDeg;
  final bool flipH;
  final bool flipV;

  // Nuevo parámetro para el texto de los ángulos
  final Color angleTextColor;

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
    this.angleTextColor = Colors.white,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (fitContain) {
      final scale =
          math.min(size.width / analysisWidth, size.height / analysisHeight);
      final dx = (size.width - analysisWidth * scale) / 2;
      final dy = (size.height - analysisHeight * scale) / 2;
      canvas.save();
      canvas.translate(dx, dy);
      canvas.scale(scale, scale);
      canvas.drawImage(analysisImage, Offset.zero, Paint());
      _drawTransformedPoses(
          canvas, analysisWidth.toDouble(), analysisHeight.toDouble());
      canvas.restore();
    } else {
      canvas.drawImage(analysisImage, Offset.zero, Paint());
      _drawTransformedPoses(
          canvas, analysisWidth.toDouble(), analysisHeight.toDouble());
    }
  }

  void _drawTransformedPoses(Canvas canvas, double w, double h) {
    // Escalar la pose de referencia (si existe) al espacio de la imagen de análisis
    Map<String, Map<String, double>>? scaledRefPose;
    if (referencePose != null) {
      scaledRefPose = _scalePose(referencePose!, refWidth, refHeight, w, h);
    }
    final scaledAnalysisPose = analysisPose;

    // Alinear la pose de referencia con la de análisis usando el keypoint ancla
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

    // Guardamos el canvas y aplicamos la transformación a los keypoints
    canvas.save();
    final cx = w / 2;
    final cy = h / 2;
    canvas.translate(cx, cy);
    final rad = rotationDeg * math.pi / 180.0;
    canvas.rotate(rad);
    if (flipH) canvas.scale(-1, 1);
    if (flipV) canvas.scale(1, -1);
    canvas.translate(-cx, -cy);

    // Dibujar las poses transformadas
    _drawPose(canvas, scaledAnalysisPose, analysisColor, strokeWidth: 3);
    if (scaledRefPose != null) {
      _drawPose(canvas, scaledRefPose, refColor.withOpacity(0.8),
          strokeWidth: 4);
    }
    // Recuperamos la transformación aplicada para los keypoints
    canvas.restore();

    // Ahora, dibujamos los ángulos en modo "upright", sin rotación ni flip.
    // Para ello, usamos la misma transformación pero la invertimos para el texto.
    _drawAnglesGlobal(canvas, w, h, rad, flipH, flipV);
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

  void _drawPose(
      Canvas canvas, Map<String, Map<String, double>> pose, Color color,
      {double strokeWidth = 3}) {
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

  /// Dibuja los ángulos en modo global (sin la rotación/flip) usando
  /// la transformación inversa para que el texto aparezca upright.
  void _drawAnglesGlobal(
      Canvas canvas, double w, double h, double rad, bool flipH, bool flipV) {
    // Para cada ángulo que nos interese, calculamos la posición global del vértice
    // usando la misma transformación aplicada a los keypoints, pero sin ella en el dibujo.
    // Por ejemplo, para la cadera izquierda: entre leftShoulder, leftHip, leftKnee.
    // Y para la rodilla izquierda: entre leftHip, leftKnee, leftAnkle.
    // Puedes extender esto a otros ángulos.

    // Definimos el centro de la imagen (en el espacio de dibujo: w x h)
    final center = Offset(w / 2, h / 2);
    // Preparamos el texto (bold, mayor tamaño)
    final textStyle = ui.TextStyle(
      color: angleTextColor,
      fontSize: 18,
      fontWeight: FontWeight.bold,
    );

    // Función para transformar un punto del sistema original usando la transformación aplicada
    Offset transformPoint(Offset pt) {
      // Traslada al centro
      final x0 = pt.dx - center.dx;
      final y0 = pt.dy - center.dy;
      // Aplica rotación
      final x1 = x0 * math.cos(rad) - y0 * math.sin(rad);
      final y1 = x0 * math.sin(rad) + y0 * math.cos(rad);
      // Aplica flip si corresponde
      final x2 = flipH ? -x1 : x1;
      final y2 = flipV ? -y1 : y1;
      // Vuelve a trasladar
      return Offset(x2 + center.dx, y2 + center.dy);
    }

    // Para dibujar el ángulo en forma upright, calculamos la posición global del vértice (B) y luego
    // dibujamos el texto sin transformación.
    // Ejemplo para ángulo de cadera izquierda (entre leftShoulder, leftHip, leftKnee)
    if (analysisPose.containsKey('leftShoulder') &&
        analysisPose.containsKey('leftHip') &&
        analysisPose.containsKey('leftKnee')) {
      final A = Offset(analysisPose['leftShoulder']!['x']!,
          analysisPose['leftShoulder']!['y']!);
      final B = Offset(
          analysisPose['leftHip']!['x']!, analysisPose['leftHip']!['y']!);
      final C = Offset(
          analysisPose['leftKnee']!['x']!, analysisPose['leftKnee']!['y']!);
      final angle = computeAngle(A, B, C);
      final para = _buildParagraph('${angle.toStringAsFixed(1)}°', textStyle);
      // Transformamos B para obtener su posición global en la imagen dibujada
      final globalB = transformPoint(B);
      canvas.drawParagraph(para, globalB);
    }

    // Ejemplo para ángulo de rodilla izquierda (entre leftHip, leftKnee, leftAnkle)
    if (analysisPose.containsKey('leftHip') &&
        analysisPose.containsKey('leftKnee') &&
        analysisPose.containsKey('leftAnkle')) {
      final A = Offset(
          analysisPose['leftHip']!['x']!, analysisPose['leftHip']!['y']!);
      final B = Offset(
          analysisPose['leftKnee']!['x']!, analysisPose['leftKnee']!['y']!);
      final C = Offset(
          analysisPose['leftAnkle']!['x']!, analysisPose['leftAnkle']!['y']!);
      final angle = computeAngle(A, B, C);
      final para = _buildParagraph('${angle.toStringAsFixed(1)}°', textStyle);
      final globalB = transformPoint(B);
      canvas.drawParagraph(para, globalB);
    }
  }

  ui.Paragraph _buildParagraph(String text, ui.TextStyle style) {
    final paragraphStyle =
        ui.ParagraphStyle(textAlign: TextAlign.center, maxLines: 1);
    final builder = ui.ParagraphBuilder(paragraphStyle)
      ..pushStyle(style)
      ..addText(text);
    final paragraph = builder.build();
    paragraph.layout(ui.ParagraphConstraints(width: 60));
    return paragraph;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
