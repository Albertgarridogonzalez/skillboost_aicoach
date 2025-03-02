import 'package:flutter/material.dart';
import 'video_picker_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('BMX Correction App'),
      ),
      body: Center(
        child: ElevatedButton(
          child: Text('Seleccionar Video'),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => VideoPickerScreen()),
            );
          },
        ),
      ),
    );
  }
}
