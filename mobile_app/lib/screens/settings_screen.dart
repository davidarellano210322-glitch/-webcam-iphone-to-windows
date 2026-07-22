// ============================================================================
// PANTALLA 4: AJUSTES GENERALES (Settings Screen)
// Configuración de streaming, IP del servidor, info de dispositivo, diagnóstico
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import '../services/telemetry_service.dart';

class SettingsScreen extends StatefulWidget {
  final TelemetryService telemetry;
  final String serverIp;
  final void Function(String ip) onServerIpChanged;
  final VoidCallback onBack;

  const SettingsScreen({
    super.key,
    required this.telemetry,
    required this.serverIp,
    required this.onServerIpChanged,
    required this.onBack,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _ipController;
  String _selectedCodec = 'H.264';
  double _bitrateTarget = 8.5;
  bool _autoReconnect = true;
  bool _lowLatencyMode = true;
  bool _sendAudio = true;
  bool _sendBattery = true;
  String _deviceName = 'iPhone de David';

  @override
  void initState() {
    super.initState();
    _ipController = TextEditingController(text: widget.serverIp);
  }

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NC.bg,
      appBar: AppBar(
        backgroundColor: NC.bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: NC.onSurfaceVariant),
          onPressed: () {
            HapticFeedback.lightImpact();
            widget.onBack();
          },
        ),
        title: const Text(
          'Ajustes Generales',
          style: TextStyle(
            fontFamily: 'Hanken Grotesk',
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: NC.onSurface,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // ─── SERVIDOR ──────────────────────────────────────────────────
            _buildSectionTitle('SERVIDOR'),
            const SizedBox(height: 12),
            _buildCard([
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'IP del servidor Windows',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        color: NC.onSurfaceVariant,
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
                      ),
                      onSubmitted: (value) {
                        widget.onServerIpChanged(value.trim());
                        HapticFeedback.lightImpact();
                      },
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: NC.primary,
                        foregroundColor: NC.onPrimary,
                        minimumSize: const Size(double.infinity, 40),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                      onPressed: () {
                        widget.onServerIpChanged(_ipController.text.trim());
                        HapticFeedback.lightImpact();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('IP guardada'),
                            backgroundColor: NC.primary,
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                      child: const Text('Guardar IP'),
                    ),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 24),

            // ─── TRANSMISIÓN ──────────────────────────────────────────────
            _buildSectionTitle('TRANSMISIÓN'),
            const SizedBox(height: 12),
            _buildCard([
              _buildDropdownRow(
                'Códec de video',
                _selectedCodec,
                ['H.264', 'H.265 (HEVC)'],
                Icons.movie,
                (v) => setState(() => _selectedCodec = v!),
              ),
              _buildDivider(),
              _buildSliderRow(
                'Bitrate objetivo',
                _bitrateTarget,
                1.0,
                20.0,
                ' Mbps',
                Icons.speed,
                (v) => setState(() => _bitrateTarget = v),
              ),
              _buildDivider(),
              _buildSwitchRow(
                'Modo baja latencia',
                _lowLatencyMode,
                Icons.bolt,
                (v) => setState(() => _lowLatencyMode = v),
              ),
              _buildDivider(),
              _buildSwitchRow(
                'Reconexión automática',
                _autoReconnect,
                Icons.sync,
                (v) => setState(() => _autoReconnect = v),
              ),
            ]),
            const SizedBox(height: 24),

            // ─── AUDIO Y BATERÍA ──────────────────────────────────────────
            _buildSectionTitle('AUDIO Y ENERGÍA'),
            const SizedBox(height: 12),
            _buildCard([
              _buildSwitchRow(
                'Enviar audio del micrófono',
                _sendAudio,
                Icons.mic,
                (v) => setState(() => _sendAudio = v),
              ),
              _buildDivider(),
              _buildSwitchRow(
                'Enviar nivel de batería',
                _sendBattery,
                Icons.battery_charging_full,
                (v) => setState(() => _sendBattery = v),
              ),
            ]),
            const SizedBox(height: 24),

            // ─── DISPOSITIVO ──────────────────────────────────────────────
            _buildSectionTitle('DISPOSITIVO'),
            const SizedBox(height: 12),
            _buildCard([
              _buildTextRow(
                'Nombre del dispositivo',
                _deviceName,
                Icons.phone_iphone,
                onTap: () => _showEditDeviceNameDialog(),
              ),
              _buildDivider(),
              _buildInfoRow('Modelo', 'iPhone', Icons.smartphone),
              _buildDivider(),
              _buildInfoRow('Sistema', 'iOS', Icons.system_update),
            ]),
            const SizedBox(height: 24),

            // ─── DIAGNÓSTICO ──────────────────────────────────────────────
            _buildSectionTitle('DIAGNÓSTICO'),
            const SizedBox(height: 12),
            _buildCard([
              _buildActionRow(
                'Probar conexión',
                Icons.network_check,
                () {
                  HapticFeedback.mediumImpact();
                  _showDiagnosticResult();
                },
              ),
              _buildDivider(),
              _buildActionRow(
                'Reiniciar servicio de cámara',
                Icons.restart_alt,
                () {
                  HapticFeedback.mediumImpact();
                  _showRestartConfirmation();
                },
              ),
            ]),
            const SizedBox(height: 24),

            // ─── ACERCA DE ────────────────────────────────────────────────
            _buildSectionTitle('ACERCA DE'),
            const SizedBox(height: 12),
            _buildCard([
              _buildInfoRow('App', 'NeoCamo Monitor', Icons.apps),
              _buildDivider(),
              _buildInfoRow('Versión', '2.5.0', Icons.tag),
              _buildDivider(),
              _buildInfoRow('Desarrollador', 'Antigravity', Icons.code),
            ]),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ─── UTILIDADES DE CONSTRUCCIÓN ──────────────────────────────────────────
  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontFamily: 'Geist',
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: NC.primary,
          letterSpacing: 2,
        ),
      ),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: NC.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NC.white05),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildDivider() {
    return const Divider(height: 1, color: NC.white10, indent: 16, endIndent: 16);
  }

