import 'dart:io';
import 'package:ffmpeg_kit_flutter_min_gpl/ffmpeg_kit.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'pose_estimator.dart';
import 'drawing_utils.dart';

class VideoProcessor {
  static Future<String> processVideo(
    String videoPath, {
    void Function(String message, double progress)? onProgress,
  }) async {
    try {
      // 1. Verificar que el archivo de entrada exista
      if (!File(videoPath).existsSync()) {
        throw Exception("El archivo de entrada no existe en: $videoPath");
      }

      // 2. Obtener directorio temporal de la app (para guardar frames y salida)
      final Directory appTemp = await getTemporaryDirectory();

      // 3. Extraer frames a carpeta temporal
      onProgress?.call("Extrayendo frames...", 0.05);

      final framesDir = Directory(
        p.join(appTemp.path, 'frames_${DateTime.now().millisecondsSinceEpoch}'),
      );
      await framesDir.create();

      final framePattern = p.join(framesDir.path, 'frame_%05d.jpg');

      // Extraer ~10 fps de frames
      final extractCmd = '-i "$videoPath" -r 10 "$framePattern"';
      await _executeFFmpeg(extractCmd, "Extracción de frames");
      onProgress?.call("Frames extraídos.", 0.15);

      // 4. Listar frames extraídos
      List<File> frameFiles = framesDir
          .listSync()
          .whereType<File>()
          .where((f) => p.extension(f.path).toLowerCase() == '.jpg')
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

      final totalFrames = frameFiles.length;
      // 5. Anotar cada fotograma con la pose estimada
      for (int i = 0; i < totalFrames; i++) {
        onProgress?.call(
          "Procesando frame ${i + 1} de $totalFrames",
          0.15 + 0.5 * ((i + 1) / totalFrames),
        );

        final frameFile = frameFiles[i];
        final bytes = await frameFile.readAsBytes();

        final poseData = await PoseEstimator.estimatePose(bytes);
        final annotatedBytes = await DrawingUtils.annotateImage(bytes, poseData);
        await frameFile.writeAsBytes(annotatedBytes);
      }

      // 6. Re-ensamblar los frames en un video conservando el audio original
      onProgress?.call("Re-ensamblar frames con audio original...", 0.70);

      final outputPath = p.join(
        appTemp.path,
        'annotated_${DateTime.now().millisecondsSinceEpoch}.mp4',
      );

      // Comando FFmpeg:
      // - Entrada 0: frames extraídos (como video)
      // - Entrada 1: video original (para audio)
      // - Mapea 0:v y 1:a, re-encodea video con libx264 y copia el audio sin cambios
      // - -shortest para ajustar la duración al segmento más corto (usualmente el video)
      final reencodeCmd = '-framerate 10 '
          '-i "$framePattern" '
          '-i "$videoPath" '
          '-map 0:v:0 -map 1:a:0 '
          '-c:v libx264 -pix_fmt yuv420p '
          '-c:a copy '
          '-shortest '
          '"$outputPath"';

      await _executeFFmpeg(reencodeCmd, "Re-ensamblar frames");
      onProgress?.call("Video procesado.", 1.0);

      // 7. Verificar que el archivo final se haya creado
      if (!File(outputPath).existsSync()) {
        throw Exception("El video final no se encontró en: $outputPath");
      }

      return outputPath;
    } catch (e) {
      rethrow;
    }
  }

  /// Método auxiliar para ejecutar un comando FFmpeg y verificar su resultado.
  static Future<void> _executeFFmpeg(String cmd, String etapa) async {
    final session = await FFmpegKit.execute(cmd);
    final returnCode = await session.getReturnCode();
    final logs = await session.getAllLogsAsString();

    if (returnCode!.isValueSuccess()) {
      print("[$etapa] Éxito:\n$logs");
    } else {
      print("[$etapa] Error:\n$logs");
      throw Exception("FFmpeg falló en la etapa: $etapa\nLogs:\n$logs");
    }
  }
}
