import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'supabase_init.dart';
import 'theme/app_colors.dart';

// Importamos las dos pantallas de inicio de sesión
import 'screens/login_screen.dart'; // El login de los conductores (Móvil)
import 'screens/web/admin_login_screen.dart'; // El login de Christian/Oficina (Web)

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await iniciarSupabase();
  runApp(const TransportesContrerasApp());
}

class TransportesContrerasApp extends StatelessWidget {
  const TransportesContrerasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Transportes Contreras',
      debugShowCheckedModeBanner: false,
      locale: const Locale('es', 'CL'),
      supportedLocales: const [Locale('es', 'CL'), Locale('es')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: AppColors.primary,
        scaffoldBackgroundColor: AppColors.background,
        fontFamily: 'Segoe UI', // Mantenemos la tipografía de escritorio
        // Mantenemos la configuración de la AppBar del conductor para cuando se use en móvil
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0F172A),
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      // EL RUTEO AUTOMÁTICO SE HACE EN CADA PANTALLA, POR LO QUE NO ES NECESARIO DEFINIR RUTAS AQUÍ
      // Si se compila/abre en Navegador (Chrome) -> Muestra el login de Oficina
      // Si se compila/abre en Celular (Android/iOS) -> Muestra el login de Choferes
      home: kIsWeb ? const AdminLoginScreen() : const LoginScreen(),
    );
  }
}