  Widget _buildDropdownRow(
    String label, String value, List<String> items, IconData icon, ValueChanged<String?> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: NC.primary, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: NC.onSurface))),
          DropdownButton<String>(
            value: value,
            items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontFamily: 'Geist', fontSize: 13, color: NC.primary)))).toList(),
            onChanged: onChanged,
            dropdownColor: NC.surfaceContainerHigh,
            underline: const SizedBox(),
          ),
        ],
      ),
    );
  }

  Widget _buildSliderRow(
    String label, double value, double min, double max, String suffix, IconData icon, ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: NC.primary, size: 20),
            const SizedBox(width: 12),
            Text(label, style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: NC.onSurface)),
            const Spacer(),
            Text('${value.toStringAsFixed(1)}$suffix', style: const TextStyle(fontFamily: 'Geist', fontSize: 12, color: NC.primary)),
          ]),
          Slider(value: value, min: min, max: max, divisions: 20, activeColor: NC.primary, inactiveColor: NC.white10, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _buildSwitchRow(String label, bool value, IconData icon, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: NC.primary, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: NC.onSurface))),
          Switch(value: value, activeColor: NC.primary, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(icon, color: NC.primary, size: 20),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: NC.onSurface)),
          const Spacer(),
          Text(value, style: const TextStyle(fontFamily: 'Geist', fontSize: 13, color: NC.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _buildTextRow(String label, String value, IconData icon, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: NC.primary, size: 20),
            const SizedBox(width: 12),
            Text(label, style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: NC.onSurface)),
            const Spacer(),
            Text(value, style: const TextStyle(fontFamily: 'Geist', fontSize: 13, color: NC.primary)),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: NC.onSurfaceVariant, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildActionRow(String label, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: NC.primary, size: 20),
            const SizedBox(width: 12),
            Text(label, style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: NC.onSurface)),
            const Spacer(),
            const Icon(Icons.chevron_right, color: NC.onSurfaceVariant, size: 18),
          ],
        ),
      ),
    );
  }

  void _showEditDeviceNameDialog() {
    final ctrl = TextEditingController(text: _deviceName);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: NC.surfaceContainer,
        title: const Text('Nombre del dispositivo', style: TextStyle(color: NC.onSurface)),
        content: TextField(
          controller: ctrl,
          style: const TextStyle(color: NC.onSurface),
          decoration: InputDecoration(
            filled: true,
            fillColor: NC.surfaceContainerLow,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar', style: TextStyle(color: NC.onSurfaceVariant))),
          TextButton(
            onPressed: () {
              setState(() => _deviceName = ctrl.text.isEmpty ? 'iPhone' : ctrl.text);
              Navigator.pop(context);
            },
            child: const Text('Guardar', style: TextStyle(color: NC.primary)),
          ),
        ],
      ),
    );
  }

  void _showDiagnosticResult() {
    final state = widget.telemetry.state;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: NC.surfaceContainer,
        title: const Text('Diagnóstico de conexión', style: TextStyle(color: NC.onSurface)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _diagRow('Estado', state.isStreaming ? 'TRANSMITIENDO' : 'DESCONECTADO'),
            _diagRow('Conexión', state.connectionStatus),
            _diagRow('Latencia', '${state.latencyMs}ms'),
            _diagRow('Bitrate', state.bitrate),
            _diagRow('Resolución', state.resolution),
            _diagRow('FPS', '${state.fps}'),
            _diagRow('Batería', '${state.batteryPercent}%'),
            _diagRow('Temperatura', '${state.thermalTemp.toInt()}°C'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar', style: TextStyle(color: NC.primary))),
        ],
      ),
    );
  }

  Widget _diagRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: NC.onSurfaceVariant)),
          Text(value, style: const TextStyle(fontFamily: 'Geist', fontSize: 13, color: NC.primary)),
        ],
      ),
    );
  }

  void _showRestartConfirmation() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Reiniciando servicio de cámara...'),
        backgroundColor: NC.primary,
        duration: Duration(seconds: 2),
      ),
    );
  }
}
