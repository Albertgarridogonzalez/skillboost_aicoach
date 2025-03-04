import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../drawing_utils.dart';

class ImageResultScreen extends StatefulWidget {
  final Map<String, dynamic> referencePose;
  final Map<String, dynamic> targetPose;
  final File referenceImage;
  final File targetImage;

  const ImageResultScreen({
    Key? key,
    required this.referencePose,
    required this.targetPose,
    required this.referenceImage,
    required this.targetImage,
  }) : super(key: key);

  @override
  _ImageResultScreenState createState() => _ImageResultScreenState();
}

class _ImageResultScreenState extends State<ImageResultScreen> {
  Uint8List? _annotatedImage;

  @override
  void initState() {
    super.initState();
    _processImage();
  }

  Future<void> _processImage() async {
    // Leemos la imagen "a analizar"
    final originalBytes = await widget.targetImage.readAsBytes();

    // Dibujamos tanto la pose "targetPose" como la "referencePose"
    final annotated = await DrawingUtils.annotateImage(
      originalBytes,
      widget.targetPose,
      widget.referencePose,
    );

    setState(() => _annotatedImage = annotated);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Comparación de Poses')),
      body: Center(
        child: _annotatedImage == null
            ? const CircularProgressIndicator()
            : Image.memory(
                _annotatedImage!,
                fit: BoxFit.none, // <= Para NO redimensionar
              ),
      ),
    );
  }
}
