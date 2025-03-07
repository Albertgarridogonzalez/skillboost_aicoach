import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../drawing_utils.dart';
import '../pose_estimator_image.dart';
import '../pose_utils.dart'; // Aquí se encuentra similarityTransformRefPose

class LivePoseAnalysisScreen extends StatefulWidget {
  const LivePoseAnalysisScreen({Key? key}) : super(key: key);

  @override
  _LivePoseAnalysisScreenState createState() => _LivePoseAnalysisScreenState();
}

class _LivePoseAnalysisScreenState extends State<LivePoseAnalysisScreen> {
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isProcessingFrame = false;

  // Cámara actual (frontal o trasera)
  CameraLensDirection _currentLens = CameraLensDirection.front;

  // Dimensiones de la imagen procesada
  int _analysisWidth = 0;
  int _analysisHeight = 0;

  // Pose en vivo (y suavizada)
  Map<String, Map<String, double>>? _livePose;
  Map<String, Map<String, double>>? _previousPose;

  // Limitador de FPS
  DateTime? _lastProcessedTime;
  final int _processingIntervalMs = 100; // ~10 fps

  // Pose de referencia (opcional)
  Uint8List? _refBytes;
  Map<String, Map<String, double>>? _refPose;
  int _refWidth = 0;
  int _refHeight = 0;

  // Colores para los overlays
  Color _refColor = Colors.green;
  Color _analysisColor = Colors.red;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  /// Inicializa la cámara.
  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    final CameraDescription selectedCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == _currentLens,
      orElse: () => cameras.first,
    );

    _cameraController = CameraController(
      selectedCamera,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    await _cameraController!.initialize();
    if (!mounted) return;

    setState(() {
      _isCameraInitialized = true;
      _analysisWidth = _cameraController!.value.previewSize?.width.toInt() ?? 0;
      _analysisHeight = _cameraController!.value.previewSize?.height.toInt() ?? 0;
    });

    // Inicia el stream de imágenes para análisis.
    _cameraController!.startImageStream(_processCameraImage);
  }

  /// Procesa cada frame de la cámara.
  Future<void> _processCameraImage(CameraImage image) async {
    final currentTime = DateTime.now();
    if (_lastProcessedTime != null &&
        currentTime.difference(_lastProcessedTime!).inMilliseconds <
            _processingIntervalMs) {
      return;
    }
    _lastProcessedTime = currentTime;

    if (_isProcessingFrame) return;
    _isProcessingFrame = true;

    try {
      // 1) Convierte CameraImage (YUV420) a JPEG
      Uint8List bytes = await _convertCameraImageToUint8List(image);

      // 2) Detecta la pose
      final result = await PoseEstimatorimage.detectPoseFromCameraImage(bytes);
      if (result != null) {
        Map<String, Map<String, double>> detectedPose =
            (result['pose'] as Map?)?.cast<String, Map<String, double>>() ?? {};

        // 3) Suavizado
        if (_previousPose != null) {
          detectedPose = _smoothPose(_previousPose!, detectedPose, 0.8);
        }

        setState(() {
          _livePose = detectedPose;
          _analysisWidth = result['width'] as int;
          _analysisHeight = result['height'] as int;
        });
        _previousPose = detectedPose;
      }
    } catch (e) {
      print("Error procesando frame: $e");
    } finally {
      _isProcessingFrame = false;
    }
  }

  /// Convierte un CameraImage (YUV420) a JPEG
  Future<Uint8List> _convertCameraImageToUint8List(CameraImage image) async {
    final width = image.width;
    final height = image.height;
    final uvRowStride = image.planes[1].bytesPerRow;
    final uvPixelStride = image.planes[1].bytesPerPixel!;

    final imgImage = img.Image(width: width, height: height);

    for (int y = 0; y < height; y++) {
      final uvRow = uvRowStride * (y >> 1);
      for (int x = 0; x < width; x++) {
        final uvPixel = uvRow + (x >> 1) * uvPixelStride;
        final index = y * width + x;
        final yVal = image.planes[0].bytes[index];
        final uVal = image.planes[1].bytes[uvPixel];
        final vVal = image.planes[2].bytes[uvPixel];

        int r = (yVal + (1.370705 * (vVal - 128))).round();
        int g = (yVal -
                (0.337633 * (uVal - 128)) -
                (0.698001 * (vVal - 128)))
            .round();
        int b = (yVal + (1.732446 * (uVal - 128))).round();
        r = r.clamp(0, 255);
        g = g.clamp(0, 255);
        b = b.clamp(0, 255);
        imgImage.setPixelRgb(x, y, r, g, b);
      }
    }
    return Uint8List.fromList(img.encodeJpg(imgImage));
  }

  /// Suaviza la pose para reducir saltos
  Map<String, Map<String, double>> _smoothPose(
    Map<String, Map<String, double>> previousPose,
    Map<String, Map<String, double>> currentPose,
    double alpha,
  ) {
    final result = <String, Map<String, double>>{};
    currentPose.forEach((key, currentCoords) {
      if (previousPose.containsKey(key)) {
        final prevCoords = previousPose[key]!;
        result[key] = {
          'x': prevCoords['x']! * alpha + currentCoords['x']! * (1 - alpha),
          'y': prevCoords['y']! * alpha + currentCoords['y']! * (1 - alpha),
          'score': currentCoords['score']!,
        };
      } else {
        result[key] = currentCoords;
      }
    });
    return result;
  }

  /// Cambia entre cámara frontal y trasera
  Future<void> _switchCamera() async {
    if (!_isCameraInitialized) return;
    await _cameraController?.stopImageStream();
    await _cameraController?.dispose();

    final cameras = await availableCameras();
    _currentLens = (_currentLens == CameraLensDirection.front)
        ? CameraLensDirection.back
        : CameraLensDirection.front;

    _initializeCamera();
  }

  /// Selecciona una imagen de referencia (opcional)
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
      _refPose = (result['pose'] as Map?)?.cast<String, Map<String, double>>();
      _refWidth = result['width'] as int;
      _refHeight = result['height'] as int;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Analizador en Vivo'),
        actions: [
          IconButton(
            icon: Icon(Icons.switch_camera),
            onPressed: _switchCamera,
            tooltip: 'Cambiar Cámara',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isCameraInitialized
                ? Stack(
                    children: [
                      CameraPreview(_cameraController!),
                      if (_livePose != null)
                        CustomPaint(
                          painter: _LivePosePainter(
                            livePose: _livePose!,
                            referencePose: _refPose,
                            analysisColor: _analysisColor,
                            refColor: _refColor,
                            imageWidth: _analysisWidth.toDouble(),
                            imageHeight: _analysisHeight.toDouble(),
                          ),
                          child: Container(),
                        ),
                    ],
                  )
                : Center(child: CircularProgressIndicator()),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: _pickReferenceImage,
                  child: Text('Img Referencia'),
                ),
                SizedBox(width: 20),
                ElevatedButton(
                  onPressed: _onDownloadPressed,
                  child: Text('Descargar Imagen'),
                ),
              ],
            ),
          ),
          SizedBox(height: 10),
        ],
      ),
    );
  }

  Future<void> _onDownloadPressed() async {
    // Aquí tu lógica para guardar la imagen con los overlays
    print("Implementa la función para guardar la imagen anotada.");
  }
}

