import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/db_settings_provider.dart';
import '../providers/inventory_provider.dart';
import '../database/db_helper.dart';
import '../services/serial_scanner_service.dart';

class DbSettingsScreen extends StatefulWidget {
  final bool isEmbedded;
  const DbSettingsScreen({super.key, this.isEmbedded = false});

  @override
  State<DbSettingsScreen> createState() => _DbSettingsScreenState();
}

class _DbSettingsScreenState extends State<DbSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _hostCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _userCtrl;
  late final TextEditingController _passCtrl;
  late final TextEditingController _dbCtrl;

  bool _testingStatus = false;
  String? _testResult;
  bool _testSuccess = false;
  bool _savingStatus = false;
  bool _obscurePassword = true;

  // Serial port settings
  List<String> _availablePorts = [];
  String _selectedPort = '';
  int _selectedBaudrate = 9600;
  static const List<int> _baudrates = [1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200];

  @override
  void initState() {
    super.initState();
    final prov = context.read<DbSettingsProvider>();
    _hostCtrl = TextEditingController(text: prov.host);
    _portCtrl = TextEditingController(text: prov.port.toString());
    _userCtrl = TextEditingController(text: prov.user);
    _passCtrl = TextEditingController(text: prov.password);
    _dbCtrl = TextEditingController(text: prov.dbName);
    _selectedPort = prov.barcodePort;
    _selectedBaudrate = prov.barcodeBaudrate;
    _refreshPorts();
  }

  void _refreshPorts() {
    final ports = SerialScannerService.availablePorts();
    setState(() {
      _availablePorts = ports;
      if (_selectedPort.isNotEmpty && !ports.contains(_selectedPort)) {
        _selectedPort = '';
      }
    });
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _dbCtrl.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _testingStatus = true;
      _testResult = null;
      _testSuccess = false;
    });

    final host = _hostCtrl.text.trim();
    final port = int.tryParse(_portCtrl.text.trim()) ?? 3306;
    final user = _userCtrl.text.trim();
    final pass = _passCtrl.text;
    final db = _dbCtrl.text.trim();

    try {
      final conn = await DBHelper.testConnection(
        host: host,
        port: port,
        user: user,
        password: pass,
        database: db,
      );
      await conn.close();
      setState(() {
        _testSuccess = true;
        _testResult = 'Connection successful!';
      });
    } catch (e) {
      setState(() {
        _testSuccess = false;
        _testResult = 'Failed to connect: $e';
      });
    } finally {
      setState(() {
        _testingStatus = false;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _savingStatus = true);

    final host = _hostCtrl.text.trim();
    final port = int.tryParse(_portCtrl.text.trim()) ?? 3306;
    final user = _userCtrl.text.trim();
    final pass = _passCtrl.text;
    final db = _dbCtrl.text.trim();

    try {
      await context.read<DbSettingsProvider>().saveSettings(
        host: host,
        port: port,
        user: user,
        password: pass,
        dbName: db,
        barcodePort: _selectedPort,
        barcodeBaudrate: _selectedBaudrate,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Settings saved successfully!'),
            backgroundColor: Color(0xFF2EA44F),
          ),
        );
        if (!widget.isEmbedded) {
          Navigator.pop(context);
        } else {
          // In embedded mode, refresh provider settings loaded in memory
          context.read<InventoryProvider>().fetchAll();
          _refreshPorts();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save settings: $e'),
            backgroundColor: const Color(0xFFF85149),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _savingStatus = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget settingsForm = Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // ── Database Config Card ──────────────────────────────────
              _card(
                title: 'MySQL Database',
                icon: Icons.storage_outlined,
                iconColor: const Color(0xFF58A6FF),
                children: [
                  _tf(_hostCtrl, 'Host Address / Server IP', Icons.dns_outlined),
                  const SizedBox(height: 14),
                  _tf(_portCtrl, 'Port Number', Icons.settings_ethernet_outlined, isNumber: true),
                  const SizedBox(height: 14),
                  _tf(_userCtrl, 'Database Username', Icons.account_circle_outlined),
                  const SizedBox(height: 14),
                  _tf(_passCtrl, 'Database Password', Icons.vpn_key_outlined, obscure: true),
                  const SizedBox(height: 14),
                  _tf(_dbCtrl, 'Database Name', Icons.folder_open_outlined),
                  if (_testResult != null) ...[
                    const SizedBox(height: 14),
                    _resultBanner(_testSuccess, _testResult!),
                  ],
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: _testingStatus ? null : _testConnection,
                    icon: _testingStatus
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.flash_on, size: 16),
                    label: const Text('Test Connection'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF58A6FF),
                      side: const BorderSide(color: Color(0xFF30363D)),
                      minimumSize: const Size(double.infinity, 46),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // ── Serial Barcode Scanner Config Card ────────────────────
              _card(
                title: 'Barcode Scanner (Serial Port)',
                icon: Icons.barcode_reader,
                iconColor: const Color(0xFF2EA44F),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _dropdown<String>(
                          label: 'COM Port',
                          icon: Icons.usb_outlined,
                          value: _availablePorts.contains(_selectedPort) ? _selectedPort : null,
                          items: [
                            const DropdownMenuItem(value: '', child: Text('None (disabled)')),
                            ..._availablePorts.map((p) => DropdownMenuItem(value: p, child: Text(p))),
                          ],
                          onChanged: (v) => setState(() => _selectedPort = v ?? ''),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Refresh ports',
                        icon: const Icon(Icons.refresh, color: Color(0xFF8B949E)),
                        onPressed: _refreshPorts,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _dropdown<int>(
                    label: 'Baud Rate',
                    icon: Icons.speed_outlined,
                    value: _baudrates.contains(_selectedBaudrate) ? _selectedBaudrate : 9600,
                    items: _baudrates.map((b) => DropdownMenuItem(value: b, child: Text('$b'))).toList(),
                    onChanged: (v) => setState(() => _selectedBaudrate = v ?? 9600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _selectedPort.isEmpty
                        ? 'Select a COM port to enable serial barcode scanning.'
                        : 'Scanner will listen on $_selectedPort @ $_selectedBaudrate baud.',
                    style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // ── Save Button ───────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _savingStatus ? null : _save,
                  icon: _savingStatus
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.save_outlined, size: 16),
                  label: const Text('Save All Settings'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2EA44F),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (widget.isEmbedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Connection Settings',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
                ),
                IconButton(
                  tooltip: 'Refresh Ports',
                  icon: const Icon(Icons.refresh, color: Color(0xFF8B949E)),
                  onPressed: _refreshPorts,
                ),
              ],
            ),
          ),
          const Divider(color: Color(0xFF30363D), height: 1),
          Expanded(child: settingsForm),
        ],
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('Connection Settings', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: settingsForm,
    );
  }

  Widget _card({
    required String title,
    required IconData icon,
    required Color iconColor,
    required List<Widget> children,
  }) {
    return Container(
      width: 480,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: iconColor, size: 18),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
          ]),
          const SizedBox(height: 4),
          const Divider(color: Color(0xFF30363D)),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _resultBanner(bool success, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: success ? const Color(0xFF1A3A2A) : const Color(0xFF3D1A1A),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        Icon(
          success ? Icons.check_circle_outline : Icons.error_outline,
          color: success ? const Color(0xFF2EA44F) : const Color(0xFFF85149),
          size: 18,
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(
          color: success ? const Color(0xFF2EA44F) : const Color(0xFFF85149),
          fontSize: 13,
        ))),
      ]),
    );
  }

  Widget _tf(TextEditingController ctrl, String label, IconData icon,
      {bool obscure = false, bool isNumber = false}) {
    final isPassword = obscure;
    final obscureVal = isPassword ? _obscurePassword : false;
    return TextFormField(
      controller: ctrl,
      obscureText: obscureVal,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF8B949E), fontSize: 13),
        prefixIcon: Icon(icon, color: const Color(0xFF8B949E), size: 18),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  color: const Color(0xFF8B949E),
                  size: 18,
                ),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              )
            : null,
        filled: true,
        fillColor: const Color(0xFF0D1117),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF30363D))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF30363D))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF2EA44F))),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFF85149))),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
    );
  }

  Widget _dropdown<T>({
    required String label,
    required IconData icon,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF8B949E), fontSize: 13),
        prefixIcon: Icon(icon, color: const Color(0xFF8B949E), size: 18),
        filled: true,
        fillColor: const Color(0xFF0D1117),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF30363D))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF30363D))),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          items: items,
          onChanged: onChanged,
          isExpanded: true,
          dropdownColor: const Color(0xFF161B22),
          style: const TextStyle(color: Colors.white, fontSize: 14),
          iconEnabledColor: const Color(0xFF8B949E),
        ),
      ),
    );
  }
}
