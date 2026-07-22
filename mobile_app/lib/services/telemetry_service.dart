// ============================================================================
// TELEMETRY SERVICE - Estado de streaming + telemetría + control de cámara
// Integra StreamingService (WebSocket) + MethodChannel (Swift nativo)
// ============================================================================

import 'dart:async';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'streaming_service.dart';

/// Estado completo de telemetría de la cámara/streaming
class TelemetryState {
  final bool isStreaming;
  final bool isFlashActive;
  final bool isRecording;
  final String activeLens;
  final String connectionStatus;
  final String resolution;
  final String bitrate;
  final int latencyMs;
  final double thermalTemp;
  final int batteryPercent;
  final bool isCharging;
  final double zoomLevel;
  final double exposureValue;
  final double isoValue;
  final double whiteBalance;
  final int fps;

  const TelemetryState({
    this.isStreaming = false,
    this.isFlashActive = false,
    this.isRecording = false,
    this.activeLens = '1x',
    this.connectionStatus = 'DESCONECTADO',
    this.resolution = '1080p 30FPS',
    this.bitrate = '0.0 Mbps',
    this.latencyMs = 0,
    this.thermalTemp = 30.0,
    this.batteryPercent = 100,
    this.isCharging = false,
    this.zoomLevel = 1.0,
    this.exposureValue = 0.0,
    this.isoValue = 100,
    this.whiteBalance = 5000,
    this.fps = 30,
  });

  TelemetryState copyWith({
    bool? isStreaming,
    bool? isFlashActive,
    bool? isRecording,
    String? activeLens,
    String? connectionStatus,
    String? resolution,
    String? bitrate,
    int? latencyMs,
    double? thermalTemp,
    int? batteryPercent,
    bool? isCharging,
    double? zoomLevel,
    double? exposureValue,
    double? isoValue,
    double? whiteBalance,
    int? fps,
  }) {
    return TelemetryState(
      isStreaming: isStreaming ?? this.isStreaming,
      isFlashActive: isFlashActive ?? this.isFlashActive,
      isRecording: isRecording ?? this.isRecording,
      activeLens: activeLens ?? this.activeLens,
      connectionStatus: connectionStatus ?? this.connectionStatus,
      resolution: resolution ?? this.resolution,
      bitrate: bitrate ?? this.bitrate,
      latencyMs: latencyMs ?? this.latencyMs,
      thermalTemp: thermalTemp ?? this.thermalTemp,
      batteryPercent: batteryPercent ?? this.batteryPercent,
      isCharging: isCharging ?? this.isCharging,
      zoomLevel: zoomLevel ?? this.zoomLevel,
      exposureValue: exposureValue ?? this.exposureValue,
      isoValue: isoValue ?? this.isoValue,
      whiteBalance: whiteBalance ?? this.whiteBalance,
      fps: fps ?? this.fps,
    );
  }
}

/// Servicio singleton de telemetría y control
class TelemetryService {
  static final TelemetryService instance = TelemetryService._();
  TelemetryService._();

  final StreamingService _streaming = StreamingService.instance;
  static const _channel = MethodChannel('com.antigravity.webcam/control');

  TelemetryState _state = const TelemetryState();
  TelemetryState get state => _state;

  // Callback para que la UI se suscriba a cambios
  void Function(TelemetryState)? onStateChanged;

  // Cámara para captura de frames
  CameraController? _cameraController;
  CameraController? get cameraController => _cameraController;

  // Configuración de red del servidor
  String _serverIp = '';
  int _serverPort = 8000;

  // Simulación de audio
  final _rand = math.Random();
  final List<double> _audioLeft = List.filled(6, 0.05);
  final List<double> _audioRight = List.filled(6, 0.05);
  List<double> get audioLeft => _audioLeft;
  List<double> get audioRight => _audioRight;

  // Timer para simular datos de audio y telemetría
  Timer? _audioTimer;
  Timer? _telemetryTimer;
  bool _isMockRunning = false;

  /// Configura la dirección IP del servidor
  void setServerConfig(String ip, {int port = 8000}) {
    _serverIp = ip;
    _serverPort = port;
  }

  /// Configura el CameraController para captura de frames
  void setCameraController(CameraController? controller) {
    _cameraController = controller;
  }

  // ─── MOCK PARA DESARROLLO ────────────────────────────────────────────────

  void startMock() {
    _isMockRunning = true;
    _startAudioSimulation();
  }

  void stopMock() {
    _isMockRunning = false;
    _audioTimer?.cancel();
    _audioTimer = null;
  }

  void _startAudioSimulation() {
    _audioTimer = Timer.periodic(const Duration(milliseconds: 150), (_) {
      if (!_isMockRunning) return;
      if (_state.isStreaming) {
        for (int i = 0; i < 6; i++) {
          _audioLeft[i] = (0.15 + _rand.nextDouble() * 0.75).clamp(0.05, 1.0);
          _audioRight[i] = (0.15 + _rand.nextDouble() * 0.75).clamp(0.05, 1.0);
        }
      } else {
        for (int i = 0; i < 6; i++) {
          _audioLeft[i] = 0.05;
          _audioRight[i] = 0.05;
        }
      }
      // Notificar a la UI para que actualice los vúmetros
      if (_state.isStreaming) {
        onStateChanged?.call(_state);
      }
    });
  }

  // ─── STREAMING PRINCIPAL ─────────────────────────────────────────────────

  /// Inicia/detiene el streaming de video
  Future<void> toggleStreaming() async {
    if (_state.isStreaming) {
      await _stopStream();
    } else {
      await _startStream();
    }
  }

