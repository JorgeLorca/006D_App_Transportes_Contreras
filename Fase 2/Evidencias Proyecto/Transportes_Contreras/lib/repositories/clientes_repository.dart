import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/cliente.dart';
import '../models/opcion_viaje.dart';
import '../widgets/form_section_card.dart' show DropdownOption;
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

  /// Lista liviana (id + nombre) de todos los clientes, ordenada por
  /// nombre, lista para un `LabeledDropdownField`.
  Future<List<DropdownOption>> obtenerOpciones() async {
    final data = await _client.from(_tabla).select('id, nombre_empresa').order('nombre_empresa');
    return (data as List).map((fila) {
      final map = fila as Map<String, dynamic>;
      return DropdownOption(map['id'].toString(), (map['nombre_empresa'] ?? 'Sin nombre').toString());
    }).toList();
  }

  /// Clientes para el select de Asignar Viaje: id, nombre y dirección (la
  /// dirección se autocompleta en el formulario al elegir el cliente).
  Future<List<OpcionViaje>> obtenerOpcionesViaje() async {
    final data = await _client
        .from(_tabla)
        .select('id, nombre_empresa, direccion')
        .order('nombre_empresa');
    return (data as List).map((fila) {
      final map = fila as Map<String, dynamic>;
      return OpcionViaje(
        id: map['id'].toString(),
        nombre: (map['nombre_empresa'] ?? 'Sin nombre').toString(),
        direccion: map['direccion'] as String?,
      );
    }).toList();
  }

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