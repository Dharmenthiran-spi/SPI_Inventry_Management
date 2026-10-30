import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/inventory_provider.dart';
import 'db_settings_screen.dart';
import 'login_screen.dart';

class AddUserScreen extends StatefulWidget {
  const AddUserScreen({super.key});
  @override
  State<AddUserScreen> createState() => _AddUserScreenState();
}

class _AddUserScreenState extends State<AddUserScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  String? _msg;
  bool _success = false;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _msg = null; _success = false; });
    final ok = await context.read<InventoryProvider>().addUser(
      name: _nameCtrl.text.trim(),
      userName: _userCtrl.text.trim(),
      password: _passCtrl.text.trim(),
    );
    setState(() {
      _loading = false;
      _success = ok;
      _msg = ok ? 'User added successfully!' : context.read<InventoryProvider>().error;
    });
    if (ok) { _nameCtrl.clear(); _userCtrl.clear(); _passCtrl.clear(); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('Add New User', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            tooltip: 'Database Settings',
            icon: const Icon(Icons.settings_outlined, color: Color(0xFF8B949E)),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DbSettingsScreen()),
              );
            },
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: () {
              context.read<AuthProvider>().logout();
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
            },
            icon: const Icon(Icons.logout, color: Color(0xFF8B949E)),
            label: const Text('Logout', style: TextStyle(color: Color(0xFF8B949E))),
          ),
        ],
      ),
      body: Center(
        child: Container(
          width: 420,
          padding: const EdgeInsets.all(32),
          margin: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF30363D)),
          ),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Create Account', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                const Text('Only admin (spi) can create user accounts.',
                    style: TextStyle(color: Color(0xFF8B949E), fontSize: 13)),
                const SizedBox(height: 28),
                _field(_nameCtrl, 'Full Name', Icons.badge_outlined),
                const SizedBox(height: 14),
                _field(_userCtrl, 'Username', Icons.person_outline),
                const SizedBox(height: 14),
                _field(_passCtrl, 'Password', Icons.lock_outline, obscure: true),
                if (_msg != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _success ? const Color(0xFF1A3A2A) : const Color(0xFF3D1A1A),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(children: [
                      Icon(_success ? Icons.check_circle_outline : Icons.error_outline,
                          color: _success ? const Color(0xFF2EA44F) : const Color(0xFFF85149), size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_msg!,
                          style: TextStyle(color: _success ? const Color(0xFF2EA44F) : const Color(0xFFF85149), fontSize: 13))),
                    ]),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity, height: 46,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2EA44F),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: _loading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Add User', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, IconData icon, {bool obscure = false}) {
    return TextFormField(
      controller: ctrl,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF8B949E)),
        prefixIcon: Icon(icon, color: const Color(0xFF8B949E), size: 20),
        filled: true, fillColor: const Color(0xFF0D1117),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF30363D))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF2EA44F))),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFF85149))),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFF85149))),
      ),
      validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
    );
  }
}
