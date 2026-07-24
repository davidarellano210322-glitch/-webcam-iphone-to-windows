// ============================================================================
// TELEMETRY SERVICE - Estado de streaming + telemetría + control de cámara
// Usa MethodChannel para hablar con WebcamStreamer.swift (TCP 6000/6001 nativo)
// ============================================================================

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/services.dart';

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
///
/// Se comunica con WebcamStreamer.swift via MethodChannel.
/// WebcamStreamer.swift maneja todo el streaming TCP nativo (puertos 6000/6001).
/// La app de escritorio C# se conecta automáticamente via USB (usbmuxd).
class TelemetryService {
  static final TelemetryService instance = TelemetryService._();
  TelemetryService._();

  static const _channel = MethodChannel('com.antigravity.webcam/control');

  TelemetryState _state = const TelemetryState();
  TelemetryState get state => _state;

  void Function(TelemetryState)? onStateChanged;

  /// Notifica cuando el streaming nativo se inicia/detiene. Lo usa la app
  /// para liberar/recuperar la sesión de cámara local (iOS solo permite una
  /// AVCaptureSession activa a la vez).
  void Function(bool isStreaming)? onStreamingChanged;

  // Simulación de audio
  final _rand = math.Random();
  final List<double> _audioLeft = List.filled(6, 0.05);
  final List<double> _audioRight = List.filled(6, 0.05);
  List<double> get audioLeft => _audioLeft;
  List<double> get audioRight => _audioRight;

  Timer? _audioTimer;
  Timer? _telemetryTimer;
  bool _isMockRunning = false;

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
      if (_state.isStreaming) {
        onStateChanged?.call(_state);
      }
    });
  }

  // ─── STREAMING PRINCIPAL ─────────────────────────────────────────────────
  //
  // El streaming es 100% nativo (Swift). Cuando llamamos 'startServer',
  // WebcamStreamer.swift inicia los servidores TCP en puertos 6000/6001,
  // captura video via AVFoundation, lo codifica con VideoToolbox (H.264),
  // y lo envia por TCP. La app de escritorio C# se conecta automaticamente
  // via USB (usbmuxd) y recibe el video.
  //
  // NO necesitamos WebSocket, ni server.py, ni IP manual.

  Future<void> toggleStreaming() async {
    if (_state.isStreaming) {
      await _stopStream();
    } else {
      await _startStream();
    }
  }

  Future<void> _startStream() async {
    _updateState(_state.copyWith(connectionStatus: 'INICIANDO...'));

    try {
      // Esto dispara WebcamStreamer.swift -> startServer()
      // que abre los puertos TCP 6000 (video) y 6001 (control)
      await _channel.invokeMethod('startServer');

      _updateState(_state.copyWith(
        isStreaming: true,
        connectionStatus: 'TRANSMITIENDO',
        bitrate: '8.5 Mbps',
        latencyMs: 12,
      ));
      // Notificar que el streaming nativo está activo para que la app libere
      // la sesión de cámara local (evita conflicto de AVCaptureSession).
      onStreamingChanged?.call(true);

      // Iniciar timer para actualizar telemetría desde Swift
      _telemetryTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        _fetchNativeTelemetry();
      });
    } catch (e) {
      // Si el canal nativo falla (ej: sin soporte nativo), reportar error
      _updateState(_state.copyWith(
        isStreaming: false,
        connectionStatus: 'ERROR',
        bitrate: '0.0 Mbps',
        latencyMs: 0,
      ));
      onStreamingChanged?.call(false);

      _telemetryTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        _fetchNativeTelemetry();
      });
    }
  }

  Future<void> _stopStream() async {
    try {
      await _channel.invokeMethod('stopServer');
    } catch (_) {}

    _telemetryTimer?.cancel();
    _telemetryTimer = null;

    _updateState(_state.copyWith(
      isStreaming: false,
      connectionStatus: 'DESCONECTADO',
      bitrate: '0.0 Mbps',
      latencyMs: 0,
    ));
    // El streaming terminó: la app puede recuperar la cámara local.
    onStreamingChanged?.call(false);
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
          latencyMs: 10 + _rand.nextInt(8),
          thermalTemp: 32.0 + _rand.nextDouble() * 4,
          batteryPercent: (_state.batteryPercent - 1).clamp(0, 100),
        ));
      }
    }
  }

  // ─── MÉTODOS DE CONTROL DE CÁMARA ────────────────────────────────────────

  Future<void> switchCamera() async {
    try { await _channel.invokeMethod('switchCamera'); } catch (_) {}
  }

  Future<void> toggleFlash() async {
    try { await _channel.invokeMethod('toggleFlash'); } catch (_) {}
    _updateState(_state.copyWith(isFlashActive: !_state.isFlashActive));
  }

  Future<void> selectLens(String lens) async {
    _updateState(_state.copyWith(activeLens: lens));
    try { await _channel.invokeMethod('setLens', {'lens': lens}); } catch (_) {}
  }

  Future<void> setZoom(double zoom) async {
    _updateState(_state.copyWith(zoomLevel: zoom));
    try { await _channel.invokeMethod('setZoom', {'zoom': zoom}); } catch (_) {}
  }

  Future<void> setExposure(double value) async {
    _updateState(_state.copyWith(exposureValue: value));
    try { await _channel.invokeMethod('setExposure', {'value': value}); } catch (_) {}
  }

  Future<void> setISO(double iso) async {
    _updateState(_state.copyWith(isoValue: iso));
    try { await _channel.invokeMethod('setISO', {'iso': iso}); } catch (_) {}
  }

  Future<void> setWhiteBalance(double kelvin) async {
    _updateState(_state.copyWith(whiteBalance: kelvin));
    try { await _channel.invokeMethod('setWhiteBalance', {'kelvin': kelvin}); } catch (_) {}
  }

  Future<void> setResolution(String resolution, int fps) async {
    _updateState(_state.copyWith(
      resolution: '$resolution ${fps}FPS',
      fps: fps,
    ));
    try {
      await _channel.invokeMethod('setResolution', <String, dynamic>{
        'width': resolution,
        'fps': fps,
      });
    } catch (_) {}
  }

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
