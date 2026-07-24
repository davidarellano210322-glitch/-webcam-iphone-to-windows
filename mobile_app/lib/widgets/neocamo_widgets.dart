// ============================================================================
// WIDGETS REUTILIZABLES NEOCAMO
// GlassBadge, FooterBadge, VerticalMeterBar, BatteryWidget, LensSelector,
// TopAppBar, BottomToolBar, CornerViewfinder, StatusPill
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BADGE DE CRISTAL (telemetría de esquinas)
// ─────────────────────────────────────────────────────────────────────────────
class GlassBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final double fontSize;

  const GlassBadge({
    super.key,
    required this.icon,
    required this.label,
    this.color = NC.primary,
    this.fontSize = 11,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: NC.surfaceContainerLow.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: NC.white10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Geist',
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: NC.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BADGE DE PIE DE PÁGINA (estado de permisos: CAMERA, MIC, NET)
// ─────────────────────────────────────────────────────────────────────────────
class FooterBadge extends StatelessWidget {
  final String label;
  final bool isOk;

  const FooterBadge({
    super.key,
    required this.label,
    this.isOk = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: NC.surfaceContainerHigh.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NC.white05),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isOk ? NC.primary : NC.error,
              boxShadow: isOk
                  ? const [BoxShadow(color: NC.primaryGlow, blurRadius: 4)]
                  : null,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Geist',
              fontSize: 9,
              fontWeight: FontWeight.w500,
              color: NC.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BARRAS VERTICALES DE VÚMETRO (L y R)
// ─────────────────────────────────────────────────────────────────────────────
class VerticalMeterBar extends StatelessWidget {
  final List<double> bars;
  final Color activeColor;
  final Color bgColor;

  const VerticalMeterBar({
    super.key,
    required this.bars,
    this.activeColor = NC.primary,
    this.bgColor = NC.white10,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: bars.asMap().entries.map((entry) {
        final val = entry.value.clamp(0.0, 1.0);
        final isHigh = val > 0.7;
        final color = isHigh ? NC.red : (val > 0.4 ? const Color(0xFFFFC107) : activeColor);
        return Container(
          width: 4,
          height: 14,
          margin: const EdgeInsets.symmetric(vertical: 1),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(2),
          ),
          alignment: Alignment.bottomCenter,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            width: 4,
            height: 14 * val,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// INDICADOR DE BATERÍA VERTICAL
// ─────────────────────────────────────────────────────────────────────────────
class BatteryWidget extends StatelessWidget {
  final int percent;
  final double width;
  final double height;

  const BatteryWidget({
    super.key,
    required this.percent,
    this.width = 24,
    this.height = 40,
  });

  @override
  Widget build(BuildContext context) {
    final p = percent.clamp(0, 100) / 100.0;
    final barHeight = (height - 8) * p;
    final isLow = percent < 20;
    final batteryColor = isLow ? NC.error : NC.primary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            border: Border.all(color: NC.white20, width: 1.5),
            borderRadius: BorderRadius.circular(5),
          ),
          padding: const EdgeInsets.all(2),
          alignment: Alignment.bottomCenter,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: width - 6,
            height: barHeight.clamp(2.0, height - 4),
            decoration: BoxDecoration(                color: batteryColor.withValues(alpha: isLow ? 0.9 : 0.8),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        // Terminal de batería
        Container(
          width: width * 0.4,
          height: 4,
          decoration: BoxDecoration(
            color: NC.white20,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$percent%',
          style: TextStyle(
            fontFamily: 'Geist',
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: isLow ? NC.error : NC.primary,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SELECTOR DE LENTES (0.5x | 1x | 3x)
// ─────────────────────────────────────────────────────────────────────────────
class LensSelector extends StatelessWidget {
  final String activeLens;
  final ValueChanged<String> onLensChanged;
  final List<String> lenses;

  const LensSelector({
    super.key,
    required this.activeLens,
    required this.onLensChanged,
    this.lenses = const ['0.5x', '1x', '3x'],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: NC.white10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: lenses.map((lens) {
          final isSelected = lens == activeLens;
          return GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              onLensChanged(lens);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? NC.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                boxShadow: isSelected
                    ? const [BoxShadow(color: NC.primaryGlow, blurRadius: 10)]
                    : null,
              ),
              child: Text(
                lens,
                style: TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? NC.onPrimary : NC.onSurfaceVariant,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GLASS PANEL (contenedor con efecto vidrio esmerilado)
// ─────────────────────────────────────────────────────────────────────────────
class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Color bgColor;
  final double bgOpacity;
  final Color? borderColor;

  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.borderRadius = 12,
    this.bgColor = NC.surfaceContainerLow,
    this.bgOpacity = 0.6,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bgColor.withValues(alpha: bgOpacity),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: borderColor ?? NC.white10),
      ),
      child: child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PÍLDORA DE ESTADO (para metadatos como "4K 60FPS" o "USB CONECTADO")
// ─────────────────────────────────────────────────────────────────────────────
class StatusPill extends StatelessWidget {
  final String text;
  final Color? color;
  final double fontSize;
  final bool showDot;

  const StatusPill({
    super.key,
    required this.text,
    this.color,
    this.fontSize = 10,
    this.showDot = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: NC.white05,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: NC.white10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDot) ...[
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color ?? NC.primary,
                boxShadow: [
                  BoxShadow(
                    color: (color ?? NC.primary).withValues(alpha: 0.6),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: TextStyle(
              fontFamily: 'Geist',
              fontSize: fontSize,
              fontWeight: FontWeight.w500,
              color: color ?? NC.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ICON BUTTON NEOCAMO (con feedback háptico)
// ─────────────────────────────────────────────────────────────────────────────
class NCIconButton extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final VoidCallback? onPressed;
  final double size;

  const NCIconButton({
    super.key,
    required this.icon,
    this.color,
    this.onPressed,
    this.size = 24,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onPressed?.call();
      },
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.transparent,
        ),
        child: Icon(icon, color: color ?? NC.onSurfaceVariant, size: size),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BOTÓN DE GRABACIÓN / STREAM CENTRAL
// ─────────────────────────────────────────────────────────────────────────────
class RecordButton extends StatelessWidget {
  final bool isStreaming;
  final bool isRecording;
  final VoidCallback onTap;
  final Animation<double>? pulseAnimation;

  const RecordButton({
    super.key,
    required this.isStreaming,
    required this.isRecording,
    required this.onTap,
    this.pulseAnimation,
  });

  @override
  Widget build(BuildContext context) {
    final btnColor = isRecording
        ? NC.red
        : (isStreaming ? NC.primary : NC.primary);

    Widget button = Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: btnColor,
        border: Border.all(color: Colors.black.withValues(alpha: 0.4), width: 4),
        boxShadow: [
          BoxShadow(
            color: (isRecording ? NC.red : NC.primary).withValues(alpha: 0.5),
            blurRadius: 20,
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isRecording ? Icons.stop : Icons.play_arrow,
            color: isRecording ? Colors.white : NC.onPrimary,
            size: 30,
          ),
          Text(
            isRecording ? 'DETENER' : 'INICIAR',
            style: TextStyle(
              fontFamily: 'Geist',
              fontSize: 7,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: isRecording ? Colors.white : NC.onPrimary,
            ),
          ),
        ],
      ),
    );

    if (isRecording && pulseAnimation != null) {
      button = AnimatedBuilder(
        animation: pulseAnimation!,
        builder: (context, child) {
          return Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: NC.red.withValues(alpha: 0.3 + (pulseAnimation!.value * 0.5)),
                  blurRadius: 15 + (pulseAnimation!.value * 15),
                ),
              ],
            ),
            child: child,
          );
        },
        child: button,
      );
    }

    return GestureDetector(
      onTap: () {
        HapticFeedback.heavyImpact();
        onTap();
      },
      child: button,
    );
  }
}
