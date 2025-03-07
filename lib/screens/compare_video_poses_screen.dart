import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter/return_code.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'dart:typed_data';


// Estas importaciones deben coincidir con las que ya usas en tu proyecto.
import 'package:skillboost_aicoach/pose_estimator_image.dart';
import 'package:skillboost_aicoach/drawing_utils.dart'; // debe incluir annotateImage, computeSelectedAngles y demás.
import 'package:skillboost_aicoach/pose_utils.dart'; // donde se encuentra similarityTransformRefPose

class CompareVideosScreen extends StatefulWidget {
  const CompareVideosScreen({Key? key}) : super(key: key);

  @override
  _CompareVideosScreenState createState() => _CompareVideosScreenState();
}

class _CompareVideosScreenState extends State<CompareVideosScreen> {
  File? _videoFile1;
  File? _videoFile2;
  VideoPlayerController? _controller1;
  VideoPlayerController? _controller2;

  // Variables para fps y selección de instante de referencia
  double? _fpsVideo1;
  double? _fpsVideo2;
  Duration _referenceTime1 = Duration.zero;
  Duration _referenceTime2 = Duration.zero;

  // Video resultante del análisis
  File? _outputVideo;

  @override
  void dispose() {
    _controller1?.dispose();
    _controller2?.dispose();
    super.dispose();
  }

  // *********************** SELECCIÓN DE VIDEOS ***********************

  Future<void> _pickVideo1() async {
    final picker = ImagePicker();
    final picked = await picker.pickVideo(source: ImageSource.gallery);
    if (picked != null) {
      _videoFile1 = File(picked.path);
      _controller1 = VideoPlayerController.file(_videoFile1!)
        ..initialize().then((_) {
          setState(() {});
        });
      _fpsVideo1 = await _getVideoFps(_videoFile1!);
      setState(() {});
    }
  }

  Future<void> _pickVideo2() async {
    final picker = ImagePicker();
    final picked = await picker.pickVideo(source: ImageSource.gallery);
    if (picked != null) {
      _videoFile2 = File(picked.path);
      _controller2 = VideoPlayerController.file(_videoFile2!)
        ..initialize().then((_) {
          setState(() {});
        });
      _fpsVideo2 = await _getVideoFps(_videoFile2!);
      setState(() {});
    }
  }

  // *********************** OBTENCIÓN DE FPS Y RE-ENCODIFICACIÓN ***********************

  Future<double> _getVideoFps(File videoFile) async {
  // Se usa ffprobe para obtener la tasa de fps
  final command =
      "-v error -select_streams v:0 -show_entries stream=r_frame_rate -of default=noprint_wrappers=1:nokey=1 \"${videoFile.path}\"";
  String? output;
  await FFmpegKit.executeAsync(command, (session) async {
    final returnCode = await session.getReturnCode();
    if (ReturnCode.isSuccess(returnCode)) {
      output = await session.getOutput();
    }
  });
  if (output != null) {
    output = output!.trim();
    // Forzamos que 'output' no sea nulo usando el operador '!'
    if (output!.contains("/")) {
      var parts = output!.split("/");
      double num = double.tryParse(parts[0]) ?? 0.0;
      double den = double.tryParse(parts[1]) ?? 1.0;
      if (den != 0) return num / den;
    } else {
      return double.tryParse(output!) ?? 30.0;
    }
  }
  return 30.0; // Valor por defecto
}


  Future<File> _reencodeVideoWithFps(File videoFile, double targetFps) async {
    final tempDir = await getTemporaryDirectory();
    String outputPath = p.join(tempDir.path, "reencoded_${p.basename(videoFile.path)}");
    final command =
        "-i \"${videoFile.path}\" -filter:v fps=fps=$targetFps -c:a copy \"$outputPath\"";
    await FFmpegKit.execute(command);
    return File(outputPath);
  }