  Future<void> _startStream() async {
    // Si no hay IP configurada, intentar detección automática
    if (_serverIp.isEmpty) {
      _updateState(_state.copyWith(
        connectionStatus: 'CONFIGURA IP DEL SERVIDOR',
      ));
      return;
    }

    // Conectar al servidor WebSocket
    _updateState(_state.copyWith(connectionStatus: 'CONECTANDO...'));
    final connected = await _streaming.connect(_serverIp, port: _serverPort);

    if (!connected) {
      _updateState(_state.copyWith(
        connectionStatus: 'ERROR DE CONEXIÓN',
        isStreaming: false,
      ));
      return;
    }

    // Iniciar captura de frames
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      await _streaming.startStreaming(_cameraController!);
      _updateState(_state.copyWith(
        isStreaming: true,
        connectionStatus: 'TRANSMITIENDO',
        bitrate: '8.5 Mbps',
        latencyMs: 120,
      ));

      // Iniciar timer para actualizar telemetría desde el nativo
      _telemetryTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        _fetchNativeTelemetry();
      });
    } else {
      _updateState(_state.copyWith(
        connectionStatus: 'CÁMARA NO INICIALIZADA',
      ));
    }
  }

  Future<void> _stopStream() async {
    await _streaming.stopStreaming(_cameraController);
    await _streaming.disconnect();
    _telemetryTimer?.cancel();
    _telemetryTimer = null;
    _updateState(_state.copyWith(
      isStreaming: false,
      connectionStatus: 'DESCONECTADO',
      bitrate: '0.0 Mbps',
      latencyMs: 0,
    ));
  }

  /// Solicita telemetría al código nativo (WebcamStreamer.swift)
  Future<void> _fetchNativeTelemetry() async {
    try {
      final result = await _channel.invokeMethod('getTelemetry');
      if (result != null && result is Map) {
        _updateState(_state.copyWith(
          batteryPercent: result['batteryLevel'] ?? _state.batteryPercent,
          isCharging: result['isCharging'] ?? _state.isCharging,
          thermalTemp: (result['thermalTemp'] ?? 30.0).toDouble(),
          latencyMs: result['latencyMs'] ?? _state.latencyMs,
          bitrate: result['bitrate'] ?? _state.bitrate,
          fps: result['fps'] ?? _state.fps,
          resolution: result['resolution'] ?? _state.resolution,
          activeLens: result['activeLens'] ?? _state.activeLens,
          connectionStatus: result['connectionStatus'] ?? _state.connectionStatus,
          isRecording: result['isRecording'] ?? _state.isRecording,
        ));
      }
    } catch (_) {
      // Si no hay nativo, mantener valores mock
      if (_state.isStreaming) {
        _updateState(_state.copyWith(
          latencyMs: 80 + _rand.nextInt(80),
          thermalTemp: 32.0 + _rand.nextDouble() * 4,
        ));
      }
    }
  }

  // ─── MÉTODOS DE CONTROL DE CÁMARA ────────────────────────────────────────

  /// Cambia entre cámara frontal/trasera
  Future<void> switchCamera() async {
    try { await _channel.invokeMethod('switchCamera'); } catch (_) {}
  }

  /// Activa/desactiva flash
  Future<void> toggleFlash() async {
    try { await _channel.invokeMethod('toggleFlash'); } catch (_) {}
    _updateState(_state.copyWith(isFlashActive: !_state.isFlashActive));
  }

  /// Selecciona lente (0.5x, 1x, 3x)
  Future<void> selectLens(String lens) async {
    _updateState(_state.copyWith(activeLens: lens));
    try { await _channel.invokeMethod('setLens', {'lens': lens}); } catch (_) {}
  }

  /// Ajusta zoom digital
  Future<void> setZoom(double zoom) async {
    _updateState(_state.copyWith(zoomLevel: zoom));
    try { await _channel.invokeMethod('setZoom', {'zoom': zoom}); } catch (_) {}
  }

  /// Ajusta exposición (EV)
  Future<void> setExposure(double value) async {
    _updateState(_state.copyWith(exposureValue: value));
    try { await _channel.invokeMethod('setExposure', {'value': value}); } catch (_) {}
  }

  /// Ajusta ISO
  Future<void> setISO(double iso) async {
    _updateState(_state.copyWith(isoValue: iso));
    try { await _channel.invokeMethod('setISO', {'iso': iso}); } catch (_) {}
  }

  /// Ajusta balance de blancos (temperatura en Kelvin)
  Future<void> setWhiteBalance(double kelvin) async {
    _updateState(_state.copyWith(whiteBalance: kelvin));
    try { await _channel.invokeMethod('setWhiteBalance', {'kelvin': kelvin}); } catch (_) {}
  }

  /// Cambia resolución y FPS
  Future<void> setResolution(String resolution, int fps) async {
    _updateState(_state.copyWith(
      resolution: '$resolution ${fps}FPS',
      fps: fps,
    ));
    try {
      await _channel.invokeMethod('setResolution', <String, dynamic>{
        'width': resolution.split('p').first,
        'fps': fps,
      });
    } catch (_) {}
  }

  /// Inicia/detiene grabación local
  Future<void> toggleRecording() async {
    final newRecording = !_state.isRecording;
    _updateState(_state.copyWith(isRecording: newRecording));
    try {
      if (newRecording) {
        await _channel.invokeMethod('startRecording');
      } else {
        await _channel.invokeMethod('stopRecording');
      }
    } catch (_) {}
  }

  // ─── INTERNO ─────────────────────────────────────────────────────────────

  void _updateState(TelemetryState newState) {
    _state = newState;
    onStateChanged?.call(_state);
  }
}
