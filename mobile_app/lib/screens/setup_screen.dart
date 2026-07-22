// ============================================================================
// PANTALLA 1: CONFIGURACIÓN / CONEXIÓN (Setup Screen)
// Visualizer teléfono ↔ laptop, anillos pulsantes, botones WiFi / USB
// Campo de IP del servidor Windows + conexión funcional
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import '../widgets/custom_painters.dart';
import '../widgets/neocamo_widgets.dart';

class SetupScreen extends StatefulWidget {
  final void Function(String ip) onConnect;
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
  final TextEditingController _ipController = TextEditingController();
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
    _ipController.dispose();
    super.dispose();
  }

  void _handleConnect() {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Introduce la IP de tu PC'),
          backgroundColor: NC.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _isConnecting = true);

    // Simular delay de conexión para feedback visual
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() => _isConnecting = false);
        widget.onConnect(ip);
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
                      _buildIpInput(),
                      const SizedBox(height: 16),
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
            color: NC.surfaceBright.withOpacity(0.5),
          ),
        ],
      ),
    );
  }

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
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 13,
            color: NC.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

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
          _buildInstructionStep('1', 'Ejecuta server.py en tu PC Windows.'),
          const SizedBox(height: 12),
          _buildInstructionStep('2', 'Introduce la IP que muestra el servidor.'),
          const SizedBox(height: 12),
          _buildInstructionStep('3', 'Presiona Conectar y comienza a transmitir.'),
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

  Widget _buildIpInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'IP DEL SERVIDOR',
          style: TextStyle(
            fontFamily: 'Geist',
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: NC.primary,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _ipController,
          keyboardType: TextInputType.number,
          style: const TextStyle(
            fontFamily: 'Geist',
            fontSize: 16,
            color: NC.onSurface,
          ),
          decoration: InputDecoration(
            hintText: '192.168.1.100',
            hintStyle: const TextStyle(color: Colors.white24),
            prefixIcon: const Icon(Icons.computer, color: NC.primary, size: 20),
            filled: true,
            fillColor: NC.surfaceContainerLow,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: NC.white10),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: NC.primary, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
            minimumSize: const Size(double.infinity, 56),
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
              : const Icon(Icons.wifi, size: 22),
          label: Text(
            _isConnecting ? 'Conectando...' : 'Conectar por WiFi',
            style: const TextStyle(
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
          onPressed: _isConnecting ? null : _handleConnect,
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
              '1. Asegúrate de que server.py esté ejecutándose en tu PC.',
              style: TextStyle(fontSize: 13, color: NC.onSurfaceVariant),
            ),
            SizedBox(height: 8),
            Text(
              '2. Verifica que tu iPhone y tu PC estén en el mismo WiFi.',
              style: TextStyle(fontSize: 13, color: NC.onSurfaceVariant),
            ),
            SizedBox(height: 8),
            Text(
              '3. Verifica que el puerto 8000 esté abierto en el firewall.',
              style: TextStyle(fontSize: 13, color: NC.onSurfaceVariant),
            ),
            SizedBox(height: 8),
            Text(
              '4. Si usas cable USB, presiona "Confiar en esta computadora".',
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
