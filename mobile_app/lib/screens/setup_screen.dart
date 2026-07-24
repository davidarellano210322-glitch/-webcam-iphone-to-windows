// ============================================================================
// PANTALLA 1: CONFIGURACIÓN / CONEXIÓN (Setup Screen)
// Visualizer teléfono ↔ laptop, anillos pulsantes, botón de inicio
// La conexión es USB nativo — no requiere IP, WiFi ni server.py.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import '../widgets/custom_painters.dart';
import '../widgets/neocamo_widgets.dart';

class SetupScreen extends StatefulWidget {
  final VoidCallback onConnect;
  final bool cameraPermission;
  final bool micPermission;
  final bool networkPermission;

  const SetupScreen({
    super.key,
    required this.onConnect,
    this.cameraPermission = false,
    this.micPermission = false,
    this.networkPermission = false,
  });

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseRingCtrl;
  late AnimationController _bounceAntennaCtrl;
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    _pulseRingCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _bounceAntennaCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseRingCtrl.dispose();
    _bounceAntennaCtrl.dispose();
    super.dispose();
  }

  void _handleConnect() {
    HapticFeedback.mediumImpact();
    setState(() => _isConnecting = true);

    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() => _isConnecting = false);
        widget.onConnect();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: CustomPaint(painter: GridBackgroundPainter())),
        Positioned.fill(
          child: CustomPaint(painter: ScanlinePainter(opacity: 0.03)),
        ),
        SafeArea(
          child: Column(
            children: [
              _buildTopBar(),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      const SizedBox(height: 20),
                      _buildConnectionVisualizer(),
                      const SizedBox(height: 24),
                      _buildTitle(),
                      const SizedBox(height: 12),
                      _buildInstructions(),
                      const SizedBox(height: 24),
                      _buildConnectionButtons(),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
              _buildFooter(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: NC.bg.withValues(alpha: 0.7),
        border: const Border(bottom: BorderSide(color: NC.white10)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: const [
              Icon(Icons.videocam, color: NC.primary, size: 22),
              SizedBox(width: 8),
              Text(
                'MONITOR PRO-CAM',
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
          const StatusPill(text: '4K 60FPS', color: NC.primary),
        ],
      ),
    );
  }

  Widget _buildConnectionVisualizer() {
    return SizedBox(
      height: 220,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PulseRingsWidget(animation: _pulseRingCtrl),
          Transform.translate(
            offset: const Offset(-45, 0),
            child: Transform.rotate(
              angle: -0.1,
              child: _buildPhoneGraphic(),
            ),
          ),
          Transform.translate(
            offset: const Offset(45, 25),
            child: _buildLaptopGraphic(),
          ),
          AnimatedBuilder(
            animation: _bounceAntennaCtrl,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(0, -8 * _bounceAntennaCtrl.value),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: NC.bg.withValues(alpha: 0.85),
                    shape: BoxShape.circle,
                    border: Border.all(color: NC.primary.withValues(alpha: 0.4)),
                    boxShadow: const [BoxShadow(color: NC.primaryGlow, blurRadius: 20)],
                  ),
                  child: const Icon(Icons.settings_input_antenna,
                      color: NC.primary, size: 36),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneGraphic() {
    return Container(
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
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: NC.surfaceBright,
              borderRadius: BorderRadius.circular(2),
            ),
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
            width: 20,
            height: 20,
            decoration: const BoxDecoration(
              color: NC.surfaceBright,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLaptopGraphic() {
    return Container(
      width: 220,
      height: 140,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: NC.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NC.white10),
        boxShadow: const [
          BoxShadow(color: Colors.black87, blurRadius: 25, offset: Offset(0, 12))
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
                        'NEOCAMO_STUDIO',
                        style: TextStyle(
                          fontFamily: 'Geist',
                          fontSize: 7,
                          color: NC.primaryGlow,
                        ),
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
          Container(
            height: 10,
            width: double.infinity,
            color: NC.surfaceBright.withValues(alpha: 0.5),
          ),
        ],
      ),
    );
  }

  Widget _buildTitle() {
    return Column(
      children: [
        const Text(
          'Listo para Transmitir',
          style: TextStyle(
            fontFamily: 'Hanken Grotesk',
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: NC.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Conecta tu iPhone por USB y presiona Iniciar.\n'
          'La app de escritorio NeoCamo Studio lo detectará automáticamente.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 13,
            color: NC.onSurfaceVariant,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildInstructions() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NC.surfaceContainerLow.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NC.white05),
      ),
      child: Column(
        children: [
          _buildInstructionStep('1', 'Conecta tu iPhone al PC con el cable USB Lightning/USB-C.'),
          const SizedBox(height: 12),
          _buildInstructionStep('2', 'Abre NeoCamo Studio en tu PC. Detectará tu iPhone automáticamente.'),
          const SizedBox(height: 12),
          _buildInstructionStep('3', 'Presiona Iniciar aqui. Luego dale al boton REC en la PC.'),
        ],
      ),
    );
  }

  Widget _buildInstructionStep(String number, String text) {
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: NC.primary.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                fontFamily: 'Geist',
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: NC.primary,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              color: NC.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildConnectionButtons() {
    return Column(
      children: [
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: NC.primary,
            foregroundColor: NC.onPrimary,
            minimumSize: const Size(double.infinity, 58),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: 10,
            shadowColor: NC.primaryGlow,
          ),
          onPressed: _isConnecting ? null : _handleConnect,
          icon: _isConnecting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: NC.onPrimary,
                    strokeWidth: 2,
                  ),
                )
              : const Icon(Icons.usb, size: 22),
          label: Text(
            _isConnecting ? 'Iniciando...' : 'Iniciar Streaming (USB)',
            style: const TextStyle(
              fontFamily: 'Hanken Grotesk',
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () => _showTroubleshootModal(),
          icon: const Icon(Icons.help_outline, color: NC.onSurfaceVariant, size: 18),
          label: const Text(
            'Solucionar problemas',
            style: TextStyle(
              fontFamily: 'Geist',
              fontSize: 12,
              color: NC.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FooterBadge(label: 'CÁMARA', isOk: widget.cameraPermission),
              const SizedBox(width: 8),
              FooterBadge(label: 'MIC', isOk: widget.micPermission),
              const SizedBox(width: 8),
            ],
          ),
          const SizedBox(height: 8),
          const SizedBox(height: 8),
          const Text(
            'BUILD: NC-2026.08-PRO // V2.5.0',
            style: TextStyle(
              fontFamily: 'Geist',
              fontSize: 9,
              color: Colors.white24,
              letterSpacing: 2.0,
            ),
          ),
        ],
      ),
    );
  }

  void _showTroubleshootModal() {
    HapticFeedback.lightImpact();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: NC.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: NC.white10),
        ),
        title: const Row(
          children: [
            Icon(Icons.help_outline, color: NC.primary),
            SizedBox(width: 8),
            Text(
              'Solución de problemas',
              style: TextStyle(
                fontFamily: 'Hanken Grotesk',
                fontSize: 18,
                color: NC.onSurface,
              ),
            ),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '1. Asegúrate de que iTunes (o Apple Mobile Device Support) esté instalado en tu PC. Es necesario para la conexión USB.',
              style: TextStyle(fontSize: 13, color: NC.onSurfaceVariant, height: 1.4),
            ),
            SizedBox(height: 8),
            Text(
              '2. Conecta el iPhone con el cable USB. Si aparece "Confiar en esta computadora", presiona Confiar.',
              style: TextStyle(fontSize: 13, color: NC.onSurfaceVariant, height: 1.4),
            ),
            SizedBox(height: 8),
            Text(
              '3. Abre NeoCamo Studio en tu PC. Debería detectar tu iPhone automáticamente.',
              style: TextStyle(fontSize: 13, color: NC.onSurfaceVariant, height: 1.4),
            ),
            SizedBox(height: 8),
            Text(
              '4. Si no detecta el iPhone, desconecta y reconecta el cable, o reinicia la app de escritorio.',
              style: TextStyle(fontSize: 13, color: NC.onSurfaceVariant, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Entendido',
              style: TextStyle(color: NC.primary, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
