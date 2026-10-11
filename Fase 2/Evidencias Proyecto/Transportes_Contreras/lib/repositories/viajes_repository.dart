import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/viaje.dart';
import 'repository_exception.dart';

/// Acceso a la tabla `viajes`.
///
/// VERSIÓN SIN AUTH: usa la anon key. Requiere una política RLS temporal que
/// permita INSERT al rol `anon` en `viajes`.
class ViajesRepository {
  ViajesRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const _tabla = 'viajes';

  /// Inserta un viaje recién asignado por el admin.
  Future<void> crear(Viaje viaje) async {
    try {
      await _client.from(_tabla).insert(viaje.toMap());
    } on PostgrestException catch (e) {
      if (e.code == '23503') {
        // foreign_key_violation: algún id/RUT no existe en su tabla.
        throw RepositoryException(
            'Alguno de los datos seleccionados (cliente, consignatario, conductor, camión o región) ya no existe. Recarga el formulario e inténtalo de nuevo.');
      }
      throw traducirErrorPostgrest(e, tabla: _tabla, entidad: 'viaje');
    }
  }
}