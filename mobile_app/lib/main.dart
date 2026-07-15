import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const NeoCamoApp());

// ===== COLORES NEOCAMO =====
abstract class NC {
  static const bg = Color(0xFF131315);
  static const surface = Color(0xFF1F1F21);
  static const surfaceLow = Color(0xFF1B1B1D);
  static const primary = Color(0xFF55EE71);
  static const onSurface = Color(0xFFE4E2E4);
  static const onSurfaceVar = Color(0xFFBCCBB7);
  static const secondary = Color(0xFFAAC7FF);
  static const error = Color(0xFFFFB4AB);
  static const red = Color(0xFFDC2626);
  static const white10 = Color(0x19FFFFFF);
  static const white20 = Color(0x33FFFFFF);
}

class NeoCamoApp extends StatelessWidget {
  const NeoCamoApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'NeoCamo Monitor',
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark().copyWith(
      scaffoldBackgroundColor: NC.bg,
      colorScheme: const ColorScheme.dark(primary: NC.primary, surface: NC.bg, error: NC.error, onSurface: NC.onSurface),
    ),
    home: const MonitorScreen(),
  );
}

// ===== PANTALLA PRINCIPAL =====
class MonitorScreen extends StatefulWidget {
  const MonitorScreen({super.key});
  @override State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen> with SingleTickerProviderStateMixin {
  bool _streaming = false;
  String _status = "DISCONNECTED";
  String _lens = "1x";
  int _battery = 85;
  double _temp = 34.0;

  late AnimationController _recPulse;
  late AnimationController _audioCtrl;
  final List<double> _audioBars = List.filled(12, 0.05);

  static const platform = MethodChannel('com.antigravity.webcam/control');

  @override void initState() {
    super.initState();
    _recPulse = AnimationController(vsync: this, duration: const Duration(ms: 1000))..repeat(reverse: true);
    _audioCtrl = AnimationController(vsync: this, duration: const Duration(ms: 120))..repeat();
    _audioCtrl.addListener(_audioTick);
  }

  @override void dispose() {
    _audioCtrl.removeListener(_audioTick);
    _audioCtrl.dispose();
    _recPulse.dispose();
    super.dispose();
  }

  void _audioTick() {
    if (!_streaming) { for (int i = 0; i < 12; i++) _audioBars[i] = 0.05; }
    else { for (int i = 0; i < 12; i++) _audioBars[i] = 0.1 + math.Random().nextDouble() * 0.7; }
    if (mounted) setState(() {});
  }

  Future<void> _toggleStreaming() async {
    try {
      if (_streaming) {
        await platform.invokeMethod('stopServer');
        setState(() { _streaming = false; _status = "DISCONNECTED"; });
      } else {
        await platform.invokeMethod('startServer');
        setState(() { _streaming = true; _status = "USB CONNECTED"; });
      }
    } catch (e) { setState(() => _status = "ERROR"); }
  }

  Future<void> _switchCamera() async {
    try { await platform.invokeMethod('switchCamera'); } catch (_) {}
  }

  void _selectLens(String lens) => setState(() => _lens = lens);

  // ----- BUILD -----
  @override Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return Scaffold(
      body: Stack(
        children: [
          // Fondo negro puro simula vista de cámara
          Container(color: Colors.black),
          // Vignette overlay
          Positioned.fill(child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Color(0x99000000), Colors.transparent, Color(0x66000000)]),
            ),
          )),
          // Scanlines sutiles
          Positioned.fill(child: CustomPaint(painter: ScanlinePainter())),

          // === UI LAYER ===
          SafeArea(
            child: Column(
              children: [
                // ---- TOP BAR ----
                _TopBar(status: _status, lens: _lens, streaming: _streaming),

                const Spacer(),

                // ---- CENTER VIEWFINDER ----
                SizedBox(height: h * 0.15, child: CustomPaint(painter: ViewfinderPainter(), size: Size.infinite)),

                const Spacer(),

                // ---- LENS PILLS ----
                _LensPills(current: _lens, onSelect: _selectLens),
                const SizedBox(height: 16),

                // ---- BOTTOM BAR ----
                _BottomBar(streaming: _streaming, recPulse: _recPulse,
                  onToggle: _toggleStreaming, onFlip: _switchCamera),
              ],
            ),
          ),

          // ---- AUDIO METERS (left) ----
          Positioned(left: 16, top: h * 0.35, bottom: h * 0.35, child: _AudioMeters(bars: _audioBars)),

          // ---- BATTERY + STORAGE (right) ----
          Positioned(right: 16, top: h * 0.3, child: _BatteryWidget(pct: _battery)),
          Positioned(right: 16, top: h * 0.55, child: _StorageWidget()),

