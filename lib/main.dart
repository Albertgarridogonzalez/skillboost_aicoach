import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart'; // Importa la librería de permisos
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _requestPermissions(); // Solicita permisos antes de iniciar la app
  runApp(const MyBmxCorrectionApp());
}

/// Función para solicitar permisos necesarios antes de procesar videos
Future<void> _requestPermissions() async {
  if (Platform.isAndroid) {
    // Para Android 13+, se deben solicitar permisos específicos de medios:
    if (await Permission.videos.isDenied) {
      await Permission.videos.request();
    }
     if (await Permission.photos.isDenied) {
      await Permission.photos.request();
    }
    // Para Android 10 y anteriores, se solicita storage
    if (await Permission.storage.isDenied) {
      await Permission.storage.request();
    }
    // Opcional: Para Android 11+ (si necesitas acceso amplio)
    if (await Permission.manageExternalStorage.isDenied) {
      await Permission.manageExternalStorage.request();
    }
  } else if (Platform.isIOS) {
    // En iOS se solicita el permiso de fotos
    if (await Permission.photos.isDenied) {
      await Permission.photos.request();
    }
  }

  // Imprime en consola el estado final de los permisos solicitados.
  if (await Permission.storage.isGranted || await Permission.videos.isGranted) {
    print("✅ Permiso concedido.");
  } else {
    print("⚠️ Permiso de almacenamiento/medios denegado.");
  }
}

class MyBmxCorrectionApp extends StatelessWidget {
  const MyBmxCorrectionApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BMX Correction App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const HomeScreen(),
    );
  }
}
