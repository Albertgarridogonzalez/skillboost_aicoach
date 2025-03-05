import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

Future<bool> checkStoragePermission(BuildContext context) async {
  if (Platform.isAndroid) {
    final DeviceInfoPlugin deviceInfoPlugin = DeviceInfoPlugin();
    final AndroidDeviceInfo info = await deviceInfoPlugin.androidInfo;

    // ✅ Android 13+ (API 33) NO necesita `Permission.storage`, solo permisos de imágenes/videos/audio
    if (info.version.sdkInt >= 33) {
      print("✅ No se necesita `Permission.storage` en Android 13+");
      return true;
    }

    // ✅ Para Android 10 a 12 (API 29-32), se usa `MANAGE_EXTERNAL_STORAGE`
    if (info.version.sdkInt >= 30) {
      PermissionStatus manageStatus = await Permission.manageExternalStorage.request();
      if (manageStatus.isGranted) {
        print("✅ `MANAGE_EXTERNAL_STORAGE` concedido.");
        return true;
      } else {
        print("❌ `MANAGE_EXTERNAL_STORAGE` denegado. Pidiendo acceso...");
        await openAppSettings();
        return false;
      }
    }
  }

  // ✅ Para Android 9 o menor, pedimos `Permission.storage`
  PermissionStatus storageStatus = await Permission.storage.request();
  if (storageStatus.isGranted) {
    print("✅ Permiso de almacenamiento concedido.");
    return true;
  } else {
    print("❌ Permiso de almacenamiento denegado. Redirigiendo a ajustes...");
    await openAppSettings();
    return false;
  }
}
