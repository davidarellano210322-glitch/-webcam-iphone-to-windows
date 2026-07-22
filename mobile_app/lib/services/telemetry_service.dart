// ============================================================================
// TELEMETRY SERVICE - Canal de comunicación nativa con WebcamStreamer.swift
// Proporciona estado de streaming, telemetría y control de cámara.
// ============================================================================
//
// NOTA: Puedes ejecutar esta app sin WebcamStreamer.swift activo —
//       todos los métodos fallan silenciosamente a valores mock.
// ============================================================================

import 'package:flutter/services.dart';
import 'dart:math' as math;

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
    this.resolution = '1080p 60FPS',
    this.bitrate = '0.0 Mbps',
    this.latencyMs = 0,
    this.thermalTemp = 30.0,
    this.batteryPercent = 100,
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
/// Cuando el canal nativo no está disponible, genera datos mock
/// para que la UI se vea viva durante desarrollo/pruebas.
class TelemetryService {
  static final TelemetryService instance = TelemetryService._();
  TelemetryService._();

  static const _channel = MethodChannel('com.antigravity.webcam/control');

  TelemetryState _state = const TelemetryState();
  TelemetryState get state => _state;

  // Callback para que la UI se suscriba a cambios
  void Function(TelemetryState)? onStateChanged;

  // Simulación de audio (mock)
  final _rand = math.Random();
  final List<double> _audioLeft = List.filled(6, 0.05);
  final List<double> _audioRight = List.filled(6, 0.05);
  List<double> get audioLeft => _audioLeft;
  List<double> get audioRight => _audioRight;

  // Mock timer ID
  bool _isMockRunning = false;

  /// Inicia el mock de datos para testing visual
  void startMock() {
    _isMockRunning = true;
    _simulateMockData();
  }

  void stopMock() {
    _isMockRunning = false;
  }

  void _simulateMockData() {
    Future.delayed(const Duration(milliseconds: 150), () {
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
      _simulateMockData();
    });
  }

  // ─── MÉTODOS DE CONTROL ──────────────────────────────────────────────────

  /// Inicia/Detiene el servidor de streaming
  Future<void> toggleStreaming() async {
    try {
      if (_state.isStreaming) {
        await _channel.invokeMethod('stopServer');
        _updateState(_state.copyWith(
          isStreaming: false,
          connectionStatus: 'DESCONECTADO',
        ));
      } else {
        await _channel.invokeMethod('startServer');
        _updateState(_state.copyWith(
          isStreaming: true,
          connectionStatus: 'USB CONECTADO',
        ));
      }
    } catch (_) {
      // Fallback local para testing sin dispositivo real
      final newStreaming = !_state.isStreaming;
      _updateState(_state.copyWith(
        isStreaming: newStreaming,
        connectionStatus: newStreaming ? 'USB CONECTADO' : 'DESCONECTADO',
        latencyMs: newStreaming ? 12 : 0,
        bitrate: newStreaming ? '8.5 Mbps' : '0.0 Mbps',
      ));
    }
  }

  /// Cambia entre cámara frontal/trasera
  Future<void> switchCamera() async {
    try {
      await _channel.invokeMethod('switchCamera');
    } catch (_) {}
  }

  /// Activa/desactiva flash
  Future<void> toggleFlash() async {
    try {
      await _channel.invokeMethod('toggleFlash');
      _updateState(_state.copyWith(isFlashActive: !_state.isFlashActive));
    } catch (_) {
      _updateState(_state.copyWith(isFlashActive: !_state.isFlashActive));
    }
  }

  /// Selecciona lente (0.5x, 1x, 3x)
  Future<void> selectLens(String lens) async {
    _updateState(_state.copyWith(activeLens: lens));
    try {
      await _channel.invokeMethod('setLens', {'lens': lens});
    } catch (_) {}
  }

  /// Ajusta zoom digital
  Future<void> setZoom(double zoom) async {
    _updateState(_state.copyWith(zoomLevel: zoom));
    try {
      await _channel.invokeMethod('setZoom', {'zoom': zoom});
    } catch (_) {}
  }

  /// Ajusta exposición (EV)
  Future<void> setExposure(double value) async {
    _updateState(_state.copyWith(exposureValue: value));
    try {
      await _channel.invokeMethod('setExposure', {'value': value});
    } catch (_) {}
  }

  /// Ajusta ISO
  Future<void> setISO(double iso) async {
    _updateState(_state.copyWith(isoValue: iso));
    try {
      await _channel.invokeMethod('setISO', {'iso': iso});
    } catch (_) {}
  }

  /// Ajusta balance de blancos (temperatura en Kelvin)
  Future<void> setWhiteBalance(double kelvin) async {
    _updateState(_state.copyWith(whiteBalance: kelvin));
    try {
      await _channel.invokeMethod('setWhiteBalance', {'kelvin': kelvin});
    } catch (_) {}
  }

  /// Cambia resolución y FPS
  Future<void> setResolution(String resolution, int fps) async {
    _updateState(_state.copyWith(
      resolution: '$resolution ${fps}FPS',
      fps: fps,
    ));
    try {
      await _channel.invokeMethod('setResolution', {
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
