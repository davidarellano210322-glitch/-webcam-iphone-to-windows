// ============================================================================
// NEOCAMO MONITOR - App Principal
// Orquestador de pantallas, permisos, cámara y servicio de telemetría
//
// ARQUITECTURA ORIGINAL (RESTAURADA):
//   App Flutter → MethodChannel → WebcamStreamer.swift (TCP 6000/6001)
//   → app de escritorio C# detecta iPhone por USB automáticamente
//   → recibe H.264 → FFmpeg → cámara virtual DirectShow
//
//   NO requiere server.py, NI WebSocket, NI IP manual
// ============================================================================

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'theme.dart';
import 'services/telemetry_service.dart';
import 'screens/setup_screen.dart';
import 'screens/live_monitor_screen.dart';
import 'screens/tune_panel.dart';
import 'screens/settings_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: NC.bg,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const NeoCamoApp());
}

class NeoCamoApp extends StatelessWidget {
  const NeoCamoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NeoCamo | Monitor Profesional',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: NC.bg,
        colorScheme: const ColorScheme.dark(
          primary: NC.primary,
          surface: NC.bg,
          error: NC.error,
          onSurface: NC.onSurface,
        ),
        splashColor: NC.primaryGlow,
        highlightColor: NC.primary.withValues(alpha: 0.1),
      ),
      home: const NeoCamoMainScreen(),
    );
  }
}

class NeoCamoMainScreen extends StatefulWidget {
  const NeoCamoMainScreen({super.key});

  @override
  State<NeoCamoMainScreen> createState() => _NeoCamoMainScreenState();
}

class _NeoCamoMainScreenState extends State<NeoCamoMainScreen>
    with TickerProviderStateMixin {
  int _currentScreenIndex = 0;

  final TelemetryService _telemetry = TelemetryService.instance;

  CameraController? _cameraController;
  bool _cameraInitialized = false;
  bool _streamingActive = false; // true mientras el streaming nativo (Swift) está activo
  List<CameraDescription> _cameras = [];

  bool _cameraPermission = false;
  bool _micPermission = false;
  bool _networkPermission = false;

  late AnimationController _recPulseCtrl;

  @override
  void initState() {
    super.initState();

    _recPulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    // Observa el estado de telemetría para pausar/reanudar la cámara local
    // según el streaming. iOS solo permite UNA AVCaptureSession activa a la
    // vez: cuando WebcamStreamer.swift empieza a transmitir debe liberar la
    // cámara; al detenerse, la recupera para el preview.
    _telemetry.onStreamingChanged = _onStreamingChanged;

    _telemetry.startMock();
    _requestPermissions();
  }

  /// Pausa/reanuda la sesión de cámara de Flutter en función del streaming.
  /// Esto evita que dos AVCaptureSession compitan por el hardware de la cámara.
  void _onStreamingChanged(bool isStreaming) {
    _streamingActive = isStreaming;
    if (!mounted) return;
    setState(() {});

    final ctrl = _cameraController;
    if (ctrl == null || !ctrl.value.isInitialized) return;

    if (isStreaming) {
      // El streaming nativo toma la cámara: liberar el preview de Flutter.
      ctrl.pausePreview().catchError((_) {});
    } else {
      // El streaming terminó: recuperar el preview de Flutter.
      ctrl.resumePreview().catchError((_) {});
    }
  }

  @override
  void dispose() {
    _recPulseCtrl.dispose();
    _telemetry.stopMock();
    _cameraController?.dispose();
    super.dispose();
  }

  // ─── PERMISOS ────────────────────────────────────────────────────────────
  Future<void> _requestPermissions() async {
    final cameraStatus = await Permission.camera.request();
    final micStatus = await Permission.microphone.request();

    setState(() {
      _cameraPermission = cameraStatus.isGranted;
      _micPermission = micStatus.isGranted;
      _networkPermission = true;
    });

    if (_cameraPermission) {
      await _initCamera();
    }
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) return;

      _cameraController = CameraController(
        _cameras.first,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.bgra8888,
      );

      await _cameraController!.initialize();

      if (mounted) setState(() => _cameraInitialized = true);
    } catch (e) {
      debugPrint('Error inicializando cámara: $e');
    }
  }

  // ─── NAVEGACIÓN ───────────────────────────────────────────────────────────
  void _goToMonitor() {
    HapticFeedback.mediumImpact();
    if (!_cameraPermission || !_micPermission) {
      _requestPermissions().then((_) {
        if (mounted) setState(() => _currentScreenIndex = 1);
      });
    } else {
      setState(() => _currentScreenIndex = 1);
    }
  }

  void _goToSetup() {
    HapticFeedback.lightImpact();
    setState(() => _currentScreenIndex = 0);
  }

  void _goToSettings() {
    HapticFeedback.lightImpact();
    setState(() => _currentScreenIndex = 2);
  }

  void _openTunePanel(BuildContext context) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => TunePanel(
        telemetry: _telemetry,
        state: _telemetry.state,
      ),
    );
  }

  // ─── BUILD ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _buildCurrentScreen(),
    );
  }

  Widget _buildCurrentScreen() {
    switch (_currentScreenIndex) {
      case 0:
        return SetupScreen(
          key: const ValueKey('SetupScreen'),
          onConnect: _goToMonitor,
          cameraPermission: _cameraPermission,
          micPermission: _micPermission,
          networkPermission: _networkPermission,
        );
      case 1:
        return LiveMonitorScreen(
          key: const ValueKey('LiveMonitorScreen'),
          telemetry: _telemetry,
          cameraController: _cameraInitialized ? _cameraController : null,
          streamingActive: _streamingActive,
          onBack: _goToSetup,
          onOpenTune: () => _openTunePanel(context),
          onOpenSettings: _goToSettings,
          recPulseAnimation: _recPulseCtrl,
        );
      case 2:
        return SettingsScreen(
          key: const ValueKey('SettingsScreen'),
          telemetry: _telemetry,
          onBack: () => setState(() => _currentScreenIndex = 1),
        );
      default:
        return SetupScreen(
          onConnect: _goToMonitor,
          cameraPermission: _cameraPermission,
          micPermission: _micPermission,
          networkPermission: _networkPermission,
        );
    }
  }
}
