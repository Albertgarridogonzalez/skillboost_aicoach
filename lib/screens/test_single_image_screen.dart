import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../pose_estimator_image.dart'; // Ajusta la ruta
// No hace falta importar drawing_utils.dart aquí, ya se usa dentro de pose_estimator_image.

class TestSingleImageScreen extends StatefulWidget {
  const TestSingleImageScreen({Key? key}) : super(key: key);

  @override
  _TestSingleImageScreenState createState() => _TestSingleImageScreenState();
}

class _TestSingleImageScreenState extends State<TestSingleImageScreen> {
  File? _pickedFile;
  Uint8List? _annotatedBytes;

  Future<void> _pickAndProcessImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final file = File(picked.path);
    setState(() {
      _pickedFile = file;
      _annotatedBytes = null;
    });

    // Llamamos al nuevo método "estimatePoseAndAnnotateFromFile"
    final annotated = await PoseEstimatorimage.estimatePoseAndAnnotateFromFile(file);
    if (annotated == null) {
      print("No se pudo anotar la imagen (quizá no se detectó pose).");
      return;
    }

    setState(() {
      _annotatedBytes = annotated;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Test Single Image Pose'),
      ),
      body: Column(
        children: [
          ElevatedButton(
            onPressed: _pickAndProcessImage,
            child: Text('Seleccionar Imagen'),
          ),
          Expanded(
            child: Center(
              child: _buildResultWidget(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultWidget() {
    // Si no hemos seleccionado imagen
    if (_pickedFile == null) {
      return Text('No se ha seleccionado ninguna imagen');
    }
    // Si no hemos anotado todavía, mostramos la imagen original
    if (_annotatedBytes == null) {
      return Image.file(_pickedFile!);
    }
    // Si ya tenemos la imagen anotada, la mostramos en un InteractiveViewer
    return InteractiveViewer(
      child: Image.memory(
        _annotatedBytes!,
        fit: BoxFit.none, // evita reescalar
      ),
    );
  }
}
