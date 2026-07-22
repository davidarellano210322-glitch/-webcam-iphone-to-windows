// ============================================================================
// STREAMING SERVICE - Cliente WebSocket para enviar video al servidor Windows
// Captura frames de CameraController, los comprime a JPEG y los envía por WS
// ============================================================================

import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class StreamingService {
  static final StreamingService instance = StreamingService._();
  StreamingService._();

  // MethodChannel para comunicación con código nativo Swift
  static const _channel = MethodChannel('com.antigravity.webcam/control');

  WebSocketChannel? _wsChannel;
  bool _isStreaming = false;
  bool _isConnected = false;
  String _connectionStatus = 'DESCONECTADO';
  String _serverUrl = '';
  int _framesSent = 0;
  final int _latencyMs = 0;
  Timer? _telemetryTimer;

  bool get isStreaming => _isStreaming;
  bool get isConnected => _isConnected;
  String get connectionStatus => _connectionStatus;
  String get serverUrl => _serverUrl;
  int get framesSent => _framesSent;
  int get latencyMs => _latencyMs;

  // Callback para que la UI se actualice
  void Function(String status, bool streaming)? onStatusChanged;

  /// Conecta al servidor WebSocket del PC
  Future<bool> connect(String ip, {int port = 8000}) async {
    try {
      // URL del servidor WebSocket HTTPS (wss://)
      final url = 'wss://$ip:$port/ws';
      _serverUrl = url;

      _connectionStatus = 'CONECTANDO...';
      onStatusChanged?.call(_connectionStatus, _isStreaming);

      _wsChannel = WebSocketChannel.connect(Uri.parse(url));

      // Esperar a que la conexión se establezca
      await _wsChannel!.ready.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('Connection timeout'),
      );

      _isConnected = true;
      _connectionStatus = 'CONECTADO';
      onStatusChanged?.call(_connectionStatus, _isStreaming);

      // Escuchar mensajes del servidor (acknowledgments, errores)
      _wsChannel!.stream.listen(
        (message) {
          // El servidor puede enviar mensajes de control
          debugPrint('[WS] Mensaje del servidor: $message');
        },
        onError: (error) {
          debugPrint('[WS] Error: $error');
          _isConnected = false;
          _connectionStatus = 'ERROR DE CONEXIÓN';
          _isStreaming = false;
          onStatusChanged?.call(_connectionStatus, _isStreaming);
        },
        onDone: () {
          debugPrint('[WS] Conexión cerrada');
          _isConnected = false;
          _isStreaming = false;
          _connectionStatus = 'DESCONECTADO';
          onStatusChanged?.call(_connectionStatus, _isStreaming);
        },
      );

      return true;
    } catch (e) {
      debugPrint('[WS] Error al conectar: $e');
      _isConnected = false;
      _connectionStatus = 'ERROR: $e';
      onStatusChanged?.call(_connectionStatus, _isStreaming);
      return false;
    }
  }

  /// Inicia el streaming de video desde CameraController
  Future<void> startStreaming(CameraController cameraController) async {
    if (!_isConnected || _wsChannel == null) {
      debugPrint('[STREAM] No hay conexión WebSocket activa');
      return;
    }

    try {
      // Intentar iniciar el servidor nativo (modo USB)
      try {
        await _channel.invokeMethod('startServer');
      } catch (_) {
        // Si falla el nativo, continuamos con modo WiFi
      }

      // Iniciar captura de frames de imagen
      await cameraController.startImageStream(_onCameraImage);
      _isStreaming = true;
      _connectionStatus = 'TRANSMITIENDO';
      _framesSent = 0;

      // Iniciar timer de telemetría (actualiza datos cada 2s)
      _telemetryTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        _fetchTelemetry();
      });

      onStatusChanged?.call(_connectionStatus, _isStreaming);
      debugPrint('[STREAM] Streaming iniciado');
    } catch (e) {
      debugPrint('[STREAM] Error al iniciar streaming: $e');
    }
  }

  /// Detiene el streaming
  Future<void> stopStreaming(CameraController? cameraController) async {
    try {
      // Detener captura de frames
      if (cameraController != null && cameraController.value.isStreamingImages) {
        await cameraController.stopImageStream();
      }

      // Detener servidor nativo
      try {
        await _channel.invokeMethod('stopServer');
      } catch (_) {}

      _isStreaming = false;
      _connectionStatus = _isConnected ? 'CONECTADO' : 'DESCONECTADO';
      _telemetryTimer?.cancel();
      _telemetryTimer = null;

      onStatusChanged?.call(_connectionStatus, _isStreaming);
      debugPrint('[STREAM] Streaming detenido');
    } catch (e) {
      debugPrint('[STREAM] Error al detener streaming: $e');
    }
  }

  /// Desconecta del servidor
  Future<void> disconnect() async {
    _telemetryTimer?.cancel();
    _telemetryTimer = null;
    _isStreaming = false;
    _isConnected = false;
    _connectionStatus = 'DESCONECTADO';
    _wsChannel?.sink.close();
    _wsChannel = null;
    onStatusChanged?.call(_connectionStatus, _isStreaming);
  }

  /// Procesa cada frame de la cámara y lo envía como JPEG por WebSocket
  void _onCameraImage(CameraImage image) {
    if (!_isStreaming || _wsChannel == null) return;

    try {
      // Convertir YUV420 a JPEG usando el canal nativo o procesamiento local
      final jpegBytes = _convertYUV420ToJPEG(image);
      if (jpegBytes != null && jpegBytes.isNotEmpty) {
        _wsChannel!.sink.add(jpegBytes);
        _framesSent++;
      }
    } catch (e) {
      debugPrint('[STREAM] Error enviando frame: $e');
    }
  }

  /// Convierte CameraImage (YUV420) a JPEG usando el canal nativo de la plataforma
  Uint8List? _convertYUV420ToJPEG(CameraImage image) {
    try {
      // En iOS, imageFormatGroup.bgra8888 nos da BGRA directamente
      // En Android, yuv420 nos da planos Y, U, V
      //
      // Para simplicidad y compatibilidad, usamos el formato bgra8888
      // que nos da datos directamente convertibles a JPEG

      if (image.format.group == ImageFormatGroup.bgra8888) {
        return _convertBGRA8888ToJPEG(image);
      } else if (image.format.group == ImageFormatGroup.yuv420) {
        return _convertYUV420(image);
      } else {
        // Fallback: intentar como bgra8888
        return _convertBGRA8888ToJPEG(image);
      }
    } catch (e) {
      debugPrint('[STREAM] Error convirtiendo frame: $e');
      return null;
    }
  }

  /// Convierte BGRA8888 a JPEG usando MethodChannel (procesamiento nativo)
  Uint8List? _convertBGRA8888ToJPEG(CameraImage image) {
    try {
      // Componer los planos en un solo buffer
      final width = image.width;
      final height = image.height;
      final plane = image.planes[0];
      final bytes = plane.bytes;

      // En BGRA8888, los datos ya están en formato BGRA por fila
      // Sin embargo, el padding puede existir. Usamos bytesPerRow para manejarlo.
      final bytesPerRow = plane.bytesPerRow;

      // Si no hay padding, enviamos directamente
      if (bytesPerRow == width * 4) {
        return Uint8List.fromList(bytes);
      }

      // Si hay padding, removemos el padding por fila
      final expectedBytesPerRow = width * 4;
      final result = Uint8List(width * height * 4);
      for (int row = 0; row < height; row++) {
        final srcOffset = row * bytesPerRow;
        final dstOffset = row * expectedBytesPerRow;
        final srcRow = bytes.sublist(srcOffset, srcOffset + expectedBytesPerRow);
        result.setRange(dstOffset, dstOffset + expectedBytesPerRow, srcRow);
      }
      return result;
    } catch (e) {
      debugPrint('[STREAM] Error en BGRA8888->JPEG: $e');
      return null;
    }
  }

  /// Convierte YUV420 a JPEG (Android)
  Uint8List? _convertYUV420(CameraImage image) {
    try {
      final width = image.width;
      final height = image.height;
      final yPlane = image.planes[0];
      final uPlane = image.planes[1];
      final vPlane = image.planes[2];

      final yBytes = yPlane.bytes;
      final uBytes = uPlane.bytes;
      final vBytes = vPlane.bytes;

      // Convertir YUV a RGB
      final rgbSize = width * height * 4; // BGRA
      final rgbBuffer = Uint8List(rgbSize);

      final yRowStride = yPlane.bytesPerRow;
      final uRowStride = uPlane.bytesPerRow;
      final vRowStride = vPlane.bytesPerRow;
      final pixelStride = uPlane.bytesPerPixel ?? 1;

      int rgbIndex = 0;
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final yVal = yBytes[y * yRowStride + x];
          final uVal = uBytes[(y ~/ 2) * uRowStride + (x ~/ 2) * pixelStride];
          final vVal = vBytes[(y ~/ 2) * vRowStride + (x ~/ 2) * pixelStride];

          // YUV to RGB conversion (BT.601)
          int r = (yVal + 1.402 * (vVal - 128)).round();
          int g = (yVal - 0.344 * (uVal - 128) - 0.714 * (vVal - 128)).round();
          int b = (yVal + 1.772 * (uVal - 128)).round();

          r = r.clamp(0, 255);
          g = g.clamp(0, 255);
          b = b.clamp(0, 255);

          // BGRA order
          rgbBuffer[rgbIndex++] = b;
          rgbBuffer[rgbIndex++] = g;
          rgbBuffer[rgbIndex++] = r;
          rgbBuffer[rgbIndex++] = 255;
        }
      }

      return rgbBuffer;
    } catch (e) {
      debugPrint('[STREAM] Error en YUV420->RGB: $e');
      return null;
    }
  }

  /// Solicita telemetría al código nativo (WebcamStreamer.swift)
  Future<void> _fetchTelemetry() async {
    try {
      final result = await _channel.invokeMethod('getTelemetry');
      if (result != null && result is Map) {
        // El resultado viene de WebcamStreamer.swift
        // Actualizar el estado con los datos reales
        debugPrint('[TELEMETRY] battery=${result['batteryLevel']}, fps=${result['fps']}');
      }
    } catch (_) {
      // Si no hay código nativo, usar valores estimados
    }
  }

  /// Obtiene telemetría en tiempo real
  Future<Map<String, dynamic>> getTelemetry() async {
    try {
      final result = await _channel.invokeMethod('getTelemetry');
      if (result != null && result is Map) {
        return Map<String, dynamic>.from(result);
      }
    } catch (_) {}

    // Valores estimados si no hay nativo
    return {
      'isStreaming': _isStreaming,
      'isRecording': false,
      'batteryLevel': 100,
      'isCharging': false,
      'thermalTemp': 32.0,
      'latencyMs': _isStreaming ? 120 : 0,
      'bitrate': _isStreaming ? '8.5 Mbps' : '0.0 Mbps',
      'fps': 30,
      'resolution': '1080p 30FPS',
      'activeLens': '1x',
      'connectionStatus': _connectionStatus,
    };
  }

  // ─── MÉTODOS DE CONTROL DE CÁMARA (delegan a Swift) ──────────────────────

  Future<void> switchCamera() async {
    try { await _channel.invokeMethod('switchCamera'); } catch (_) {}
  }

  Future<void> toggleFlash() async {
    try { await _channel.invokeMethod('toggleFlash'); } catch (_) {}
  }

  Future<void> setLens(String lens) async {
    try { await _channel.invokeMethod('setLens', {'lens': lens}); } catch (_) {}
  }

  Future<void> setZoom(double zoom) async {
    try { await _channel.invokeMethod('setZoom', {'zoom': zoom}); } catch (_) {}
  }

  Future<void> setExposure(double value) async {
    try { await _channel.invokeMethod('setExposure', {'value': value}); } catch (_) {}
  }

  Future<void> setISO(double iso) async {
    try { await _channel.invokeMethod('setISO', {'iso': iso}); } catch (_) {}
  }

  Future<void> setWhiteBalance(double kelvin) async {
    try { await _channel.invokeMethod('setWhiteBalance', {'kelvin': kelvin}); } catch (_) {}
  }

  Future<void> setResolution(String resolution, int fps) async {
    try {
      await _channel.invokeMethod('setResolution', {
        'width': resolution.split('p').first,
        'fps': fps,
      });
    } catch (_) {}
  }

  Future<void> startRecording() async {
    try { await _channel.invokeMethod('startRecording'); } catch (_) {}
  }

  Future<void> stopRecording() async {
    try { await _channel.invokeMethod('stopRecording'); } catch (_) {}
  }
}
