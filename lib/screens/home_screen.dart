// home_screen.dart
import 'package:flutter/material.dart';
import 'package:skillboost_aicoach/checkstorage.dart';
import 'package:skillboost_aicoach/screens/compare_poses_screen.dart';
import 'package:skillboost_aicoach/screens/live_pose_analysis_screen.dart';
import 'package:skillboost_aicoach/screens/compare_video_poses_screen.dart';

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
              onPressed: () async {
                bool permisoConcedido = await checkStoragePermission(context);
                if (permisoConcedido) {
                  print("✅ Permiso listo para usar almacenamiento.");
                } else {
                  print("❌ Permiso denegado.");
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => ComparePosesScreen()),
                );
              },
              child: Text('Analizador de imagen'),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                bool permisoConcedido = await checkStoragePermission(context);
                if (permisoConcedido) {
                  print("✅ Permiso listo para usar cámara y almacenamiento.");
                } else {
                  print("❌ Permiso denegado.");
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => LivePoseAnalysisScreen()),
                );
              },
              child: Text('Analizador en vivo'),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                bool permisoConcedido = await checkStoragePermission(context);
                if (permisoConcedido) {
                  print("✅ Permiso listo para usar almacenamiento.");
                } else {
                  print("❌ Permiso denegado.");
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => CompareVideosScreen()),
                );
              },
              child: Text('Analizador de video'),
            ),
            SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
