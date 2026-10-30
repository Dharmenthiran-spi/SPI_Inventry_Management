import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'inventory_screen.dart';
import 'add_user_screen.dart';
import 'db_settings_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _errorMsg;

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _errorMsg = null; });

    final auth = context.read<AuthProvider>();
    final err = await auth.login(_userCtrl.text.trim(), _passCtrl.text.trim());

    if (!mounted) return;
    setState(() => _loading = false);

    if (err != null) {
      setState(() => _errorMsg = err);
      return;
    }

    // Default spi user → Add User screen
    if (auth.role == AuthRole.defaultUser) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AddUserScreen()));
    } else {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const InventoryScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: Stack(
        children: [
          Positioned(
            top: 20,
            right: 20,
            child: IconButton(
              tooltip: 'Database Settings',
              icon: const Icon(Icons.settings_outlined, color: Color(0xFF8B949E)),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DbSettingsScreen()),
                );
              },
            ),
          ),
          Center(
            child: SingleChildScrollView(
              child: Container(
            width: 420,
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF30363D)),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 32)],
            ),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo / Icon
                  Container(
                    width: 72, height: 72,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2EA44F), Color(0xFF1A7F37)],
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(Icons.inventory_2_rounded, color: Colors.white, size: 38),
                  ),
                  const SizedBox(height: 24),
                  const Text('Inventry Management', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  const Text('Sign in to continue', style: TextStyle(color: Color(0xFF8B949E), fontSize: 14)),
                  const SizedBox(height: 32),

                  // Username
                  TextFormField(
                    controller: _userCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDec('Username', Icons.person_outline),
                    validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),

                  // Password
                  TextFormField(
                    controller: _passCtrl,
                    obscureText: _obscure,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDec('Password', Icons.lock_outline).copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, color: const Color(0xFF8B949E)),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                    onFieldSubmitted: (_) => _login(),
                  ),

                  if (_errorMsg != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(color: const Color(0xFF3D1A1A), borderRadius: BorderRadius.circular(8)),
                      child: Row(children: [
                        const Icon(Icons.error_outline, color: Color(0xFFF85149), size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_errorMsg!, style: const TextStyle(color: Color(0xFFF85149), fontSize: 13))),
                      ]),
                    ),
                  ],

                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _login,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2EA44F),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        disabledBackgroundColor: const Color(0xFF1A7F37).withOpacity(0.5),
                      ),
                      child: _loading
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                          : const Text('Sign In', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ],
  ),
);
}

  InputDecoration _inputDec(String label, IconData icon) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF8B949E)),
        prefixIcon: Icon(icon, color: const Color(0xFF8B949E), size: 20),
        filled: true,
        fillColor: const Color(0xFF0D1117),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF30363D)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF2EA44F)),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFF85149)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFF85149)),
        ),
      );
}