          // ---- CORNER BADGES ----
          Positioned(left: 16, top: h * 0.2, child: _TelemetryBadge(icon: Icons.thermostat, value: "${_temp.toInt()}°C")),
          Positioned(right: 16, top: h * 0.2, child: _TelemetryBadge(icon: Icons.speed, value: "12ms", color: NC.secondary)),
        ],
      ),
    );
  }
}

// ===== COMPONENTES =====

// --- Scanline painter ---
class ScanlinePainter extends CustomPainter {
  @override void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withAlpha(4);
    for (double y = 0; y < size.height; y += 4) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }
  @override bool shouldRepaint(covariant CustomPainter old) => false;
}

// --- Viewfinder ---
class ViewfinderPainter extends CustomPainter {
  @override void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.white.withAlpha(40)..style = PaintingStyle.stroke..strokeWidth = 1.5;
    final w = size.width, h = size.height;
    const s = 48.0;
    // Top-left
    canvas.drawLine(const Offset(0, 0), Offset(s, 0), p);
    canvas.drawLine(const Offset(0, 0), Offset(0, s), p);
    // Top-right
    canvas.drawLine(Offset(w - s, 0), Offset(w, 0), p);
    canvas.drawLine(Offset(w, 0), Offset(w, s), p);
    // Bottom-left
    canvas.drawLine(Offset(0, h - s), Offset(0, h), p);
    canvas.drawLine(const Offset(0, 0), Offset(s, h), p);
    // Bottom-right
    canvas.drawLine(Offset(w - s, h), Offset(w, h), p);
    canvas.drawLine(Offset(w, h - s), Offset(w, h), p);
    // Center crosshair
    final cx = w / 2, cy = h / 2;
    canvas.drawLine(Offset(cx - 20, cy), Offset(cx + 20, cy), p);
    canvas.drawLine(Offset(cx, cy - 20), Offset(cx, cy + 20), p);
  }
  @override bool shouldRepaint(covariant CustomPainter old) => false;
}

// --- Top Bar ---
class _TopBar extends StatelessWidget {
  final String status, lens;
  final bool streaming;
  const _TopBar({required this.status, required this.lens, required this.streaming});

  @override Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: NC.bg.withAlpha(180),
      border: const Border(bottom: BorderSide(color: NC.white10)),
    ),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Row(children: [
        const Icon(Icons.videocam, color: NC.primary, size: 22),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("PRO-CAM MONITOR", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: NC.primary, letterSpacing: 1.2)),
          const SizedBox(height: 2),
          Row(children: [
            _PulseDot(active: streaming),
            const SizedBox(width: 4),
            Text(status, style: TextStyle(fontSize: 9, color: NC.onSurfaceVar, letterSpacing: 1)),
          ]),
        ]),
      ]),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: NC.white10, borderRadius: BorderRadius.circular(20), border: Border.all(color: NC.white10)),
        child: Row(children: [
          Text("RES", style: TextStyle(fontSize: 8, color: NC.onSurfaceVar.withAlpha(150))),
          const SizedBox(width: 6),
          Text("1080p 60FPS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: NC.primary)),
        ]),
      ),
    ]),
  );
}

// --- Pulse dot animado ---
class _PulseDot extends StatelessWidget {
  final bool active;
  const _PulseDot({required this.active});
  @override Widget build(BuildContext context) => Container(
    width: 6, height: 6,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: active ? NC.primary : NC.error,
      boxShadow: active ? [BoxShadow(color: NC.primary.withAlpha(100), blurRadius: 8)] : null,
    ),
  );
}

// --- Lens Pills ---
class _LensPills extends StatelessWidget {
  final String current;
  final void Function(String) onSelect;
  const _LensPills({required this.current, required this.onSelect});

  static const _lenses = ['0.5x', '1x', '3x'];

  @override Widget build(BuildContext context) => Center(
    child: Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: Colors.black.withAlpha(100), borderRadius: BorderRadius.circular(40), border: Border.all(color: NC.white10)),
      child: Row(mainAxisSize: MainAxisSize.min, children: _lenses.map((l) {
        final sel = l == current;
        return GestureDetector(
          onTap: () => onSelect(l),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: sel ? NC.primary : NC.white10,
              borderRadius: BorderRadius.circular(40),
            ),
            child: Text(l, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: sel ? NC.bg : NC.onSurfaceVar)),
          ),
        );
      }).toList()),
    ),
  );
}

// --- Bottom Bar ---
class _BottomBar extends StatelessWidget {
  final bool streaming;
  final AnimationController recPulse;
  final VoidCallback onToggle, onFlip;
  const _BottomBar({required this.streaming, required this.recPulse, required this.onToggle, required this.onFlip});

