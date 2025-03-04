import 'dart:io';
import 'package:ffmpeg_kit_flutter_min_gpl/ffmpeg_kit.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'pose_estimator.dart';
import 'drawing_utils.dart';

class VideoProcessor {
  static Future<String> processVideo(
    String videoPath, {
    void Function(String message, double progress)? onProgress,
  }) async {
    try {
      if (!File(videoPath).existsSync()) {
        throw Exception("El archivo de entrada no existe en: $videoPath");
      }

      final Directory appTemp = await getTemporaryDirectory();
      final fps = await _getVideoFps(videoPath);

      final framesDir = Directory(
        p.join(appTemp.path, 'frames_${DateTime.now().millisecondsSinceEpoch}'),
      );
      await framesDir.create();

      final framePattern = p.join(framesDir.path, 'frame_%05d.jpg');

      final extractCmd = '-i "$videoPath" -r $fps "$framePattern"';
      await _executeFFmpeg(extractCmd, "Extracción de frames");
      onProgress?.call("Frames extraídos.", 0.15);

      List<File> frameFiles = framesDir
          .listSync()
          .whereType<File>()
          .where((f) => p.extension(f.path).toLowerCase() == '.jpg')
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

      final totalFrames = frameFiles.length;

      if (PoseEstimator.referencePoses.isEmpty) {
        throw Exception("❌ No hay poses de referencia cargadas.");
      }

      for (int i = 0; i < totalFrames; i++) {
        final currentFrame = i + 1;
        final frameProgress = currentFrame / totalFrames;

        final message = "Procesando frame $currentFrame de $totalFrames "
            "(${(frameProgress * 100).toStringAsFixed(1)}%)";

        final overallProgress = 0.15 + 0.5 * frameProgress;
        onProgress?.call(message, overallProgress);

        final frameFile = frameFiles[i];
        final bytes = await frameFile.readAsBytes();

        final int refIndex = (i >= PoseEstimator.referencePoses.length) 
            ? PoseEstimator.referencePoses.length - 1 
            : i;

        final referencePose = PoseEstimator.referencePoses[refIndex];

        final poseData = await PoseEstimator.estimatePose(bytes);
        final annotatedBytes = await DrawingUtils.annotateImage(bytes, poseData, referencePose);
        await frameFile.writeAsBytes(annotatedBytes);
      }

      final outputPath = p.join(
        appTemp.path,
        'annotated_${DateTime.now().millisecondsSinceEpoch}.mp4',
      );

      final reencodeCmd = '-framerate $fps '
          '-i "$framePattern" '
          '-i "$videoPath" '
          '-map 0:v:0 -map 1:a:0 '
          '-c:v libx264 -pix_fmt yuv420p '
          '-c:a copy '
          '-shortest '
          '"$outputPath"';

      await _executeFFmpeg(reencodeCmd, "Re-ensamblar frames");
      onProgress?.call("Video procesado.", 1.0);

      if (!File(outputPath).existsSync()) {
        throw Exception("El video final no se encontró en: $outputPath");
      }

      return outputPath;
    } catch (e) {
      rethrow;
    }
  }

  static Future<double> _getVideoFps(String videoPath) async {
    return 30.0;
  }

  static Future<void> _executeFFmpeg(String cmd, String etapa) async {
    await FFmpegKit.execute(cmd);
  }
}
