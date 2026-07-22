// ============================================================================
// PANEL DE AJUSTES (Tune Panel) - Bottom Sheet Modal
// Sliders de exposición, ISO, balance de blancos, zoom, resolución y FPS
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import '../services/telemetry_service.dart';

class TunePanel extends StatefulWidget {
  final TelemetryService telemetry;
  final TelemetryState state;

  const TunePanel({
    super.key,
    required this.telemetry,
    required this.state,
  });

  @override
  State<TunePanel> createState() => _TunePanelState();
}

class _TunePanelState extends State<TunePanel> {
  late double _zoom;
  late double _exposure;
  late double _iso;
  late double _whiteBalance;
  late String _resolution;
  late int _fps;

  @override
  void initState() {
    super.initState();
    _zoom = widget.state.zoomLevel;
    _exposure = widget.state.exposureValue;
    _iso = widget.state.isoValue;
    _whiteBalance = widget.state.whiteBalance;
    final parts = widget.state.resolution.split(' ');
    _resolution = parts.isNotEmpty ? parts[0] : '1080p';
    _fps = widget.state.fps;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: NC.surfaceContainer,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: NC.white10)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Handle del modal
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: NC.white20,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Título
              Row(
                children: const [
                  Icon(Icons.tune, color: NC.primary, size: 22),
                  SizedBox(width: 8),
                  Text(
                    'Ajustes de Cámara',
                    style: TextStyle(
                      fontFamily: 'Hanken Grotesk',
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: NC.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Zoom
              _buildSlider(
                label: 'ZOOM',
                value: _zoom,
                min: 0.5,
                max: 6.0,
                divisions: 55,
                suffix: 'x',
                icon: Icons.zoom_in,
                onChanged: (v) => setState(() => _zoom = v),
                onChangeEnd: (v) => widget.telemetry.setZoom(v),
              ),
              const SizedBox(height: 16),
              // Exposición (EV)
              _buildSlider(
                label: 'EXPOSICIÓN (EV)',
                value: _exposure,
                min: -2.0,
                max: 2.0,
                divisions: 40,
                suffix: ' EV',
                icon: Icons.exposure,
                onChanged: (v) => setState(() => _exposure = v),
                onChangeEnd: (v) => widget.telemetry.setExposure(v),
              ),
              const SizedBox(height: 16),
              // ISO
              _buildSlider(
                label: 'ISO',
                value: _iso,
                min: 25,
                max: 3200,
                divisions: 100,
                suffix: '',
                icon: Icons.camera,
                onChanged: (v) => setState(() => _iso = v),
                onChangeEnd: (v) => widget.telemetry.setISO(v),
              ),
              const SizedBox(height: 16),
              // Balance de Blancos (Kelvin)
              _buildSlider(
                label: 'BALANCE DE BLANCOS',
                value: _whiteBalance,
                min: 2000,
                max: 10000,
                divisions: 80,
                suffix: ' K',
                icon: Icons.wb_sunny,
                onChanged: (v) => setState(() => _whiteBalance = v),
                onChangeEnd: (v) => widget.telemetry.setWhiteBalance(v),
              ),
              const SizedBox(height: 20),
              // Resolución + FPS
              Row(
                children: [
                  Expanded(child: _buildResolutionSelector()),
                  const SizedBox(width: 12),
                  Expanded(child: _buildFpsSelector()),
                ],
              ),
              const SizedBox(height: 16),
              // Botón Aplicar
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: NC.primary,
                  foregroundColor: NC.onPrimary,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  widget.telemetry
                      .setResolution(_resolution, _fps);
                  Navigator.pop(context);
                },
                child: const Text(
                  'Aplicar cambios',
                  style: TextStyle(
                    fontFamily: 'Hanken Grotesk',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── SLIDER INDIVIDUAL ────────────────────────────────────────────────────
  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String suffix,
    required IconData icon,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(icon, color: NC.primary, size: 14),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: NC.onSurfaceVariant,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
            Text(
              '${value.toStringAsFixed(value < 10 ? 1 : 0)}$suffix',
              style: const TextStyle(
                fontFamily: 'Geist',
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: NC.primary,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: NC.primary,
            inactiveTrackColor: NC.white10,
            thumbColor: NC.primary,
            overlayColor: NC.primaryGlow,
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
            onChangeEnd: (v) {
              HapticFeedback.selectionClick();
              onChangeEnd(v);
            },
          ),
        ),
      ],
    );
  }

  // ─── SELECTOR DE RESOLUCIÓN ───────────────────────────────────────────────
  Widget _buildResolutionSelector() {
    const options = ['720p', '1080p', '4K'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'RESOLUCIÓN',
          style: TextStyle(
            fontFamily: 'Geist',
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: NC.onSurfaceVariant,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: NC.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: NC.white10),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _resolution,
              isExpanded: true,
              dropdownColor: NC.surfaceContainer,
              style: const TextStyle(
                fontFamily: 'Geist',
                fontSize: 13,
                color: NC.onSurface,
              ),
              items: options
                  .map((r) => DropdownMenuItem(
                        value: r,
                        child: Text(r),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _resolution = v);
              },
            ),
          ),
        ),
      ],
    );
  }

  // ─── SELECTOR DE FPS ─────────────────────────────────────────────────────
  Widget _buildFpsSelector() {
    const options = [24, 30, 60];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'FPS',
          style: TextStyle(
            fontFamily: 'Geist',
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: NC.onSurfaceVariant,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: NC.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: NC.white10),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _fps,
              isExpanded: true,
              dropdownColor: NC.surfaceContainer,
              style: const TextStyle(
                fontFamily: 'Geist',
                fontSize: 13,
                color: NC.onSurface,
              ),
              items: options
                  .map((f) => DropdownMenuItem(
                        value: f,
                        child: Text('$f FPS'),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _fps = v);
              },
            ),
          ),
        ),
      ],
    );
  }
}
