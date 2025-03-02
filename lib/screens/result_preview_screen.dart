import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:permission_handler/permission_handler.dart';

class ResultPreviewScreen extends StatefulWidget {
  final String videoPath;

  const ResultPreviewScreen({Key? key, required this.videoPath})
      : super(key: key);

  @override
  _ResultPreviewScreenState createState() => _ResultPreviewScreenState();
}

class _ResultPreviewScreenState extends State<ResultPreviewScreen> {
  VideoPlayerController? _controller;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  void _initializeVideo() {
    _controller = VideoPlayerController.file(File(widget.videoPath))
      ..initialize().then((_) {
        setState(() {});
        _controller?.play();
      });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  /// Solicita permisos de almacenamiento y de video en Android (si es necesario)
  Future<bool> _requestStoragePermission() async {
    if (Platform.isAndroid) {
      // Para Android 10 y anteriores, se solicita storage
      PermissionStatus storageStatus = await Permission.storage.request();
      // Para Android 13+, se solicita el permiso para videos
      PermissionStatus videosStatus = await Permission.videos.request();
      return storageStatus.isGranted || videosStatus.isGranted;
    }
    return true;
  }

  /// Guarda el video en la galería usando saver_gallery
  Future<void> _saveVideoToGallery() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Guardar en galería no es compatible en Web con saver_gallery'),
        ),
      );
      return;
    }

    bool hasPermission = await _requestStoragePermission();
    if (!hasPermission) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Permisos de almacenamiento/medios denegados.')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      // Guarda el video en la galería.
      final result = await SaverGallery.saveFile(
        filePath: widget.videoPath,
        skipIfExists: true,
        fileName: 'video.mp4',
        androidRelativePath: "Movies",
      );

      print("Resultado al guardar: $result");

      // Asumimos que result es un objeto que tiene la propiedad isSuccess
      if (result != null && result.isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Video guardado en la galería.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar el video.')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Excepción al guardar: $e')),
      );
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isInitialized = _controller?.value.isInitialized == true;

    return Scaffold(
      appBar: AppBar(
        title: Text('Video Anotado'),
      ),
      body: Center(
        child: isInitialized
            ? AspectRatio(
                aspectRatio: _controller!.value.aspectRatio,
                child: VideoPlayer(_controller!),
              )
            : CircularProgressIndicator(),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isSaving || !isInitialized ? null : _saveVideoToGallery,
        child: _isSaving
            ? CircularProgressIndicator(color: Colors.white)
            : Icon(Icons.download),
      ),
    );
  }
}
