import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../local_db/database_helper.dart';
import '../local_db/sync_helper.dart';
import 'conductor_home.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _rutController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _verificandoSesion = true;

  @override
  void initState() {
    super.initState();
    _verificarSesionExistente();
  }

  /// Revisa si ya existe una sesión guardada en el dispositivo (Online u Offline)
  Future<void> _verificarSesionExistente() async {
    try {
      final session = Supabase.instance.client.auth.currentSession;
      final sesionLocal = await DatabaseHelper.instance.obtenerSesionConductor();

      if (session != null && sesionLocal != null) {
        // Ya inició sesión antes y tenemos su RUT en SQLite: entra directo incluso sin internet
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const ConductorHome()),
          );
          return;
        }
      } else if (session != null && sesionLocal == null) {
        // Tiene sesión de Supabase pero aún no se guardaba en SQLite
        final conductorData = await Supabase.instance.client
            .from('conductores')
            .select()
            .eq('auth_id', session.user.id)
            .maybeSingle();

        if (conductorData != null) {
          await DatabaseHelper.instance.guardarSesionConductor(
            session.user.id,
            conductorData['rut'].toString(),
            conductorData['nombre_completo'].toString(),
          );
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const ConductorHome()),
            );
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('Verificación offline: $e');
      // Si falló la red pero hay sesión local guardada, permitimos el paso offline
      final sesionLocal = await DatabaseHelper.instance.obtenerSesionConductor();
      if (sesionLocal != null && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const ConductorHome()),
        );
        return;
      }
    } finally {
      if (mounted) {
        setState(() => _verificandoSesion = false);
      }
    }
  }

  Future<void> _iniciarSesion() async {
    setState(() => _isLoading = true);

    try {
      String rutIngresado = _rutController.text.trim();

      final correoReal = await Supabase.instance.client
          .rpc('obtener_correo_por_rut', params: {'rut_ingresado': rutIngresado});

      if (correoReal == null || correoReal.toString().isEmpty) {
        throw Exception('El RUT ingresado no está registrado.');
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
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Bienvenido, ${adminData['nombre_completo']}')),
            );
          }
          return;
        }

        final conductorData = await Supabase.instance.client
            .from('conductores')
            .select()
            .eq('auth_id', user.id)
            .maybeSingle();

        if (conductorData != null) {
          final rut = conductorData['rut'].toString();
          final nombre = conductorData['nombre_completo'].toString();

          // Guardamos la sesión en SQLite para futuros inicios Offline
          await DatabaseHelper.instance.guardarSesionConductor(user.id, rut, nombre);

          // Descargamos todos sus viajes inmediatamente a la base local
          await SyncHelper.sincronizarTodo(rut);

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
            content: Text('Error: RUT no registrado, contraseña incorrecta o sin conexión.'),
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
    if (_verificandoSesion) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator(color: Color(0xFFE67E22))),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
              const Text('RUT de Usuario', style: TextStyle(fontWeight: FontWeight.bold)),
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
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {},
                  child: const Text('¿Olvidaste tu clave?', style: TextStyle(color: Color(0xFFE67E22))),
                ),
              ),
              const SizedBox(height: 16),
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