  @override Widget build(BuildContext context) {
    final recAnim = recPulse.view;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      decoration: BoxDecoration(color: NC.surfaceLow.withAlpha(150), border: const Border(top: BorderSide(color: NC.white10)), borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        _NavBtn(icon: Icons.flash_off),
        _NavBtn(icon: Icons.flip_camera_ios, onTap: onFlip),
        // Central REC button
        GestureDetector(
          onTap: onToggle,
          child: AnimatedBuilder(
            animation: recAnim,
            builder: (_, child) => Container(
              width: 68, height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: streaming ? NC.red : NC.white10,
                border: Border.all(color: Colors.black.withAlpha(60), width: 4),
                boxShadow: streaming ? [BoxShadow(color: NC.red.withAlpha((recAnim.value * 130).toInt()), blurRadius: 24)] : null,
              ),
              child: child,
            ),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(streaming ? Icons.stop : Icons.circle, color: streaming ? Colors.white : NC.primary, size: 28),
            Text(streaming ? "STOP" : "REC", style: TextStyle(fontSize: 7, fontWeight: FontWeight.w700, color: streaming ? Colors.white : NC.primary, letterSpacing: 1.5)),
          ]),
        ),
        _NavBtn(icon: Icons.tune),
        _NavBtn(icon: Icons.settings),
      ]),
    );
  }
}

// --- Nav button ---
class _NavBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _NavBtn({required this.icon, this.onTap});
  @override Widget build(BuildContext context) => SizedBox(
    width: 44, height: 44,
    child: IconButton(icon: Icon(icon, color: NC.onSurfaceVar, size: 24), onPressed: onTap ?? () {}),
  );
}

// --- Audio Meters ---
class _AudioMeters extends StatelessWidget {
  final List<double> bars;
  const _AudioMeters({required this.bars});

  @override Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      ...List.generate(6, (i) => _MeterBar(height: bars[i])),
      const SizedBox(height: 8),
      ...List.generate(6, (i) => _MeterBar(height: bars[i + 6], secondChannel: true)),
      const SizedBox(height: 12),
      Text("AUDIO", style: TextStyle(fontSize: 7, color: Colors.white.withAlpha(100), letterSpacing: 2)),
    ],
  );
}

class _MeterBar extends StatelessWidget {
  final double height;
  final bool secondChannel;
  const _MeterBar({required this.height, this.secondChannel = false});
  @override Widget build(BuildContext context) => Container(
    width: 6, height: 24,
    margin: const EdgeInsets.symmetric(vertical: 1),
    decoration: BoxDecoration(color: NC.white10, borderRadius: BorderRadius.circular(3)),
    child: Align(
      alignment: Alignment.bottomCenter,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        height: 24 * height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(3),
          gradient: LinearGradient(
            begin: Alignment.bottomCenter, end: Alignment.topCenter,
            colors: [NC.primary, NC.secondary, secondChannel ? const Color(0xFFFFB74D) : NC.secondary],
          ),
        ),
      ),
    ),
  );
}

// --- Battery ---
class _BatteryWidget extends StatelessWidget {
  final int pct;
  const _BatteryWidget({required this.pct});

  @override Widget build(BuildContext context) => Column(children: [
    Container(
      width: 28, height: 44,
      decoration: BoxDecoration(
        border: Border.all(color: NC.white20, width: 2),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.all(2),
      child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
        Container(
          height: (40 * pct / 100).clamp(2.0, 40.0),
          decoration: BoxDecoration(color: NC.primary.withAlpha(200), borderRadius: BorderRadius.circular(3)),
        ),
      ]),
    ),
    const SizedBox(height: 6),
    Text("$pct%", style: TextStyle(fontSize: 9, color: NC.primary, fontWeight: FontWeight.w600)),
  ]);
}

// --- Storage ---
class _StorageWidget extends StatelessWidget {
  @override Widget build(BuildContext context) => Column(children: [
    Icon(Icons.sd_card, color: Colors.white.withAlpha(100), size: 22),
    const SizedBox(height: 4),
    Text("1.2TB", style: TextStyle(fontSize: 9, color: Colors.white.withAlpha(150))),
  ]);
}

// --- Telemetry Badge ---
class _TelemetryBadge extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color? color;
  const _TelemetryBadge({required this.icon, required this.value, this.color});

  @override Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(color: NC.surfaceLow.withAlpha(150), borderRadius: BorderRadius.circular(10), border: Border.all(color: NC.white10)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: color ?? NC.primary),
      const SizedBox(width: 4),
      Text(value, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: NC.onSurface)),
    ]),
  );
}