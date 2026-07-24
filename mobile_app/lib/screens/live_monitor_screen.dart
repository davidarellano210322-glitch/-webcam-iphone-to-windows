// ============================================================================
// PANTALLA 2: MONITOR EN VIVO PROFESIONAL (Live Monitor Screen)
// Vista previa de cámara real, telemetría, lens selector, vúmetros, batería
// Botón principal: iniciar/detener STREAMING hacia el servidor Windows
// ============================================================================

import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import '../services/telemetry_service.dart';
import '../widgets/custom_painters.dart';
import '../widgets/neocamo_widgets.dart';

class LiveMonitorScreen extends StatefulWidget {
  final TelemetryService telemetry;
  final CameraController? cameraController;
  final bool streamingActive; // true mientras el streaming nativo (Swift) está activo
  final VoidCallback onBack;
  final VoidCallback onOpenTune;
  final VoidCallback onOpenSettings;
  final Animation<double> recPulseAnimation;

  const LiveMonitorScreen({
    super.key,
    required this.telemetry,
    required this.cameraController,
    this.streamingActive = false,
    required this.onBack,
    required this.onOpenTune,
    required this.onOpenSettings,
    required this.recPulseAnimation,
  });

  @override
  State<LiveMonitorScreen> createState() => _LiveMonitorScreenState();
}

class _LiveMonitorScreenState extends State<LiveMonitorScreen> {
  TelemetryState _state = const TelemetryState();

  @override
  void initState() {
    super.initState();
    _state = widget.telemetry.state;
    widget.telemetry.onStateChanged = _onTelemetryChanged;
  }

  @override
  void dispose() {
    widget.telemetry.onStateChanged = null;
    super.dispose();
  }

