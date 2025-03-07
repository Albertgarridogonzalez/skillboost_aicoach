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

  // Último frame procesado
  Uint8List? _latestFrameBytes;
  int _analysisWidth = 0;
  int _analysisHeight = 0;

  // Pose detectada en vivo
  Map<String, Map<String, double>>? _livePose;

  // Imagen y pose de referencia seleccionada
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

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    // Selecciona la cámara según _currentLens
    final CameraDescription selectedCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == _currentLens,
      orElse: () => cameras.first,
    );

    _cameraController = CameraController(
      selectedCamera,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    await _cameraController?.initialize();
    if (!mounted) return;

    setState(() {
      _isCameraInitialized = true;
      _analysisWidth =
          _cameraController!.value.previewSize?.width.toInt() ?? 0;
      _analysisHeight =
          _cameraController!.value.previewSize?.height.toInt() ?? 0;
    });

    // Inicia el stream de imágenes para análisis en vivo.
    _cameraController!.startImageStream(_processCameraImage);
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_isProcessingFrame) return;
    _isProcessingFrame = true;

    try {
      // Convierte CameraImage (YUV420) a Uint8List JPEG
      Uint8List bytes = await convertCameraImageToUint8List(image);
      _latestFrameBytes = bytes;

      // Detecta la pose en la imagen convertida
      final result = await PoseEstimatorimage.detectPoseFromCameraImage(bytes);
      if (result != null) {
        setState(() {
          _livePose =
              (result['pose'] as Map?)?.cast<String, Map<String, double>>();
          _analysisWidth = result['width'] as int;
          _analysisHeight = result['height'] as int;
        });
      }
    } catch (e) {
      print("Error procesando frame: $e");
    } finally {
      _isProcessingFrame = false;
    }
  }

  /// Convierte un CameraImage (formato YUV420) a una imagen JPEG en Uint8List.
  Future<Uint8List> convertCameraImageToUint8List(CameraImage image) async {
    final int width = image.width;
    final int height = image.height;
    final int uvRowStride = image.planes[1].bytesPerRow;
    final int uvPixelStride = image.planes[1].bytesPerPixel!;

    // Crea una imagen vacía usando el paquete 'image'
    var imgImage = img.Image(width: width, height: height);

    for (int y = 0; y < height; y++) {
      final int uvRow = uvRowStride * (y >> 1);
      for (int x = 0; x < width; x++) {
        final int uvPixel = uvRow + (x >> 1) * uvPixelStride;
        final int index = y * width + x;
        final int yVal = image.planes[0].bytes[index];
        final int uVal = image.planes[1].bytes[uvPixel];
        final int vVal = image.planes[2].bytes[uvPixel];

        int r = (yVal + (1.370705 * (vVal - 128))).round();
        int g = (yVal - (0.337633 * (uVal - 128)) - (0.698001 * (vVal - 128))).round();
        int b = (yVal + (1.732446 * (uVal - 128))).round();
        r = r.clamp(0, 255);
        g = g.clamp(0, 255);
        b = b.clamp(0, 255);
        imgImage.setPixelRgb(x, y, r, g, b);
      }
    }
    return Uint8List.fromList(img.encodeJpg(imgImage));
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
      _refPose =
          (result['pose'] as Map?)?.cast<String, Map<String, double>>();
      _refWidth = result['width'] as int;
      _refHeight = result['height'] as int;
    });
  }

  /// Cambia entre cámara frontal y trasera.
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
          // Vista de cámara en vivo con overlays
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
          // Botones para seleccionar imagen de referencia y descargar
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
    // Aquí implementarías la lógica para capturar el último frame
    // con los overlays y guardarlo en el dispositivo.
    print("Implementa la función para guardar la imagen anotada.");
  }
}

/// CustomPainter para dibujar la pose en vivo y la de referencia sobre la vista de cámara.
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
    // Calcula los factores de escala para adaptar las coordenadas
    double scaleX = size.width / imageWidth;
    double scaleY = size.height / imageHeight;

    _drawPose(canvas, livePose, analysisColor,
        scaleX: scaleX, scaleY: scaleY);
    if (referencePose != null) {
      final transformedRefPose = similarityTransformRefPose(
        refPose: referencePose!,
        dstPose: livePose,
      );
      _drawPose(canvas, transformedRefPose, refColor.withOpacity(0.8),
          strokeWidth: 4, scaleX: scaleX, scaleY: scaleY);
    }
  }

  void _drawPose(Canvas canvas, Map<String, Map<String, double>> pose, Color color,
      {double strokeWidth = 3, required double scaleX, required double scaleY}) {
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
        Offset(p1['x']! * scaleX, p1['y']! * scaleY),
        Offset(p2['x']! * scaleX, p2['y']! * scaleY),
        linePaint,
      );
    }

    void drawPoint(String kp) {
      if (!pose.containsKey(kp)) return;
      final p = pose[kp]!;
      canvas.drawCircle(
          Offset(p['x']! * scaleX, p['y']! * scaleY), 5, circlePaint);
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
