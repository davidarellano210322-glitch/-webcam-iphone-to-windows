// ============================================================================
// NEOCAMO MONITOR - App Principal
// Orquestador de pantallas, permisos, cámara y servicio de telemetría
// ============================================================================
//
// ARQUITECTURA:
//   lib/
//   ├── main.dart              ← este archivo (orquestador)
//   ├── theme.dart             ← paleta, tipografía, constantes
//   ├── services/
//   │   └── telemetry_service.dart  ← MethodChannel + estado
//   ├── widgets/
//   │   ├── neocamo_widgets.dart     ← GlassBadge, RecordButton, etc
//   │   └── custom_painters.dart    ← Grid, Scanlines, Viewfinder
//   └── screens/
//       ├── setup_screen.dart        ← Pantalla 1: Conexión
//       ├── live_monitor_screen.dart ← Pantalla 2: Monitor en vivo
//       ├── tune_panel.dart          ← Pantalla 3: Ajustes de cámara (modal)
//       └── settings_screen.dart     ← Pantalla 4: Ajustes generales
//
// INTEGRACIÓN NATIVA:
//   - WebcamStreamer.swift expone MethodChannel 'com.antigravity.webcam/control'
//   - Métodos existentes: startServer, stopServer, switchCamera, toggleFlash, setLens
//   - Métodos NUEVOS requeridos (ver TODO al final):
//     setZoom, setExposure, setISO, setWhiteBalance, setResolution, startRecording,
//     stopRecording, getTelemetry
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

// ============================================================================
// APP ROOT
// ============================================================================
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
        highlightColor: NC.primary.withOpacity(0.1),
      ),
      home: const NeoCamoMainScreen(),
    );
  }
}

// ============================================================================
// PANTALLA PRINCIPAL - Orquestador con navegación
// ============================================================================
class NeoCamoMainScreen extends StatefulWidget {
  const NeoCamoMainScreen({super.key});

  @override
  State<NeoCamoMainScreen> createState() => _NeoCamoMainScreenState();
}

class _NeoCamoMainScreenState extends State<NeoCamoMainScreen>
    with TickerProviderStateMixin {
  // Navegación: 0 = Setup, 1 = Monitor, 2 = Settings
  int _currentScreenIndex = 0;

  // Servicio de telemetría (singleton)
  final TelemetryService _telemetry = TelemetryService.instance;

  // Cámara Flutter (para vista previa real en el monitor)
  CameraController? _cameraController;
  bool _cameraInitialized = false;
  List<CameraDescription> _cameras = [];

  // Permisos
  bool _cameraPermission = false;
  bool _micPermission = false;
  bool _networkPermission = false;

  // Animaciones
  late AnimationController _recPulseCtrl;

  @override
  void initState() {
    super.initState();

    // Controller para pulso del botón REC
    _recPulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    // Inicia mock de telemetría para desarrollo
    _telemetry.startMock();

    // Solicita permisos al iniciar
    _requestPermissions();
  }

  @override
  void dispose() {
    _recPulseCtrl.dispose();
    _cameraController?.dispose();
    _telemetry.stopMock();
    super.dispose();
  }

  // ─── PERMISOS ────────────────────────────────────────────────────────────
  Future<void> _requestPermissions() async {
    final cameraStatus = await Permission.camera.request();
    final micStatus = await Permission.microphone.request();

    setState(() {
      _cameraPermission = cameraStatus.isGranted;
      _micPermission = micStatus.isGranted;
      // En iOS el permiso de red local se solicita al iniciar el servidor,
      // asumimos true por ahora; se actualizará cuando se conecte.
      _networkPermission = true;
    });

    // Si tenemos permiso de cámara, inicializa CameraController
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
    // Re-solicita permisos si no los tenemos
    if (!_cameraPermission || !_micPermission) {
      _requestPermissions().then((_) {
        setState(() => _currentScreenIndex = 1);
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TunePanel(
        telemetry: _telemetry,
        state: _telemetry.state,
      ),
    );
  }

  // ─── BUILD ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: _buildCurrentScreen(),
      ),
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
          onBack: _goToSetup,
          onOpenTune: () => _openTunePanel(context),
          onOpenSettings: _goToSettings,
          recPulseAnimation: _recPulseCtrl,
        );
      case 2:
        return SettingsScreen(
          key: const ValueKey('SettingsScreen'),
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

// ============================================================================
// TODO: MÉTODOS SWIFT REQUERIDOS PARA COMPLETAR LA INTEGRACIÓN
// ============================================================================
//
// Para que la telemetría y los controles avanzados funcionen completamente,
// agrega estos métodos al método `handle(_ call: FlutterMethodCall)` en:
//
//   mobile_app/ios/Runner/AppDelegate.swift
//
// (o donde tengas registrado el MethodChannel 'com.antigravity.webcam/control')
//
// Casos a agregar:
//
// case "setZoom":
//     let zoom = call.arguments["zoom"] as! Double
//     WebcamStreamer.shared.setZoom(zoom)
//     result(nil)
//
// case "setExposure":
//     let value = call.arguments["value"] as! Double
//     WebcamStreamer.shared.setExposure(value)
//     result(nil)
//
// case "setISO":
//     let iso = call.arguments["iso"] as! Double
//     WebcamStreamer.shared.setISO(iso)
//     result(nil)
//
// case "setWhiteBalance":
//     let kelvin = call.arguments["kelvin"] as! Double
//     WebcamStreamer.shared.setWhiteBalance(kelvin)
//     result(nil)
//
// case "setResolution":
//     let width = call.arguments["width"] as! Int
//     let fps = call.arguments["fps"] as! Int
//     WebcamStreamer.shared.setResolution(width: width, fps: fps)
//     result(nil)
//
// case "startRecording":
//     WebcamStreamer.shared.startRecording()
//     result(nil)
//
// case "stopRecording":
//     WebcamStreamer.shared.stopRecording()
//     result(nil)
//
// case "getTelemetry":
//     let telemetry = WebcamStreamer.shared.getTelemetry()
//     result(telemetry)  // Dict con: battery, thermal, bitrate, latency, fps
//
// Y en WebcamStreamer.swift, implementa las funciones correspondientes:
//
// func setZoom(_ zoom: Double) {
//     guard let device = captureDevice else { return }
//     try? device.lockForConfiguration()
//     device.videoZoomFactor = zoom
//     device.unlockForConfiguration()
// }
//
// func setExposure(_ value: Double) {
//     guard let device = captureDevice else { return }
//     try? device.lockForConfiguration()
//     device.setExposureTargetBias(value, completionHandler: nil)
//     device.unlockForConfiguration()
// }
//
// func setISO(_ iso: Double) {
//     guard let device = captureDevice else { return }
//     try? device.lockForConfiguration()
//     device.setExposureModeCustom(duration: AVCaptureExposureDuration.current,
//                                  iso: iso, completionHandler: nil)
//     device.unlockForConfiguration()
// }
//
// func setWhiteBalance(_ kelvin: Double) {
//     // Convierte Kelvin a RGB gains y aplica
//     // (requiere implementación manual de la conversión K→RGB)
// }
//
// ============================================================================
