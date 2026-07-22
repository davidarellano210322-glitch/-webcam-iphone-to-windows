// ============================================================================
// PANTALLA 4: AJUSTES GENERALES (Settings Screen)
// Configuración de streaming, info de dispositivo, diagnóstico, versión
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback onBack;

  const SettingsScreen({super.key, required this.onBack});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Opciones de configuración (mock, estado local)
  String _selectedCodec = 'H.264';
  double _bitrateTarget = 8.5;
  bool _autoReconnect = true;
  bool _lowLatencyMode = true;
  bool _sendAudio = true;
  bool _sendBattery = true;
  String _deviceName = 'iPhone de David';

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
            // ─── SECCIÓN: TRANSMISIÓN ────────────────────────────────────────
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

            // ─── SECCIÓN: AUDIO Y BATERÍA ────────────────────────────────────
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

            // ─── SECCIÓN: DISPOSITIVO ────────────────────────────────────────
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
              _buildInfoRow('Modelo', 'iPhone 15 Pro', Icons.smartphone),
              _buildDivider(),
              _buildInfoRow('Sistema', 'iOS 17.4.1', Icons.system_update),
            ]),
            const SizedBox(height: 24),

            // ─── SECCIÓN: DIAGNÓSTICO ────────────────────────────────────────
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
                'Ver logs de streaming',
                Icons.description,
                () {
                  HapticFeedback.lightImpact();
                },
              ),
              _buildDivider(),
              _buildActionRow(
                'Reiniciar servicio de cámara',
                Icons.restart_alt,
                () {
                  HapticFeedback.mediumImpact();
                },
              ),
            ]),
            const SizedBox(height: 24),

            // ─── SECCIÓN: ACERCA DE ──────────────────────────────────────────
            _buildSectionTitle('ACERCA DE'),
            const SizedBox(height: 12),
            _buildCard([
              _buildInfoRow('App', 'NeoCamo Monitor', Icons.apps),
              _buildDivider(),
              _buildInfoRow('Versión', '2.5.0 (Build 4)', Icons.tag),
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
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NC.white10),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildDivider() => const Divider(
        color: NC.white10,
        height: 1,
        thickness: 0.5,
        indent: 16,
        endIndent: 16,
      );

  Widget _buildDropdownRow(
    String label,
    String value,
    List<String> options,
    IconData icon,
    ValueChanged<String?> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: NC.onSurfaceVariant, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                color: NC.onSurface,
              ),
            ),
          ),
          DropdownButton<String>(
            value: value,
            underline: const SizedBox(),
            dropdownColor: NC.surfaceContainer,
            style: const TextStyle(
              fontFamily: 'Geist',
              fontSize: 13,
              color: NC.primary,
            ),
            items: options
                .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                .toList(),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildSliderRow(
    String label,
    double value,
    double min,
    double max,
    String suffix,
    IconData icon,
    ValueChanged<double> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: NC.onSurfaceVariant, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    color: NC.onSurface,
                  ),
                ),
              ),
              Text(
                '${value.toStringAsFixed(1)}$suffix',
                style: const TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: NC.primary,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: NC.primary,
              inactiveTrackColor: NC.white10,
              thumbColor: NC.primary,
              overlayColor: NC.primaryGlow,
              trackHeight: 3,
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: 19,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchRow(
    String label,
    bool value,
    IconData icon,
    ValueChanged<bool> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: NC.onSurfaceVariant, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                color: NC.onSurface,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: (v) {
              HapticFeedback.selectionClick();
              onChanged(v);
            },
            activeColor: NC.primary,
            activeTrackColor: NC.primaryGlow,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: NC.onSurfaceVariant, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                color: NC.onSurface,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'Geist',
              fontSize: 13,
              color: NC.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextRow(
    String label,
    String value,
    IconData icon, {
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: NC.onSurfaceVariant, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  color: NC.onSurface,
                ),
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                fontFamily: 'Geist',
                fontSize: 13,
                color: NC.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: NC.onSurfaceVariant, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildActionRow(
    String label,
    IconData icon,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: NC.primary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  color: NC.onSurface,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: NC.onSurfaceVariant, size: 18),
          ],
        ),
      ),
    );
  }

  void _showEditDeviceNameDialog() {
    final controller = TextEditingController(text: _deviceName);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: NC.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: NC.white10),
        ),
        title: const Text(
          'Nombre del dispositivo',
          style: TextStyle(
            fontFamily: 'Hanken Grotesk',
            fontSize: 18,
            color: NC.onSurface,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(
            fontFamily: 'Inter',
            color: NC.onSurface,
          ),
          decoration: InputDecoration(
            hintText: 'Ej. iPhone de David',
            hintStyle: TextStyle(color: NC.onSurfaceVariant),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: NC.white20),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: NC.primary),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar',
                style: TextStyle(color: NC.onSurfaceVariant)),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                if (controller.text.isNotEmpty) {
                  _deviceName = controller.text;
                }
              });
              Navigator.pop(context);
            },
            child: const Text('Guardar',
                style: TextStyle(color: NC.primary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showDiagnosticResult() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: NC.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: NC.white10),
        ),
        title: Row(
          children: const [
            Icon(Icons.check_circle, color: NC.primary),
            SizedBox(width: 8),
            Text(
              'Diagnóstico completado',
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
            Text('✓ Permisos de cámara: OK',
                style: TextStyle(fontSize: 13, color: NC.onSurfaceVariant)),
            SizedBox(height: 6),
            Text('✓ Permisos de micrófono: OK',
                style: TextStyle(fontSize: 13, color: NC.onSurfaceVariant)),
            SizedBox(height: 6),
            Text('✓ Red local: OK',
                style: TextStyle(fontSize: 13, color: NC.onSurfaceVariant)),
            SizedBox(height: 6),
            Text('✓ Servicio de streaming: Activo',
                style: TextStyle(fontSize: 13, color: NC.onSurfaceVariant)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar',
                style: TextStyle(color: NC.primary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
