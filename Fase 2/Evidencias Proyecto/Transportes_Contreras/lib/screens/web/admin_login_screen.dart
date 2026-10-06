import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_home_screen.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _rutController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  // Color principal corporativo extraído de tu diseño
  final Color primaryDarkBlue = const Color(0xFF002B5C);

  Future<void> _iniciarSesion() async {
    setState(() => _isLoading = true);
    try {
      String rutIngresado = _rutController.text.trim();

      final correoReal = await Supabase.instance.client
          .rpc('obtener_correo_por_rut', params: {'rut_ingresado': rutIngresado});

      if (correoReal == null || correoReal.toString().isEmpty) {
        throw Exception('RUT no encontrado en la base de datos.');
      }

      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: correoReal.toString(),
        password: _passwordController.text.trim(),
      );

      final user = response.user;
      if (user != null) {
        final adminData = await Supabase.instance.client
            .from('administradores')
            .select()
            .eq('auth_id', user.id)
            .maybeSingle();

        if (adminData != null) {
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const AdminHomeScreen()),
            );
          }
          return;
        }
        throw Exception('Acceso denegado. Tu perfil no es de administrador.');
      }
    } catch (e) {
      debugPrint('Error de login admin: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        // IMAGEN DE FONDO A PANTALLA COMPLETA
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/fondo_admin.jpg'), // Asegúrate que este sea el nombre correcto
            fit: BoxFit.cover,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
              // TARJETA BLANCA FLOTANTE CENTRAL
              constraints: const BoxConstraints(maxWidth: 450),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 30,
                    offset: const Offset(0, 15),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // LOGO SUPERIOR
                  Center(
                    child: Image.asset(
                      'assets/images/logo_transportes.jpeg',
                      height: 80,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // TÍTULOS
                  Text(
                    'Panel de Administración',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: primaryDarkBlue,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Ingresa con tu cuenta de administrador para\ngestionar la plataforma.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // CAMPO: USUARIO (RUT)
                  const Text(
                    'Usuario',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _rutController,
                    keyboardType: TextInputType.text,
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(12),
                      RutFormatter(),
                    ],
                    decoration: InputDecoration(
                      hintText: '12.345.678-9',
                      hintStyle: TextStyle(color: Colors.grey[400]),
                      prefixIcon: const Icon(Icons.person_outline, color: Colors.grey, size: 20),
                      filled: true,
                      fillColor: Colors.grey[50],
                      contentPadding: const EdgeInsets.symmetric(vertical: 16),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: primaryDarkBlue, width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // CAMPO: CONTRASEÑA
                  const Text(
                    'Contraseña',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      hintText: '••••••••',
                      hintStyle: TextStyle(color: Colors.grey[400]),
                      prefixIcon: const Icon(Icons.lock_outline, color: Colors.grey, size: 20),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          color: Colors.grey,
                          size: 20,
                        ),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                      contentPadding: const EdgeInsets.symmetric(vertical: 16),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: primaryDarkBlue, width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // BOTÓN DE INICIO DE SESIÓN
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _iniciarSesion,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryDarkBlue,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: _isLoading
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text('Iniciar Sesión', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                                SizedBox(width: 8),
                                Icon(Icons.chevron_right, size: 18),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // CAJA DE ALERTA: ACCESO RESTRINGIDO
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F7FF),
                      border: Border.all(color: const Color(0xFFD6E8FF)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.verified_user_outlined, color: primaryDarkBlue, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Acceso Restringido',
                                style: TextStyle(fontWeight: FontWeight.bold, color: primaryDarkBlue, fontSize: 12),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Solo personal autorizado puede acceder al panel de administración.',
                                style: TextStyle(fontSize: 11, color: Colors.black54, height: 1.3),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // FOOTER
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () {}, 
                        style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(50, 20)),
                        child: const Text('Términos', style: TextStyle(color: Colors.grey, fontSize: 11))
                      ),
                      const Text('•', style: TextStyle(color: Colors.grey, fontSize: 11)),
                      TextButton(
                        onPressed: () {}, 
                        style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(50, 20)),
                        child: const Text('Privacidad', style: TextStyle(color: Colors.grey, fontSize: 11))
                      ),
                      const Text('•', style: TextStyle(color: Colors.grey, fontSize: 11)),
                      TextButton(
                        onPressed: () {}, 
                        style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(50, 20)),
                        child: const Text('Soporte', style: TextStyle(color: Colors.grey, fontSize: 11))
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.local_shipping_outlined, size: 12, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text('TRANSPORTES CONTRERAS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.grey)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Versión 2.4.0 • Desarrollado por TechSYS Solutions',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 9, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Formateador de RUT reciclado del login del conductor
class RutFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    
    if (newValue.text.isEmpty) return newValue;

    String cleanText = newValue.text.replaceAll(RegExp(r'[^0-9kK]'), '').toUpperCase();
    if (cleanText.isEmpty) return newValue.copyWith(text: '');

    String formatted = '';
    int length = cleanText.length;

    if (length > 1) {
      String rut = cleanText.substring(0, length - 1);
      String dv = cleanText.substring(length - 1);
      
      String rutWithDots = '';
      int dotCount = 0;
      for (int i = rut.length - 1; i >= 0; i--) {
        rutWithDots = rut[i] + rutWithDots;
        dotCount++;
        if (dotCount == 3 && i != 0) {
          rutWithDots = '.$rutWithDots';
          dotCount = 0;
        }
      }
      formatted = '$rutWithDots-$dv';
    } else {
      formatted = cleanText;
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}