/// --------------------------------------------------------------------------
/// PINTOR: flip horizontal de la pose en vivo y la referencia, luego transform
/// --------------------------------------------------------------------------
class _LivePosePainter extends CustomPainter {
  final Map<String, Map<String, double>> livePose;
  final Map<String, Map<String, double>>? referencePose;
  final Color analysisColor;
  final Color refColor;
  final double imageWidth;
  final double imageHeight;

  _LivePosePainter({
    required this.livePose,
    required this.analysisColor,
    required this.imageWidth,
    required this.imageHeight,
    this.referencePose,
    required this.refColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1) Calcula factores de escala
    final double scaleX = size.width / imageWidth;
    final double scaleY = size.height / imageHeight;

    // 2) Haz flip horizontal a la pose en vivo
    final flippedAnalysisPose = _flipHorizontalPose(livePose);

    // 3) Dibuja la pose en vivo ya espejada
    _drawPose(canvas, flippedAnalysisPose, analysisColor,
        scaleX: scaleX, scaleY: scaleY);

    // 4) Si hay pose de referencia, también la espejamos y luego la transformamos
    if (referencePose != null) {
      final flippedRefPose = _flipHorizontalPose(referencePose!);

      final transformedRefPose = similarityTransformRefPose(
        refPose: flippedRefPose,
        dstPose: flippedAnalysisPose,
      );

      // 5) Dibujamos la referencia transformada
      _drawPose(canvas, transformedRefPose, refColor.withOpacity(0.8),
          strokeWidth: 4, scaleX: scaleX, scaleY: scaleY);
    }
  }

  /// Flip horizontal en torno al bounding box de la pose
  Map<String, Map<String, double>> _flipHorizontalPose(
      Map<String, Map<String, double>> pose) {
    // 1) Calculamos minX y maxX
    double minX = double.infinity;
    double maxX = -double.infinity;
    for (final coords in pose.values) {
      final x = coords['x']!;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
    }
    final centerX = (minX + maxX) / 2;

    // 2) Reflejamos cada X
    final newPose = <String, Map<String, double>>{};
    pose.forEach((kp, coords) {
      final oldX = coords['x']!;
      final oldY = coords['y']!;
      final score = coords['score'] ?? 0.0;
      final newX = 2 * centerX - oldX;
      newPose[kp] = {'x': newX, 'y': oldY, 'score': score};
    });
    return newPose;
  }

  /// Dibuja la pose
  void _drawPose(Canvas canvas, Map<String, Map<String, double>> pose,
      Color color,
      {double strokeWidth = 3,
      required double scaleX,
      required double scaleY}) {
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
        Offset(p1['x']! * scaleX, p1['y']! * scaleY),
        Offset(p2['x']! * scaleX, p2['y']! * scaleY),
        linePaint,
      );
    }

    void drawPoint(String kp) {
      if (!pose.containsKey(kp)) return;
      final p = pose[kp]!;
      canvas.drawCircle(
        Offset(p['x']! * scaleX, p['y']! * scaleY),
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

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
