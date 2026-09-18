import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'screens/splash_screen.dart'; // Cambia esto por tu pantalla principal

class VideoSplash extends StatefulWidget {
  @override
  _VideoSplashState createState() => _VideoSplashState();
}

class _VideoSplashState extends State<VideoSplash> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.asset("assets/video/splash_video.mp4")
      ..initialize().then((_) {
        setState(() {}); // Asegura que el primer frame se vea
        _controller.play();
      });

    // Escuchamos cuando el video termina para cambiar de pantalla
    _controller.addListener(() {
      if (_controller.value.position == _controller.value.duration) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => SplashScreen()),
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose(); // Muy importante liberar la memoria
    super.dispose();
  }

  @override
Widget build(BuildContext context) {
  return Scaffold(
    backgroundColor: Colors.black, 
    body: Stack(
      children: [
        SizedBox.expand(
          child: _controller.value.isInitialized
              ? FittedBox(
                  // BoxFit.cover hace que el video llene toda la pantalla
                  // recortando ligeramente los bordes si es necesario.
                  fit: BoxFit.cover, 
                  child: SizedBox(
                    width: _controller.value.size.width,
                    height: _controller.value.size.height,
                    child: VideoPlayer(_controller),
                  ),
                )
              : Container(color: Colors.black), // Fondo negro mientras carga
        ),
        // Opcional: Puedes poner un pequeño indicador de carga abajo
        if (!_controller.value.isInitialized)
          const Center(child: CircularProgressIndicator(color: Colors.white)),
        ],
     ),
    );
  }
}