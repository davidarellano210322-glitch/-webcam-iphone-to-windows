import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const NeoCamoApp());
}

// ============================================================================
// SISTEMA DE DISEÑO & PALETA DE COLORES NEOCAMO
// ============================================================================
abstract class NC {
  static const bg = Color(0xFF131315);
  static const surface = Color(0xFF131315);
  static const surfaceContainer = Color(0xFF1F1F21);
  static const surfaceContainerLow = Color(0xFF1B1B1D);
  static const surfaceContainerHigh = Color(0xFF2A2A2C);
  static const surfaceBright = Color(0xFF39393B);
  
  static const primary = Color(0xFF55EE71);
  static const primaryGlow = Color(0x4055EE71);
  static const onPrimary = Color(0xFF003910);
  
  static const secondary = Color(0xFFAAC7FF);
  static const tertiary = Color(0xFFFFC4BA);
  static const error = Color(0xFFFFB4AB);
  static const red = Color(0xFFDC2626);
  static const redGlow = Color(0x80DC2626);
  
  static const onSurface = Color(0xFFE4E2E4);
  static const onSurfaceVar = Color(0xFFBCCBB7);
  static const outline = Color(0xFF869583);
  
  static const white05 = Color(0x0DFFFFFF);
  static const white10 = Color(0x1AFFFFFF);
  static const white20 = Color(0x33FFFFFF);
  static const white40 = Color(0x66FFFFFF);
}

class NeoCamoApp extends StatelessWidget {
  const NeoCamoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NeoCamo | Professional Monitor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: NC.bg,
        colorScheme: const ColorScheme.dark(
          primary: NC.primary,
          surface: NC.bg,
          error: NC.error,
          onSurface: NC.onSurface,
        ),
      ),
      home: const NeoCamoMainScreen(),
    );
  }
}

// ============================================================================
// PANTALLA PRINCIPAL CON NAVEGACIÓN ENTRE SETUP Y MONITOR PROFESIONAL
// ============================================================================
class NeoCamoMainScreen extends StatefulWidget {
  const NeoCamoMainScreen({super.key});

  @override
  State<NeoCamoMainScreen> createState() => _NeoCamoMainScreenState();
}

class _NeoCamoMainScreenState extends State<NeoCamoMainScreen> with TickerProviderStateMixin {
  // Estado de Navegación
  int _currentScreenIndex = 0; // 0 = Connection & Setup, 1 = Live Monitor

  // Estado de Transmisión & Cámara
  bool _isStreaming = false;
  String _connectionStatus = "DISCONNECTED";
  String _activeLens = "1x";
  bool _isFlashActive = false;
  int _batteryPercent = 85;
  double _thermalTemp = 34.0;
  String _currentResolution = "1080p 60FPS";
  String _currentBitrate = "8.5 Mbps";
  int _latencyMs = 12;

  // Animation Controllers
  late AnimationController _pulseRingCtrl;
  late AnimationController _bounceAntennaCtrl;
  late AnimationController _recPulseCtrl;
  late AnimationController _audioMeterCtrl;

  final List<double> _audioBarsLeft = List.filled(6, 0.1);
  final List<double> _audioBarsRight = List.filled(6, 0.1);

  static const platform = MethodChannel('com.antigravity.webcam/control');

  @override
  void initState() {
    super.initState();

    // Controller para anillos pulsantes en la pantalla de inicio
    _pulseRingCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    // Controller para antena rebotando
    _bounceAntennaCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    // Controller para botón REC rojo en streaming
    _recPulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    // Controller para animación de vúmetros de audio
    _audioMeterCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    )..repeat();