  Future<void> _equalizeFps() async {
    if (_videoFile1 == null || _videoFile2 == null) return;
    if (_fpsVideo1 == null || _fpsVideo2 == null) return;
    double targetFps = math.min(_fpsVideo1!, _fpsVideo2!);
    if (_fpsVideo1! > targetFps) {
      _videoFile1 = await _reencodeVideoWithFps(_videoFile1!, targetFps);
      _fpsVideo1 = targetFps;
      _controller1 = VideoPlayerController.file(_videoFile1!)
        ..initialize().then((_) {
          setState(() {});
        });
    }
    if (_fpsVideo2! > targetFps) {
      _videoFile2 = await _reencodeVideoWithFps(_videoFile2!, targetFps);
      _fpsVideo2 = targetFps;
      _controller2 = VideoPlayerController.file(_videoFile2!)
        ..initialize().then((_) {
          setState(() {});
        });
    }
  }

  // *********************** INTERFAZ: VIDEOS Y SELECCIÓN DE INSTANTE ***********************

  Widget _buildVideoPlayers() {
    if (_controller1 == null ||
        !_controller1!.value.isInitialized ||
        _controller2 == null ||
        !_controller2!.value.isInitialized) {
      return Center(child: Text('Selecciona ambos videos'));
    }
    return Row(
      children: [
        Expanded(
          child: Column(
            children: [
              AspectRatio(
                aspectRatio: _controller1!.value.aspectRatio,
                child: VideoPlayer(_controller1!),
              ),
              Slider(
                min: 0,
                max: _controller1!.value.duration.inMilliseconds.toDouble(),
                value: _referenceTime1.inMilliseconds.toDouble(),
                onChanged: (value) {
                  setState(() {
                    _referenceTime1 = Duration(milliseconds: value.toInt());
                    _controller1!.seekTo(_referenceTime1);
                  });
                },
              ),
              Text("Ref. Video 1: ${_referenceTime1.inSeconds}s"),
            ],
          ),
        ),
        Expanded(
          child: Column(
            children: [
              AspectRatio(
                aspectRatio: _controller2!.value.aspectRatio,
                child: VideoPlayer(_controller2!),
              ),
              Slider(
                min: 0,
                max: _controller2!.value.duration.inMilliseconds.toDouble(),
                value: _referenceTime2.inMilliseconds.toDouble(),
                onChanged: (value) {
                  setState(() {
                    _referenceTime2 = Duration(milliseconds: value.toInt());
                    _controller2!.seekTo(_referenceTime2);
                  });
                },
              ),
              Text("Ref. Video 2: ${_referenceTime2.inSeconds}s"),
            ],
          ),
        ),
      ],
    );
  }

  // *********************** PROCESAMIENTO: EXTRACCIÓN, ANÁLISIS Y REENSAMBLADO ***********************

