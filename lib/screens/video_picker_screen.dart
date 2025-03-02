import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../video_processor.dart';
import 'result_preview_screen.dart';

class VideoPickerScreen extends StatefulWidget {
  const VideoPickerScreen({Key? key}) : super(key: key);

  @override
  _VideoPickerScreenState createState() => _VideoPickerScreenState();
}

class _VideoPickerScreenState extends State<VideoPickerScreen> {
  File? _selectedVideo;
  VideoPlayerController? _videoController;
  bool _isProcessing = false;
  String _progressMessage = "";
  double _progressValue = 0.0;

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _selectedVideo = File(result.files.single.path!);
      });
      _initializeVideoPlayer();
    }
  }

  Future<void> _initializeVideoPlayer() async {
    if (_selectedVideo == null) return;
    _videoController = VideoPlayerController.file(_selectedVideo!)
      ..initialize().then((_) {
        setState(() {});
      })
      ..setLooping(true);
    _videoController?.play();
  }

  Future<void> _processVideo() async {
    if (_selectedVideo == null) return;
    setState(() {
      _isProcessing = true;
      _progressMessage = "Iniciando...";
      _progressValue = 0.0;
    });

    try {
      final annotatedVideoPath = await VideoProcessor.processVideo(
        _selectedVideo!.path,
        onProgress: (message, progress) {
          setState(() {
            _progressMessage = message;
            _progressValue = progress;
          });
        },
      );

      setState(() {
        _isProcessing = false;
      });

      if (annotatedVideoPath != null && File(annotatedVideoPath).existsSync()) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ResultPreviewScreen(videoPath: annotatedVideoPath),
          ),
        );
      } else {
        _showErrorDialog("El video procesado no se encontró.");
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
      });
      _showErrorDialog("Ocurrió un error durante el procesamiento: $e");
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Error en el procesamiento"),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Aceptar"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Seleccionar video'),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            if (_selectedVideo != null && _videoController?.value.isInitialized == true)
              SizedBox(
                height: 300, // Video más grande
                child: AspectRatio(
                  aspectRatio: _videoController!.value.aspectRatio,
                  child: VideoPlayer(_videoController!),
                ),
              ),
            SizedBox(height: 20),
            if (_isProcessing)
              Column(
                children: [
                  LinearProgressIndicator(value: _progressValue),
                  SizedBox(height: 10),
                  Text(_progressMessage),
                ],
              ),
            SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: _pickVideo,
                  child: Text('Elegir Video'),
                ),
                ElevatedButton(
                  onPressed: _isProcessing ? null : _processVideo,
                  child: Text('Procesar Video'),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
