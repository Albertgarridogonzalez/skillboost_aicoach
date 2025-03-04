import 'package:flutter/material.dart';
import 'video_picker_screen.dart';
//import 'image_picker_screen.dart';
// Importa la nueva pantalla de pruebas
import 'test_single_image_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('AI Coach - Selección')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => VideoPickerScreen()),
                );
              },
              child: Text('Seleccionar Video'),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => ImagePickerScreen()),
                );
              },
              child: Text('Seleccionar Imagen'),
            ),
            SizedBox(height: 20),
            // NUEVO BOTÓN: Test de pose en una sola imagen
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => TestSingleImageScreen()),
                );
              },
              child: Text('Test Single Image Pose'),
            ),
          ],
        ),
      ),
    );
  }
}

ImagePickerScreen() {
}
