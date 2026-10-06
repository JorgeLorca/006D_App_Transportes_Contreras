import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/consignatario.dart';
import 'repository_exception.dart';

/// Acceso a la tabla `consignatarios` en Supabase.
///
/// VERSIÓN SIN AUTH: usa la anon key. Requiere una política RLS temporal que
/// permita INSERT al rol `anon` en `consignatarios`.
class ConsignatariosRepository {
  ConsignatariosRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const _tabla = 'consignatarios';

  /// Prueba de conexión: si no lanza excepción, la URL y la anon key son
  /// correctas y la tabla existe. (Con RLS activo puede devolver 0 filas.)
  Future<void> probarConexion() async {
    await _client.from(_tabla).select().limit(1);
  }

  /// Inserta el consignatario en la base de datos.
  Future<void> crear(Consignatario consignatario) async {
    try {
      await _client.from(_tabla).insert(consignatario.toMap());
    } on PostgrestException catch (e) {
      throw traducirErrorPostgrest(e, tabla: _tabla, entidad: 'consignatario');
    }
  }
}