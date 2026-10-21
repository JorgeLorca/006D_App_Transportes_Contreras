import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_init.dart';
import 'theme/app_colors.dart';

// Importamos las pantallas de login y la pantalla principal administrativa
import 'screens/login_screen.dart'; // El login de los conductores (Móvil)
import 'screens/web/admin_login_screen.dart'; // El login de Christian/Oficina (Web)
import 'widgets/admin_shell.dart'; // Contenedor principal con AppSidebar (Web)

import 'screens/web/admin_home_screen.dart';

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
        fontFamily: 'Segoe UI',
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
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      return const LoginScreen();
    }

    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = Supabase.instance.client.auth.currentSession;

        if (session != null) {
          return const AdminHomeScreen(); // <-- Cambiado de AdminShell() a AdminHomeScreen()
        }

        return const AdminLoginScreen();
      },
    );
  }
}