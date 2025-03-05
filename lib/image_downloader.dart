import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<Directory?> _getDownloadDirectory() async {
  Directory? directory = await getExternalStorageDirectory();
  // En algunos dispositivos la ruta devuelta puede tener la carpeta 'Android/data/...'
  // Puedes intentar navegar hacia arriba si es necesario.
  return directory;
}