  Future<void> _startAnalysis() async {
    if (_videoFile1 == null || _videoFile2 == null) return;
    // Igualamos los fps de ambos videos
    await _equalizeFps();
    double targetFps = _fpsVideo1 ?? 30.0;
    
    // Creamos directorios temporales para guardar fotogramas y resultados
    final tempDir = await getTemporaryDirectory();
    final framesDir1 = Directory(p.join(tempDir.path, "frames1"));
    final framesDir2 = Directory(p.join(tempDir.path, "frames2"));
    final outputFramesDir = Directory(p.join(tempDir.path, "outputFrames"));
    if (!framesDir1.existsSync()) framesDir1.createSync();
    if (!framesDir2.existsSync()) framesDir2.createSync();
    if (!outputFramesDir.existsSync()) outputFramesDir.createSync();
    
    // Extraer fotogramas de cada video a partir del instante de referencia
    await _extractFrames(_videoFile1!, _referenceTime1, framesDir1.path, targetFps);
    await _extractFrames(_videoFile2!, _referenceTime2, framesDir2.path, targetFps);
    
    // Procesar fotogramas: por cada par (asumimos misma cantidad y orden)
    await _processFrames(framesDir1.path, framesDir2.path, outputFramesDir.path);
    
    // Reensamblar fotogramas procesados en un video final
    File assembledVideo = await _assembleVideoFromFrames(outputFramesDir.path, targetFps);
    setState(() {
      _outputVideo = assembledVideo;
    });
    
    // Aquí podrías navegar a otra pantalla o reproducir el video final
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Análisis completado. Video generado.")),
    );
  }

  Future<void> _extractFrames(
    File videoFile, Duration startTime, String outputDir, double fps) async {
  String startTimeStr = "${startTime.inSeconds}";
  final command =
      "-ss $startTimeStr -i \"${videoFile.path}\" -vf fps=$fps \"$outputDir/frame_%04d.jpg\"";
  print("Ejecutando extracción de fotogramas con comando: $command");
  final session = await FFmpegKit.execute(command);
  final returnCode = await session.getReturnCode();
  print("Código de retorno de extracción: $returnCode");
  final output = await session.getOutput();
  print("Salida de extracción: $output");
}

  Future<void> _processFrames(
    String framesDir1, String framesDir2, String outputDir) async {
  final dir1 = Directory(framesDir1);
  final dir2 = Directory(framesDir2);
  final frames1 = dir1
      .listSync()
      .whereType<File>()
      .toList()..sort((a, b) => a.path.compareTo(b.path));
  final frames2 = dir2
      .listSync()
      .whereType<File>()
      .toList()..sort((a, b) => a.path.compareTo(b.path));
  int numFrames = math.min(frames1.length, frames2.length);
  print("Procesando $numFrames fotogramas...");

  for (int i = 0; i < numFrames; i++) {
    File frameFile1 = frames1[i];
    File frameFile2 = frames2[i];

    // Procesamos fotogramas usando las funciones de detección de pose
    final result1 = await PoseEstimatorimage.detectPoseOnOrientedImage(frameFile1);
    final result2 = await PoseEstimatorimage.detectPoseOnOrientedImage(frameFile2);
    if (result1 == null || result2 == null) {
      print("No se detectó pose en el fotograma $i");
      continue;
    }

    Map<String, Map<String, double>> refPose = result1['pose'];
    Map<String, Map<String, double>> analysisPose = result2['pose'];

    // Aplicamos la transformación de similitud
    Map<String, Map<String, double>> transformedRefPose =
        similarityTransformRefPose(refPose: refPose, dstPose: analysisPose);

    // Leemos el fotograma de análisis y lo anotamos
    Uint8List frameBytes = await frameFile2.readAsBytes();
    Uint8List annotatedBytes = await DrawingUtils.annotateImage(
        frameBytes, analysisPose, transformedRefPose);

    String outputPath =
        p.join(outputDir, "frame_${i.toString().padLeft(4, '0')}.jpg");
    File(outputPath).writeAsBytesSync(annotatedBytes);
    print("Fotograma $i procesado y guardado en $outputPath");
  }
}

 Future<File> _assembleVideoFromFrames(String framesDir, double fps) async {
  final tempDir = await getTemporaryDirectory();
  String outputVideoPath = p.join(tempDir.path, "analyzed_video.mp4");
  final command =
      "-r $fps -i \"$framesDir/frame_%04d.jpg\" -c:v libx264 -pix_fmt yuv420p \"$outputVideoPath\"";
  print("Ejecutando ensamblado de video con comando: $command");
  final session = await FFmpegKit.execute(command);
  final returnCode = await session.getReturnCode();
  print("Código de retorno de ensamblado: $returnCode");
  final output = await session.getOutput();
  print("Salida de ensamblado: $output");
  return File(outputVideoPath);
}
  // *********************** INTERFAZ DE USUARIO ***********************

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Analizador de Video'),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Botones para seleccionar videos
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: _pickVideo1,
                  child: Text('Seleccionar Video 1'),
                ),
                SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _pickVideo2,
                  child: Text('Seleccionar Video 2'),
                ),
              ],
            ),
            SizedBox(height: 10),
            _buildVideoPlayers(),
            SizedBox(height: 10),
            ElevatedButton(
              onPressed: _startAnalysis,
              child: Text('Iniciar Análisis'),
            ),
            SizedBox(height: 10),
            if (_outputVideo != null)
              Column(
                children: [
                  Text('Video Analizado:'),
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: VideoPlayer(
                      VideoPlayerController.file(_outputVideo!)
                        ..initialize().then((_) {
                          setState(() {});
                          // Puedes reproducir el video automáticamente si lo deseas.
                        }),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
