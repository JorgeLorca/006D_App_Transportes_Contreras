import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'conductor_home.dart';
import 'package:flutter/services.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _rutController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

 Future<void> _iniciarSesion() async {
    setState(() => _isLoading = true);
    
    try {
      // 1. Capturar el RUT (Asegúrate de que el formato coincida con tu BD)
      String rutIngresado = _rutController.text.trim();

      // 2. Ejecutar la función remota en Supabase para obtener el correo real
      final correoReal = await Supabase.instance.client
          .rpc('obtener_correo_por_rut', params: {'rut_ingresado': rutIngresado});

      // Si la base de datos no devuelve un correo, el RUT no existe
      if (correoReal == null || correoReal.toString().isEmpty) {
        throw Exception('El RUT ingresado no está registrado.');
      }

      // 3. Hacer el login oficial en Supabase con el correo real y la contraseña
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: correoReal.toString(),
        password: _passwordController.text.trim(),
      );

      final user = response.user;
      
      if (user != null) {
        // Verificar si es administrador
        final adminData = await Supabase.instance.client
            .from('administradores')
            .select()
            .eq('auth_id', user.id)
            .maybeSingle();

        if (adminData != null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Bienvenido, ${adminData['nombre_completo']}')),
            );
            // Navigator.pushReplacement(...) al Dashboard Admin
          }
          return;
        }

        // Verificar si es conductor
        final conductorData = await Supabase.instance.client
            .from('conductores')
            .select()
            .eq('auth_id', user.id)
            .maybeSingle();

        if (conductorData != null) {
          if (mounted) {
            Navigator.pushReplacement(
              context, 
              MaterialPageRoute(builder: (context) => const ConductorHome()),
            );
          }
          return;
        }

        throw Exception('Usuario sin perfil en el sistema.');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error: RUT no registrado o contraseña incorrecta.'),
            backgroundColor: Colors.red,
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
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, 
            children: [
              // 1. HEADER (Logo de la empresa)
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 20.0),
                  child: Image.asset(
                    'assets/images/logo_transportes.jpeg',
                    height: 160, 
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(height: 40),

              // 2. TEXTOS DE BIENVENIDA
              const Text(
                'Bienvenido de nuevo',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
              ),
              const SizedBox(height: 8),
              Text(
                'Ingresa a tu cuenta para gestionar tus rutas y\nlogística de transporte.',
                style: TextStyle(fontSize: 14, color: Colors.grey[600], height: 1.4),
              ),
              const SizedBox(height: 32),

              // 3. FORMULARIO EXCLUSIVO DE RUT
              const Text('RUT de Usuario', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(
  controller: _rutController,
  keyboardType: TextInputType.text,
  inputFormatters: [
    LengthLimitingTextInputFormatter(12), // Limita el largo máximo
    RutFormatter(), // Nuestro formateador personalizado
  ],
  decoration: InputDecoration(
    hintText: '12.345.678-9',
    filled: true,
    fillColor: Colors.grey[100],
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide.none,
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
  ),
),
              const SizedBox(height: 20),
              
              const Text('Contraseña', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  hintText: '••••••••',
                  filled: true,
                  fillColor: Colors.grey[100],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                ),
              ),
              
              // Olvidaste tu clave
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {},
                  child: const Text('¿Olvidaste tu clave?', style: TextStyle(color: Color(0xFFE67E22))),
                ),
              ),
              const SizedBox(height: 16),

              // Botón Iniciar Sesión
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _iniciarSesion,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('Iniciar Sesión', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                            SizedBox(width: 8),
                            Icon(Icons.chevron_right, color: Colors.white),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 40),

              // 4. FOOTER 
              Center(
                child: Column(
                  children: [
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.lock_outline, size: 16, color: Colors.green),
                        SizedBox(width: 6),
                        Text('Acceso Seguro', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tu sesión permanecerá activa incluso sin conexión\npara asegurar la continuidad operativa en ruta.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton(onPressed: () {}, child: Text('Términos', style: TextStyle(color: Colors.grey[700], fontSize: 12))),
                        Text('•', style: TextStyle(color: Colors.grey[400])),
                        TextButton(onPressed: () {}, child: Text('Privacidad', style: TextStyle(color: Colors.grey[700], fontSize: 12))),
                        Text('•', style: TextStyle(color: Colors.grey[400])),
                        TextButton(onPressed: () {}, child: Text('Soporte', style: TextStyle(color: Colors.grey[700], fontSize: 12))),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text('TRANSPORTES CONTRERAS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey[400])),
                    const SizedBox(height: 4),
                    Text('Versión 1.0 Desarrollado por TechSYS Solutions', style: TextStyle(fontSize: 10, color: Colors.grey[400])),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _rutController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
class RutFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    
    if (newValue.text.isEmpty) return newValue;

    // 1. Limpiar todo lo que no sea número o la letra K
    String cleanText = newValue.text.replaceAll(RegExp(r'[^0-9kK]'), '').toUpperCase();
    if (cleanText.isEmpty) return newValue.copyWith(text: '');

    // 2. Separar el dígito verificador del resto del RUT
    String formatted = '';
    int length = cleanText.length;

    if (length > 1) {
      String rut = cleanText.substring(0, length - 1);
      String dv = cleanText.substring(length - 1);
      
      // 3. Agregar los puntos cada 3 números
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
      // 4. Unir el cuerpo con el guion y el DV
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