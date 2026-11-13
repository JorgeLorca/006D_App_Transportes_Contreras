import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/registro_asistencia.dart';

/// Lee los eventos de asistencia de Supabase y les pega el nombre del
/// conductor (la tabla de asistencia solo guarda el RUT).
///
/// ⚠️ Ajusta estas constantes a los nombres reales de tu base.
class AsistenciaRepository {
  static const _tablaAsistencia = 'asistencia';
  static const _tablaConductores = 'conductores';
  static const _colRutConductor = 'rut';

  final SupabaseClient _client = Supabase.instance.client;

  /// Todos los eventos que hay en la tabla (el más reciente primero).
  /// La tabla solo guarda el período vigente de 45 días, así que no se filtra
  /// por fecha. Se trae en bloques porque Supabase corta en 1000 filas.
  Future<List<RegistroAsistencia>> obtenerTodos() async {
    const bloque = 1000;
    final filas = <Map<String, dynamic>>[];
    for (var desde = 0;; desde += bloque) {
      final lote = await _client
          .from(_tablaAsistencia)
          .select()
          .order('hora_evento', ascending: false)
          .range(desde, desde + bloque - 1);
      filas.addAll(lote);
      if (lote.length < bloque) break;
    }

    final ruts = filas.map((f) => f['conductor_rut'] as String).toSet().toList();
    final nombres = <String, String>{};
    if (ruts.isNotEmpty) {
      final conductores = await _client.from(_tablaConductores).select().inFilter(_colRutConductor, ruts);
      for (final c in conductores) {
        nombres[c[_colRutConductor] as String] = _nombreCompleto(c);
      }
    }

    return [
      for (final f in filas)
        RegistroAsistencia.fromMap(
          f,
          nombre: nombres[f['conductor_rut']] ?? f['conductor_rut'] as String,
        ),
    ];
  }

  /// Arma el nombre probando las columnas más comunes. Si tu tabla usa otras,
  /// cambia solo esta función.
  static String _nombreCompleto(Map<String, dynamic> c) {
    String t(String k) => (c[k] as String?)?.trim() ?? '';
    final completo = t('nombre_completo');
    if (completo.isNotEmpty) return completo;

    final nombre = [t('nombres'), t('nombre')].firstWhere((s) => s.isNotEmpty, orElse: () => '');
    final apellido = [t('apellidos'), t('apellido'), '${t('apellido_paterno')} ${t('apellido_materno')}'.trim()]
        .firstWhere((s) => s.isNotEmpty, orElse: () => '');
    final junto = '$nombre $apellido'.trim();
    return junto.isEmpty ? (c[_colRutConductor] as String? ?? 'Sin nombre') : junto;
  }
}