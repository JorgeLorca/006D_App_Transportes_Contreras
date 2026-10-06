import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'repositories/trabajadores_repository.dart';

Future<void> iniciarSupabase() async {
  await Supabase.initialize(
    url: 'https://jxvnwpzyiqpdxomwlmbs.supabase.co/',
    // ignore: deprecated_member_use
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imp4dm53cHp5aXFwZHhvbXdsbWJzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTAwOTA3MzQsImV4cCI6MjEwNTY2NjczNH0.I3WhkujKGMIPUWpfD9dOBcOl29ZQgV8182G_YxSjkrw',
  );

  // Prueba temporal de conexión (bórrala después)
  try {
    await TrabajadoresRepository().probarConexion();
    debugPrint('✅ Supabase conectado');
  } catch (e) {
    debugPrint('❌ Error de conexión: $e');
  }
}