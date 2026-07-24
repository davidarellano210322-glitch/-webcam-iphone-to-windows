// ============================================================================
// CUSTOM PAINTERS - Efectos visuales de la app NeoCamo
// Incluye: Grid de fondo, Scanlines, Visor (esquinas + cruz), Anillos pulsantes
// ============================================================================

import 'package:flutter/material.dart';
import '../theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GRID DE FONDO (pantalla de conexión)
// ─────────────────────────────────────────────────────────────────────────────
class GridBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.03)
      ..strokeWidth = 0.5;
    const step = 40.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// SCANLINES (efecto de monitor CRT en ambas pantallas)
// ─────────────────────────────────────────────────────────────────────────────
class ScanlinePainter extends CustomPainter {
  final double opacity;
  ScanlinePainter({this.opacity = 0.08});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withValues(alpha: opacity);
    for (double y = 0; y < size.height; y += 4) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => old is! ScanlinePainter || old.opacity != opacity;
}

// ─────────────────────────────────────────────────────────────────────────────
// VISOR CINEMATOGRÁFICO (esquinas + retícula central)
// ─────────────────────────────────────────────────────────────────────────────
class ViewfinderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double cornerLength;

  const ViewfinderPainter({
    this.color = Colors.white38,
    this.strokeWidth = 1.5,
    this.cornerLength = 30,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    final w = size.width;
    final h = size.height;
    final s = cornerLength.toDouble();

    // Esquinas
    canvas.drawLine(Offset(w * 0.25, h * 0.25), Offset(w * 0.25 + s, h * 0.25), paint);
    canvas.drawLine(Offset(w * 0.25, h * 0.25), Offset(w * 0.25, h * 0.25 + s), paint);

    canvas.drawLine(Offset(w * 0.75, h * 0.25), Offset(w * 0.75 - s, h * 0.25), paint);
    canvas.drawLine(Offset(w * 0.75, h * 0.25), Offset(w * 0.75, h * 0.25 + s), paint);

    canvas.drawLine(Offset(w * 0.25, h * 0.75), Offset(w * 0.25 + s, h * 0.75), paint);
    canvas.drawLine(Offset(w * 0.25, h * 0.75), Offset(w * 0.25, h * 0.75 - s), paint);

    canvas.drawLine(Offset(w * 0.75, h * 0.75), Offset(w * 0.75 - s, h * 0.75), paint);
    canvas.drawLine(Offset(w * 0.75, h * 0.75), Offset(w * 0.75, h * 0.75 - s), paint);

    // Cruz central
    final cx = w / 2;
    final cy = h / 2;
    paint.strokeWidth = 1;
    final crossColor = Colors.white.withValues(alpha: 0.2);
    paint.color = crossColor;
    canvas.drawLine(Offset(cx - 12, cy), Offset(cx + 12, cy), paint);
    canvas.drawLine(Offset(cx, cy - 12), Offset(cx, cy + 12), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// ANILLOS PULSANTES (pantalla de conexión)
// ─────────────────────────────────────────────────────────────────────────────
class PulseRingsWidget extends StatelessWidget {
  final Animation<double> animation;
  final Color color;

  const PulseRingsWidget({
    super.key,
    required this.animation,
    this.color = NC.primary,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final val = animation.value;
        return Stack(
          alignment: Alignment.center,
          children: [
            // Anillo exterior
            Container(
              width: 220 + (val * 40),
              height: 220 + (val * 40),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: color.withValues(alpha: (0.25 - (val * 0.2)).clamp(0.0, 1.0)),
                  width: 1.5,
                ),
              ),
            ),
            // Anillo interior
            Container(
              width: 160 + (val * 30),
              height: 160 + (val * 30),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: color.withValues(alpha: (0.15 - (val * 0.12)).clamp(0.0, 1.0)),
                  width: 1.0,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
