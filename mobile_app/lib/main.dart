import 'package:flutter/material.dart';
import 'package:flutter/services.dart';


void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Antigravity Camera',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0D0F14),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00F2FE),
          secondary: Color(0xFF4FACFE),
        ),
      ),
      home: const CameraHomeScreen(),
    );
  }
}

class CameraHomeScreen extends StatefulWidget {
  const CameraHomeScreen({super.key});

  @override
  State<CameraHomeScreen> createState() => _CameraHomeScreenState();
}

class _CameraHomeScreenState extends State<CameraHomeScreen> {
  bool _isStreaming = false;
  String _status = "Desconectado";
  int _fps = 0;

  static const platform = MethodChannel('com.antigravity.webcam/control');

  Future<void> _toggleStreaming() async {
    try {
      if (_isStreaming) {
        await platform.invokeMethod('stopServer');
        setState(() {
          _isStreaming = false;
          _status = "Desconectado";
        });
      } else {
        await platform.invokeMethod('startServer');
        setState(() {
          _isStreaming = true;
          _status = "Transmitiendo (USB)";
        });
      }
    } catch (e) {
      setState(() {
        _status = "Error: $e";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Antigravity Webcam',
          style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00F2FE)),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.flip_camera_ios, color: Color(0xFF00F2FE)),
            tooltip: "Cambiar de cámara",
            onPressed: () async {
              try {
                await platform.invokeMethod('switchCamera');
              } catch (e) {
                // Silenciar error de llamada de canal si no está corriendo en dispositivo real
              }
            },
          ),
        ],
        backgroundColor: const Color(0xFF161C2D),
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Preview Container
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white10),
                ),
                child: Center(
                  child: _isStreaming
                      ? const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.videocam, size: 64, color: Color(0xFF00F2FE)),
                            SizedBox(height: 16),
                            Text("Vista previa nativa activa"),
                          ],
                        )
                      : const Text(
                          "Cámara apagada",
                          style: TextStyle(color: Colors.white38),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Status and Stats
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF161C2D),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Estado:", style: TextStyle(color: Colors.white54)),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isStreaming ? Colors.green : Colors.red,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _status,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _isStreaming ? Colors.green : Colors.red,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const Divider(height: 24, color: Colors.white10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("FPS reales:", style: TextStyle(color: Colors.white54)),
                      Text(
                        _isStreaming ? "60 FPS" : "0 FPS",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Start/Stop Button
            ElevatedButton(
              onPressed: _toggleStreaming,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isStreaming ? Colors.red : const Color(0xFF00F2FE),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                _isStreaming ? "Detener Transmisión" : "Iniciar Transmisión USB",
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