    _audioMeterCtrl.addListener(_updateAudioMeters);
  }

  @override
  void dispose() {
    _audioMeterCtrl.removeListener(_updateAudioMeters);
    _pulseRingCtrl.dispose();
    _bounceAntennaCtrl.dispose();
    _recPulseCtrl.dispose();
    _audioMeterCtrl.dispose();
    super.dispose();
  }

  void _updateAudioMeters() {
    if (!_isStreaming) {
      for (int i = 0; i < 6; i++) {
        _audioBarsLeft[i] = 0.05;
        _audioBarsRight[i] = 0.05;
      }
    } else {
      final rand = math.Random();
      for (int i = 0; i < 6; i++) {
        _audioBarsLeft[i] = (0.2 + rand.nextDouble() * 0.75).clamp(0.05, 1.0);
        _audioBarsRight[i] = (0.2 + rand.nextDouble() * 0.75).clamp(0.05, 1.0);
      }
    }
    if (mounted) setState(() {});
  }

  // --- MÉTODOS DE CONTROL ---
  Future<void> _toggleStreaming() async {
    try {
      if (_isStreaming) {
        await platform.invokeMethod('stopServer');
        setState(() {
          _isStreaming = false;
          _connectionStatus = "DISCONNECTED";
        });
      } else {
        await platform.invokeMethod('startServer');
        setState(() {
          _isStreaming = true;
          _connectionStatus = "USB CONNECTED";
        });
      }
    } catch (_) {
      // Alternar localmente para pruebas de UI
      setState(() {
        _isStreaming = !_isStreaming;
        _connectionStatus = _isStreaming ? "USB CONNECTED" : "DISCONNECTED";
      });
    }
  }

  Future<void> _switchCamera() async {
    try {
      await platform.invokeMethod('switchCamera');
    } catch (_) {}
  }

  Future<void> _toggleFlash() async {
    try {
      await platform.invokeMethod('toggleFlash');
      setState(() => _isFlashActive = !_isFlashActive);
    } catch (_) {
      setState(() => _isFlashActive = !_isFlashActive);
    }
  }

  void _selectLens(String lens) {
    setState(() => _activeLens = lens);
    try {
      platform.invokeMethod('setLens', {'lens': lens});
    } catch (_) {}
  }

  void _goToMonitorScreen() {
    setState(() {
      _currentScreenIndex = 1;
    });
  }

  void _goToSetupScreen() {
    setState(() {
      _currentScreenIndex = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: _currentScreenIndex == 0
            ? _buildConnectionSetupScreen()
            : _buildProfessionalMonitorScreen(),
      ),
    );
  }

  // =========================================================================
  // SCREEN 1: CONNECTION & SETUP SCREEN (DISEÑO FIEL AL HTML DE EJEMPLO)
  // =========================================================================
  Widget _buildConnectionSetupScreen() {
    return Stack(
      key: const ValueKey('ConnectionSetupScreen'),
      children: [
        // Fondo con Grid personalizado
        Positioned.fill(
          child: CustomPaint(painter: GridBackgroundPainter()),
        ),

        // Scanlines overlay
        Positioned.fill(
          child: CustomPaint(painter: ScanlinePainter(opacity: 0.03)),
        ),

        SafeArea(
          child: Column(
            children: [
              // Top App Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.videocam, color: NC.primary, size: 22),
                        SizedBox(width: 8),
                        Text(
                          "PRO-CAM MONITOR",
                          style: TextStyle(
                            fontFamily: 'Geist',
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: NC.primary,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: NC.white05,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: NC.white10),
                      ),
                      child: Text(
                        "4K 60FPS",
                        style: TextStyle(
                          fontFamily: 'Geist',
                          fontSize: 10,
                          color: NC.onSurfaceVar,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      const SizedBox(height: 20),

                      // Connection Visualizer (Teléfono + Laptop + Anillos)
                      SizedBox(
                        height: 260,
                        width: double.infinity,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Anillos de Pulso Animados
                            AnimatedBuilder(
                              animation: _pulseRingCtrl,
                              builder: (context, child) {
                                final val = _pulseRingCtrl.value;
                                return Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Container(
                                      width: 220 + (val * 40),
                                      height: 220 + (val * 40),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: NC.primary.withOpacity((0.3 - (val * 0.25)).clamp(0.0, 1.0)),
                                          width: 1.5,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      width: 160 + (val * 30),
                                      height: 160 + (val * 30),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: NC.primary.withOpacity((0.2 - (val * 0.15)).clamp(0.0, 1.0)),
                                          width: 1.0,
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),

                            // Gráfico de Teléfono Móvil
                            Transform.translate(
                              offset: const Offset(-45, 0),
                              child: Transform.rotate(
                                angle: -0.1,
                                child: Container(
                                  width: 100,
                                  height: 190,
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: NC.surfaceContainer,
                                    borderRadius: BorderRadius.circular(28),
                                    border: Border.all(color: NC.surfaceBright, width: 4),
                                    boxShadow: const [
                                      BoxShadow(color: Colors.black54, blurRadius: 20, offset: Offset(0, 10))
                                    ],
                                  ),
                                  child: Column(
                                    children: [
                                      Container(
                                        width: 36, height: 4,
                                        decoration: BoxDecoration(color: NC.surfaceBright, borderRadius: BorderRadius.circular(2)),
                                      ),
                                      const SizedBox(height: 8),
                                      Expanded(
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: Colors.black,
                                            borderRadius: BorderRadius.circular(18),
                                            border: Border.all(color: NC.white10),
                                          ),
                                          child: const Center(
                                            child: Icon(Icons.camera_alt, color: NC.primaryGlow, size: 36),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Container(
                                        width: 20, height: 20,
                                        decoration: const BoxDecoration(color: NC.surfaceBright, shape: BoxShape.circle),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            // Gráfico de Laptop
                            Transform.translate(
                              offset: const Offset(45, 25),
                              child: Container(
                                width: 220,
                                height: 140,
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: NC.surfaceContainer,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: NC.white10),
                                  boxShadow: const [
                                    BoxShadow(color: Colors.black80, blurRadius: 25, offset: Offset(0, 12))
                                  ],
                                ),
                                child: Column(
                                  children: [
                                    Expanded(
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.black,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: NC.white10),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Row(
                                                  children: const [
                                                    CircleAvatar(radius: 3, backgroundColor: NC.red),
                                                    SizedBox(width: 4),
                                                    CircleAvatar(radius: 3, backgroundColor: Colors.amber),
                                                    SizedBox(width: 4),
                                                    CircleAvatar(radius: 3, backgroundColor: NC.primary),
                                                  ],
                                                ),
                                                const Text(
                                                  "NEOCAMO_STUDIO_V2.1",
                                                  style: TextStyle(fontFamily: 'Geist', fontSize: 7, color: NC.primaryGlow),
                                                ),
                                              ],
                                            ),
                                            const Spacer(),
                                            Center(
                                              child: Column(
                                                children: [
                                                  Container(width: 100, height: 3, color: NC.white10),
                                                  const SizedBox(height: 4),
                                                  Container(width: 70, height: 3, color: NC.white10),
                                                ],
                                              ),
                                            ),
                                            const Spacer(),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Container(height: 10, width: double.infinity, color: NC.surfaceBright.withOpacity(0.5)),
                                  ],
                                ),
                              ),
                            ),

                            // Animated Wireless Wave / Antena
                            AnimatedBuilder(
                              animation: _bounceAntennaCtrl,
                              builder: (context, child) {
                                return Transform.translate(
                                  offset: Offset(0, -8 * _bounceAntennaCtrl.value),
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: NC.bg.withOpacity(0.8),
                                      shape: BoxShape.circle,
                                      border: Border.all(color: NC.primary.withOpacity(0.4)),
                                      boxShadow: const [
                                        BoxShadow(color: NC.primaryGlow, blurRadius: 20)
                                      ],
                                    ),
                                    child: const Icon(Icons.settings_input_antenna, color: NC.primary, size: 36),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Título & Descripción
                      const Text(
                        "Ready to Connect",
                        style: TextStyle(
                          fontFamily: 'Hanken Grotesk',
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: NC.onSurface,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Instrucciones 1 y 2
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: NC.surfaceContainerLow.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: NC.white05),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 22, height: 22,
                                  decoration: BoxDecoration(
                                    color: NC.primary.withOpacity(0.2),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Center(
                                    child: Text(
                                      "1",
                                      style: TextStyle(fontFamily: 'Geist', fontSize: 10, fontWeight: FontWeight.bold, color: NC.primary),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Text(
                                    "Open NeoCamo Studio on your computer.",
                                    style: TextStyle(fontSize: 13, color: NC.onSurfaceVar),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Container(
                                  width: 22, height: 22,
                                  decoration: BoxDecoration(
                                    color: NC.primary.withOpacity(0.2),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Center(
                                    child: Text(
                                      "2",
                                      style: TextStyle(fontFamily: 'Geist', fontSize: 10, fontWeight: FontWeight.bold, color: NC.primary),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Text(
                                    "Connect via USB cable or use WiFi for freedom.",
                                    style: TextStyle(fontSize: 13, color: NC.onSurfaceVar),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Botones de Selección de Modo
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: NC.primary,
                          foregroundColor: NC.onPrimary,
                          minimumSize: const Size(double.infinity, 56),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 10,
                          shadowColor: NC.primaryGlow,
                        ),
                        onPressed: _goToMonitorScreen,
                        icon: const Icon(Icons.wifi, size: 22),
                        label: const Text(
                          "WiFi Connect (Auto-Discovery)",
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 12),

                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: NC.onSurface,
                          minimumSize: const Size(double.infinity, 54),
                          side: const BorderSide(color: NC.white20),
                          backgroundColor: NC.surfaceContainer.withOpacity(0.7),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: _goToMonitorScreen,
                        icon: const Icon(Icons.usb, color: NC.primary, size: 22),
                        label: const Text(
                          "USB Priority Mode",
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                        ),
                      ),
                      const SizedBox(height: 8),

                      TextButton.icon(
                        onPressed: () {
                          _showTroubleshootModal(context);
                        },
                        icon: const Icon(Icons.help_outline, color: NC.onSurfaceVar, size: 18),
                        label: const Text(
                          "Troubleshoot Connection",
                          style: TextStyle(fontFamily: 'Geist', fontSize: 12, color: NC.onSurfaceVar),
                        ),
                      ),

                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),

              // Footer Badges
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        _FooterBadge(label: "CAMERA: OK"),
                        SizedBox(width: 8),
                        _FooterBadge(label: "MIC: OK"),
                        SizedBox(width: 8),
                        _FooterBadge(label: "LOCAL NET: OK"),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "BUILD: NC-2026.08-PRO // V2.5.0",
                      style: TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 9,
                        color: Colors.white24,
                        letterSpacing: 2.0,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // SCREEN 2: PROFESSIONAL LIVE MONITOR SCREEN (DISEÑO FIEL AL HTML 2)
  // =========================================================================
  Widget _buildProfessionalMonitorScreen() {
    return Stack(
      key: const ValueKey('ProfessionalMonitorScreen'),
      children: [
        // Live Camera Preview (Simulada / Fondo de cámara real)
        Positioned.fill(
          child: Container(
            color: Colors.black,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Imagen de muestra cinematográfica o vista de cámara
                Image.network(
                  "https://lh3.googleusercontent.com/aida-public/AB6AXuAAY90iB3CdPTTUr-swSglSZpuiicmj6Zg9nqHa83M0jy8MY27zcvg_HDhr5iqBzQuuW3vSQjz-vtQNXP9odrSXUXbvxs80jWDGs4BqvrKfjqfzfDuNVpLsnl92Ufq7P1ub1jLZ4rSHZ1cp5Hc6Oalv5HuGdw_FeVJhY_U4kODQN7_oY6XeIIXuDPPLUW-bTQaPlzqPsAMYzs0TVGWUqJpWeZOxloTXMnpQ66zlq0XEqSI6BWxSoGaaO2ftKPlIdjeYGdk9fuzGuqU",
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(color: const Color(0xFF0F0F11)),
                ),
                // Overlay de Gradiente Vignette
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black54, Colors.transparent, Colors.black80],
                    ),
                  ),
                ),
                // Scanlines overlay
                CustomPaint(painter: ScanlinePainter(opacity: 0.1)),
              ],
            ),
          ),
        ),

        // Retícula Cinematográfica del Visor (Corners + Crosshair)
        Positioned.fill(
          child: CustomPaint(painter: ViewfinderPainter()),
        ),

        // UI Overlay Layer
        SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // --- TOP APP BAR ---
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: NC.bg.withOpacity(0.7),
                  border: const Border(bottom: BorderSide(color: NC.white10)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back, color: NC.onSurfaceVar, size: 20),
                          onPressed: _goToSetupScreen,
                        ),
                        const Icon(Icons.videocam, color: NC.primary, size: 22),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              "PRO-CAM MONITOR",
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
                                  width: 6, height: 6,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _isStreaming ? NC.primary : NC.red,
                                    boxShadow: _isStreaming ? const [BoxShadow(color: NC.primaryGlow, blurRadius: 6)] : null,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _connectionStatus,
                                  style: const TextStyle(fontFamily: 'Geist', fontSize: 9, color: NC.onSurfaceVar),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                    // Telemetría de Resolución & Bitrate
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: NC.white05,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: NC.white10),
                          ),
                          child: Row(
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  const Text("RESOLUTION", style: TextStyle(fontFamily: 'Geist', fontSize: 7, color: NC.onSurfaceVar)),
                                  Text(_currentResolution, style: const TextStyle(fontFamily: 'Geist', fontSize: 10, fontWeight: FontWeight.bold, color: NC.primary)),
                                ],
                              ),
                              const SizedBox(width: 8),
                              Container(width: 1, height: 16, color: NC.white10),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  const Text("BITRATE", style: TextStyle(fontFamily: 'Geist', fontSize: 7, color: NC.onSurfaceVar)),
                                  Text(_currentBitrate, style: const TextStyle(fontFamily: 'Geist', fontSize: 10, fontWeight: FontWeight.bold, color: NC.primary)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // --- CORNER TELEMETRY BADGES ---
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _GlassBadge(icon: Icons.thermostat, label: "${_thermalTemp.toInt()}°C", color: NC.primary),
                    _GlassBadge(icon: Icons.speed, label: "${_latencyMs}ms", color: NC.secondary),
                  ],
                ),
              ),

              const Spacer(),

              // --- LENS SELECTOR PILLS (0.5x, 1x, 3x) ---
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: NC.white10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: ['0.5x', '1x', '3x'].map((lens) {
                    final isSelected = lens == _activeLens;
                    return GestureDetector(
                      onTap: () => _selectLens(lens),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected ? NC.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: isSelected ? const [BoxShadow(color: NC.primaryGlow, blurRadius: 10)] : null,
                        ),
                        child: Text(
                          lens,
                          style: TextStyle(
                            fontFamily: 'Geist',
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? NC.onPrimary : NC.onSurfaceVar,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: 16),

              // --- BOTTOM TOOLBAR ---
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: NC.surfaceContainerLow.withOpacity(0.85),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  border: const Border(top: BorderSide(color: NC.white10)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    IconButton(
                      icon: Icon(_isFlashActive ? Icons.flash_on : Icons.flash_off, color: _isFlashActive ? NC.primary : NC.onSurfaceVar),
                      onPressed: _toggleFlash,
                    ),
                    IconButton(
                      icon: const Icon(Icons.flip_camera_ios, color: NC.onSurfaceVar),
                      onPressed: _switchCamera,
                    ),

                    // Central REC / STREAM Button
                    GestureDetector(
                      onTap: _toggleStreaming,
                      child: AnimatedBuilder(
                        animation: _recPulseCtrl,
                        builder: (context, child) {
                          final pulseVal = _isStreaming ? _recPulseCtrl.value : 0.0;
                          return Container(
                            width: 68,
                            height: 68,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isStreaming ? NC.red : NC.primary,
                              border: Border.all(color: Colors.black.withOpacity(0.4), width: 4),
                              boxShadow: [
                                BoxShadow(
                                  color: (_isStreaming ? NC.red : NC.primary).withOpacity(0.4 + (pulseVal * 0.4)),
                                  blurRadius: 15 + (pulseVal * 10),
                                )
                              ],
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _isStreaming ? Icons.stop : Icons.play_arrow,
                                  color: _isStreaming ? Colors.white : NC.onPrimary,
                                  size: 28,
                                ),
                                Text(
                                  _isStreaming ? "STOP" : "START",
                                  style: TextStyle(
                                    fontFamily: 'Geist',
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                    color: _isStreaming ? Colors.white : NC.onPrimary,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),

                    IconButton(
                      icon: const Icon(Icons.tune, color: NC.onSurfaceVar),
                      onPressed: () {},
                    ),
                    IconButton(
                      icon: const Icon(Icons.settings, color: NC.onSurfaceVar),
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // --- AUDIO METERS (LEFT SIDE OVERLAY) ---
        Positioned(
          left: 16,
          top: MediaQuery.of(context).size.height * 0.35,
          child: Column(
            children: [
              Row(
                children: [
                  _VerticalMeterBar(bars: _audioBarsLeft),
                  const SizedBox(width: 3),
                  _VerticalMeterBar(bars: _audioBarsRight),
                ],
              ),
              const SizedBox(height: 8),
              Transform.rotate(
                angle: -math.pi / 2,
                child: const Text(
                  "AUDIO",
                  style: TextStyle(fontFamily: 'Geist', fontSize: 8, color: Colors.white38, letterSpacing: 2),
                ),
              ),
            ],
          ),
        ),

        // --- BATTERY / STORAGE (RIGHT SIDE OVERLAY) ---
        Positioned(
          right: 16,
          top: MediaQuery.of(context).size.height * 0.35,
          child: Column(
            children: [
              // Batería Widget
              Container(
                width: 24,
                height: 40,
                decoration: BoxDecoration(
                  border: Border.all(color: NC.white20, width: 1.5),
                  borderRadius: BorderRadius.circular(5),
                ),
                padding: const EdgeInsets.all(2),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    height: (32 * _batteryPercent / 100).toDouble(),
                    decoration: BoxDecoration(
                      color: NC.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "$_batteryPercent%",
                style: const TextStyle(fontFamily: 'Geist', fontSize: 9, color: NC.primary, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 20),

              // Storage Widget
              const Icon(Icons.sd_card, color: Colors.white38, size: 20),
              const SizedBox(height: 2),
              const Text(
                "1.2TB",
                style: TextStyle(fontFamily: 'Geist', fontSize: 9, color: Colors.white54),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showTroubleshootModal(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: NC.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: NC.white10)),
        title: Row(
          children: const [
            Icon(Icons.help_outline, color: NC.primary),
            SizedBox(width: 8),
            Text("Connection Troubleshoot", style: TextStyle(fontFamily: 'Hanken Grotesk', fontSize: 18, color: NC.onSurface)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text("1. Asegúrate de que NeoCamo Studio esté abierto en tu PC.", style: TextStyle(fontSize: 13, color: NC.onSurfaceVar)),
            SizedBox(height: 8),
            Text("2. Si usas cable USB en iPhone, presiona 'Confiar en esta computadora'.", style: TextStyle(fontSize: 13, color: NC.onSurfaceVar)),
            SizedBox(height: 8),
            Text("3. En Android, activa la Depuración por USB y ejecuta 'python setup_usb.py'.", style: TextStyle(fontSize: 13, color: NC.onSurfaceVar)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Entendido", style: TextStyle(color: NC.primary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// PAINTERS PERSONALIZADOS PARA RETÍCULA Y GRID
// ============================================================================

class _FooterBadge extends StatelessWidget {
  final String label;
  const _FooterBadge({required this.label});
  @override Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: NC.surfaceContainerHigh.withOpacity(0.8),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: NC.white05),
    ),
    child: Row(
      children: [
        Container(
          width: 5, height: 5,
          decoration: const BoxDecoration(color: NC.primary, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontFamily: 'Geist', fontSize: 9, color: NC.onSurfaceVar)),
      ],
    ),
  );
}

class _GlassBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _GlassBadge({required this.icon, required this.label, required this.color});

  @override Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: NC.surfaceContainerLow.withOpacity(0.7),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: NC.white10),
    ),
    child: Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontFamily: 'Geist', fontSize: 11, fontWeight: FontWeight.bold, color: NC.onSurface)),
      ],
    ),
  );
}

class _VerticalMeterBar extends StatelessWidget {
  final List<double> bars;
  const _VerticalMeterBar({required this.bars});

  @override Widget build(BuildContext context) => Column(
    children: bars.map((val) => Container(
      width: 4, height: 14,
      margin: const EdgeInsets.symmetric(vertical: 1),
      decoration: BoxDecoration(
        color: NC.white10,
        borderRadius: BorderRadius.circular(2),
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          height: 14 * val,
          decoration: BoxDecoration(
            color: NC.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    )).toList(),
  );
}

class GridBackgroundPainter extends CustomPainter {
  @override void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.02)
      ..strokeWidth = 1.0;
    const step = 40.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }
  @override bool shouldRepaint(covariant CustomPainter old) => false;
}

class ScanlinePainter extends CustomPainter {
  final double opacity;
  ScanlinePainter({this.opacity = 0.05});
  @override void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withOpacity(opacity);
    for (double y = 0; y < size.height; y += 4) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }
  @override bool shouldRepaint(covariant CustomPainter old) => false;
}

class ViewfinderPainter extends CustomPainter {
  @override void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final w = size.width;
    final h = size.height;
    const s = 30.0;

    // ESQUINAS
    canvas.drawLine(Offset(w * 0.2, h * 0.2), Offset(w * 0.2 + s, h * 0.2), p);
    canvas.drawLine(Offset(w * 0.2, h * 0.2), Offset(w * 0.2, h * 0.2 + s), p);

    canvas.drawLine(Offset(w * 0.8, h * 0.2), Offset(w * 0.8 - s, h * 0.2), p);
    canvas.drawLine(Offset(w * 0.8, h * 0.2), Offset(w * 0.8, h * 0.2 + s), p);

    canvas.drawLine(Offset(w * 0.2, h * 0.8), Offset(w * 0.2 + s, h * 0.8), p);
    canvas.drawLine(Offset(w * 0.2, h * 0.8), Offset(w * 0.2, h * 0.8 - s), p);

    canvas.drawLine(Offset(w * 0.8, h * 0.8), Offset(w * 0.8 - s, h * 0.8), p);
    canvas.drawLine(Offset(w * 0.8, h * 0.8), Offset(w * 0.8, h * 0.8 - s), p);

    // CRUZ CENTRAL
    final cx = w / 2;
    final cy = h / 2;
    canvas.drawLine(Offset(cx - 12, cy), Offset(cx + 12, cy), p);
    canvas.drawLine(Offset(cx, cy - 12), Offset(cx, cy + 12), p);
  }
  @override bool shouldRepaint(covariant CustomPainter old) => false;
}