  void _onTelemetryChanged(TelemetryState newState) {
    if (mounted) {
      setState(() => _state = newState);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Vista previa de cámara real
        Positioned.fill(child: _buildCameraPreview()),

        // Overlay de gradiente vignette
        Positioned.fill(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black54, Colors.transparent, Colors.black87],
              ),
            ),
          ),
        ),

        // Scanlines overlay
        Positioned.fill(
          child: CustomPaint(painter: ScanlinePainter(opacity: 0.08)),
        ),

        // Retícula cinematográfica
        Positioned.fill(
          child: CustomPaint(painter: const ViewfinderPainter()),
        ),

        // UI Overlay Layer
        SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildTopBar(),
              _buildCornerTelemetry(),
              const Spacer(),
              _buildLensSelector(),
              const SizedBox(height: 16),
              _buildBottomToolBar(),
            ],
          ),
        ),

        // Vúmetros de audio (izquierda)
        Positioned(
          left: 16,
          top: MediaQuery.of(context).size.height * 0.35,
          child: _buildAudioMeters(),
        ),

        // Batería / Almacenamiento (derecha)
        Positioned(
          right: 16,
          top: MediaQuery.of(context).size.height * 0.35,
          child: _buildBatteryAndStorage(),
        ),
      ],
    );
  }

  // ─── VISTA PREVIA DE CÁMARA REAL ─────────────────────────────────────────
  Widget _buildCameraPreview() {
    final ctrl = widget.cameraController;

    // Mientras el streaming nativo (Swift) está activo, iOS cede la cámara a
    // la AVCaptureSession de WebcamStreamer. No podemos mostrar el preview de
    // Flutter aquí (competiría por el hardware). Mostramos un estado en vivo.
    if (widget.streamingActive) {
      return _buildLiveStreamingBackground();
    }

    if (ctrl == null || !ctrl.value.isInitialized) {
      return _buildCameraPlaceholder();
    }
    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: ctrl.value.previewSize?.height ?? 1080,
            height: ctrl.value.previewSize?.width ?? 1920,
            child: CameraPreview(ctrl),
          ),
        ),
      ),
    );
  }

  /// Fondo durante el streaming: gradiente animado que refleja que el iPhone
  /// está transmitiendo hacia el PC (la cámara la usa el stream nativo).
  Widget _buildLiveStreamingBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 0.8,
          colors: [Color(0xFF1A2E1D), Color(0xFF0A0A0C)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.85, end: 1.0),
              duration: const Duration(milliseconds: 900),
              builder: (context, scale, child) =>
                  Transform.scale(scale: scale, child: child),
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: NC.primary.withValues(alpha: 0.15),
                  border: Border.all(color: NC.primary.withValues(alpha: 0.6), width: 2),
                  boxShadow: const [
                    BoxShadow(color: NC.primaryGlow, blurRadius: 30),
                  ],
                ),
                child: const Icon(Icons.cast_connected,
                    color: NC.primary, size: 44),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'TRANSMITIENDO AL PC',
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: NC.primary,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Mira la vista previa en NeoCamo Studio (Windows).\n'
              'La cámara del iPhone está dedicada al stream.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                color: Colors.white38,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraPlaceholder() {
    return Container(
      color: const Color(0xFF0A0A0C),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.videocam_off,
                color: NC.primary.withValues(alpha: 0.3), size: 64),
            const SizedBox(height: 16),
            const Text(
              'Cámara no inicializada',
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 12,
                color: Colors.white38,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Verifica permisos de cámara',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                color: Colors.white24,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── TOP BAR ─────────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: NC.bg.withValues(alpha: 0.7),
        border: const Border(bottom: BorderSide(color: NC.white10)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back,
                    color: NC.onSurfaceVariant, size: 20),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  widget.onBack();
                },
              ),
              const Icon(Icons.videocam, color: NC.primary, size: 22),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'MONITOR PRO-CAM',
                    style: TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: NC.primary,
                      letterSpacing: 1.2,
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _state.isStreaming ? NC.primary : NC.red,
                          boxShadow: _state.isStreaming
                              ? const [BoxShadow(color: NC.primaryGlow, blurRadius: 6)]
                              : null,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _state.connectionStatus,
                        style: const TextStyle(
                          fontFamily: 'Geist',
                          fontSize: 9,
                          color: NC.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: NC.white05,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: NC.white10),
            ),
            child: Row(
              children: [
                _buildTelemetryItem('RESOLUCIÓN', _state.resolution),
                const SizedBox(width: 8),
                Container(width: 1, height: 16, color: NC.white10),
                const SizedBox(width: 8),
                _buildTelemetryItem('BITRATE', _state.bitrate),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTelemetryItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Geist',
            fontSize: 7,
            color: NC.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontFamily: 'Geist',
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: NC.primary,
          ),
        ),
      ],
    );
  }

  // ─── TELEMTRÍA DE ESQUINAS ───────────────────────────────────────────────
  Widget _buildCornerTelemetry() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GlassBadge(
            icon: Icons.thermostat,
            label: '${_state.thermalTemp.toInt()}°C',
            color: NC.primary,
          ),
          GlassBadge(
            icon: Icons.speed,
            label: '${_state.latencyMs}ms',
            color: NC.secondary,
          ),
        ],
      ),
    );
  }

  // ─── SELECTOR DE LENTES ──────────────────────────────────────────────────
  Widget _buildLensSelector() {
    return LensSelector(
      activeLens: _state.activeLens,
      onLensChanged: (lens) => widget.telemetry.selectLens(lens),
    );
  }

  // ─── BARRA INFERIOR ──────────────────────────────────────────────────────
  Widget _buildBottomToolBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: NC.surfaceContainerLow.withValues(alpha: 0.85),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: const Border(top: BorderSide(color: NC.white10)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          IconButton(
            icon: Icon(
              _state.isFlashActive ? Icons.flash_on : Icons.flash_off,
              color: _state.isFlashActive ? NC.primary : NC.onSurfaceVariant,
            ),
            onPressed: () => widget.telemetry.toggleFlash(),
          ),
          IconButton(
            icon: const Icon(Icons.flip_camera_ios,
                color: NC.onSurfaceVariant),
            onPressed: () => widget.telemetry.switchCamera(),
          ),
          // Botón REC / STREAM central — controla el streaming hacia el PC
          RecordButton(
            isStreaming: _state.isStreaming,
            isRecording: _state.isRecording,
            onTap: () => widget.telemetry.toggleStreaming(),
            pulseAnimation: widget.recPulseAnimation,
          ),
          IconButton(
            icon: const Icon(Icons.tune, color: NC.onSurfaceVariant),
            onPressed: () {
              HapticFeedback.lightImpact();
              widget.onOpenTune();
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: NC.onSurfaceVariant),
            onPressed: () {
              HapticFeedback.lightImpact();
              widget.onOpenSettings();
            },
          ),
        ],
      ),
    );
  }

  // ─── VÚMETROS DE AUDIO ──────────────────────────────────────────────────
  Widget _buildAudioMeters() {
    return Column(
      children: [
        Row(
          children: [
            VerticalMeterBar(bars: widget.telemetry.audioLeft),
            const SizedBox(width: 3),
            VerticalMeterBar(bars: widget.telemetry.audioRight),
          ],
        ),
        const SizedBox(height: 8),
        Transform.rotate(
          angle: -math.pi / 2,
          child: const Text(
            'AUDIO',
            style: TextStyle(
              fontFamily: 'Geist',
              fontSize: 8,
              color: Colors.white38,
              letterSpacing: 2,
            ),
          ),
        ),
      ],
    );
  }

  // ─── BATERÍA Y ALMACENAMIENTO ────────────────────────────────────────────
  Widget _buildBatteryAndStorage() {
    return Column(
      children: [
        BatteryWidget(percent: _state.batteryPercent),
        const SizedBox(height: 20),
        const Icon(Icons.sd_card, color: Colors.white38, size: 20),
        const SizedBox(height: 2),
        const Text(
          '1.2TB',
          style: TextStyle(
            fontFamily: 'Geist',
            fontSize: 9,
            color: Colors.white54,
          ),
        ),
      ],
    );
  }
}
