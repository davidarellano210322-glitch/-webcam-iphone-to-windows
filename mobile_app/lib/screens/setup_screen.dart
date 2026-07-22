// ============================================================================
// PANTALLA 1: CONFIGURACIÓN / CONEXIÓN (Setup Screen)
// Visualizer teléfono ↔ laptop, anillos pulsantes, botones WiFi / USB
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
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseRingCtrl;
  late AnimationController _bounceAntennaCtrl;

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

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Fondo con grid
        Positioned.fill(child: CustomPaint(painter: GridBackgroundPainter())),
        // Scanlines
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

  // ─── TOP APP BAR ─────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: NC.bg.withOpacity(0.7),
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

  // ─── VISUALIZADOR DE CONEXIÓN ────────────────────────────────────────────
  Widget _buildConnectionVisualizer() {
    return SizedBox(
      height: 260,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Anillos pulsantes
          PulseRingsWidget(animation: _pulseRingCtrl),

          // Teléfono
          Transform.translate(
            offset: const Offset(-45, 0),
            child: Transform.rotate(
              angle: -0.1,
              child: _buildPhoneGraphic(),
            ),
          ),

          // Laptop
          Transform.translate(
            offset: const Offset(45, 25),
            child: _buildLaptopGraphic(),
          ),

          // Antena animada
          AnimatedBuilder(
            animation: _bounceAntennaCtrl,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(0, -8 * _bounceAntennaCtrl.value),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: NC.bg.withOpacity(0.85),
                    shape: BoxShape.circle,
                    border: Border.all(color: NC.primary.withOpacity(0.4)),
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
                        'NEOCAMO_STUDIO_V2.1',
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
            color: NC.surfaceBright.withOpacity(0.5),
          ),
        ],
      ),
    );
  }

  // ─── TÍTULO ──────────────────────────────────────────────────────────────
  Widget _buildTitle() {
    return Column(
      children: [
        const Text(
          'Listo para Conectar',
          style: TextStyle(
            fontFamily: 'Hanken Grotesk',
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: NC.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Conecta tu iPhone a tu PC y empieza a transmitir video profesional.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 13,
            color: NC.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  // ─── INSTRUCCIONES ───────────────────────────────────────────────────────
  Widget _buildInstructions() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NC.surfaceContainerLow.withOpacity(0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NC.white05),
      ),
      child: Column(
        children: [
          _buildInstructionStep(
            '1',
            'Abre NeoCamo Studio en tu computadora.',
          ),
          const SizedBox(height: 12),
          _buildInstructionStep(
            '2',
            'Conecta vía cable USB o usa WiFi para libertad inalámbrica.',
          ),
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
            color: NC.primary.withOpacity(0.2),
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

  // ─── BOTONES DE CONEXIÓN ─────────────────────────────────────────────────
  Widget _buildConnectionButtons() {
    return Column(
      children: [
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: NC.primary,
            foregroundColor: NC.onPrimary,
            minimumSize: const Size(double.infinity, 56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: 10,
            shadowColor: NC.primaryGlow,
          ),
          onPressed: () {
            HapticFeedback.mediumImpact();
            widget.onConnect();
          },
          icon: const Icon(Icons.wifi, size: 22),
          label: const Text(
            'Conectar por WiFi (Auto-Discovery)',
            style: TextStyle(
              fontFamily: 'Hanken Grotesk',
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: NC.onSurface,
            minimumSize: const Size(double.infinity, 54),
            side: const BorderSide(color: NC.white20),
            backgroundColor: NC.surfaceContainer.withOpacity(0.7),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onPressed: () {
            HapticFeedback.mediumImpact();
            widget.onConnect();
          },
          icon: const Icon(Icons.usb, color: NC.primary, size: 22),
          label: const Text(
            'Modo Prioridad USB',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () => _showTroubleshootModal(),
          icon: const Icon(Icons.help_outline, color: NC.onSurfaceVariant, size: 18),
          label: const Text(
            'Solucionar problemas de conexión',
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

  // ─── FOOTER (BADGES DE PERMISOS + VERSIÓN) ──────────────────────────────
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
              FooterBadge(label: 'RED LOCAL', isOk: widget.networkPermission),
            ],
          ),
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
        title: Row(
          children: const [
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
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              '1. Asegúrate de que NeoCamo Studio esté abierto en tu PC.',
              style: TextStyle(fontSize: 13, color: NC.onSurfaceVariant),
            ),
            SizedBox(height: 8),
            Text(
              '2. Si usas cable USB en iPhone, presiona "Confiar en esta computadora".',
              style: TextStyle(fontSize: 13, color: NC.onSurfaceVariant),
            ),
            SizedBox(height: 8),
            Text(
              '3. Verifica que el puerto 8000 esté abierto en el firewall de Windows.',
              style: TextStyle(fontSize: 13, color: NC.onSurfaceVariant),
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
