import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/cliente.dart';
import 'repository_exception.dart';

/// Acceso a la tabla `clientes`.
///
/// VERSIÓN SIN AUTH: usa la anon key. Requiere políticas RLS temporales que
/// permitan INSERT/UPDATE al rol `anon`.
class ClientesRepository {
  ClientesRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const _tabla = 'clientes';

  Future<void> crear(Cliente cliente) async {
    try {
      await _client.from(_tabla).insert(cliente.toMap());
    } on PostgrestException catch (e) {
      throw traducirErrorPostgrest(e, tabla: _tabla, entidad: 'cliente');
    }
  }

  /// Actualiza un cliente ya existente (identificado por [Cliente.id]).
  Future<void> actualizar(Cliente cliente) async {
    assert(cliente.id != null, 'No se puede actualizar un cliente sin id');
    try {
      await _client.from(_tabla).update(cliente.toMap()).eq('id', cliente.id!);
    } on PostgrestException catch (e) {
      throw traducirErrorPostgrest(e, tabla: _tabla, entidad: 'cliente');
    }
  }
}