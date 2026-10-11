import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/consignatario.dart';
import '../models/opcion_viaje.dart';
import '../widgets/form_section_card.dart' show DropdownOption;
import 'repository_exception.dart';

/// Acceso a la tabla `consignatarios` en Supabase.
///
/// VERSIÓN SIN AUTH: usa la anon key. Requiere políticas RLS temporales que
/// permitan INSERT/UPDATE al rol `anon` en `consignatarios`.
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

  /// Lista liviana (id + nombre) de todos los consignatarios, ordenada por
  /// nombre, lista para un `LabeledDropdownField`.
  Future<List<DropdownOption>> obtenerOpciones() async {
    final data = await _client.from(_tabla).select('id, nombre_empresa').order('nombre_empresa');
    return (data as List).map((fila) {
      final map = fila as Map<String, dynamic>;
      return DropdownOption(map['id'].toString(), (map['nombre_empresa'] ?? 'Sin nombre').toString());
    }).toList();
  }

  /// Consignatarios para el select de Asignar Viaje: id, nombre y dirección
  /// (la dirección se autocompleta en el formulario al elegir el destino).
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

  /// Inserta el consignatario en la base de datos.
  Future<void> crear(Consignatario consignatario) async {
    try {
      await _client.from(_tabla).insert(consignatario.toMap());
    } on PostgrestException catch (e) {
      throw traducirErrorPostgrest(e, tabla: _tabla, entidad: 'consignatario');
    }
  }

  /// Actualiza un consignatario ya existente (identificado por
  /// [Consignatario.id], que debe venir de la base de datos).
  Future<void> actualizar(Consignatario consignatario) async {
    assert(consignatario.id != null, 'No se puede actualizar un consignatario sin id');
    try {
      await _client.from(_tabla).update(consignatario.toMap()).eq('id', consignatario.id!);
    } on PostgrestException catch (e) {
      throw traducirErrorPostgrest(e, tabla: _tabla, entidad: 'consignatario');
    }
  }
}