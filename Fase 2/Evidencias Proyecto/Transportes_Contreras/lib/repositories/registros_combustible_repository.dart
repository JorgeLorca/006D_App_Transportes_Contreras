import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/registro_combustible.dart';
import 'repository_exception.dart';

/// Acceso a la tabla `registros_combustible` en Supabase: lectura de los
/// registros y revisión (aprobar / rechazar) por parte de la administración.
///
/// Requiere políticas RLS que permitan SELECT en `registros_combustible`, en
/// `conductores` (nombre del conductor) y en `camiones` (patente), y UPDATE en
/// `registros_combustible` para revisar. OJO: con RLS activo y sin política de
/// lectura Supabase no da error, devuelve la lista vacía; y sin política de
/// UPDATE la actualización tampoco da error, simplemente no modifica ninguna
/// fila (por eso [actualizarRevision] lo comprueba).
class RegistrosCombustibleRepository {
  RegistrosCombustibleRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const _tabla = 'registros_combustible';

  /// Bucket de Storage donde están las fotos del voucher y del tablero.
  static const _bucketEvidencias = 'evidencias_combustible';

  static const estadoPendiente = 'pendiente';
  static const estadoAprobado = 'aprobado';
  static const estadoRechazado = 'rechazado';

  /// Trae los registros, del más reciente al más antiguo, con el nombre del
  /// conductor (join por `conductor_rut`) y la patente del camión (join por
  /// `camion_id`).
  ///
  /// Supabase devuelve como máximo 1000 filas por consulta (límite del
  /// proyecto); si algún día se supera, habrá que paginar desde el servidor.
  Future<List<RegistroCombustible>> obtenerTodos() async {
    try {
      final data = await _client
          .from(_tabla)
          .select('*, conductores(nombre_completo), camiones(patente)')
          .order('registrado_en', ascending: false);
      return (data as List)
          .map((fila) => RegistroCombustible.fromMap(fila as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      debugPrint('Supabase error ${e.code}: ${e.message} | ${e.details} | ${e.hint}');
      throw RepositoryException(_mensajeError(e));
    }
  }

  /// Aprueba o rechaza un registro, sea cual sea su estado actual (también
  /// sirve para corregir uno ya aprobado o rechazado).
  ///
  /// [estadoActual] es el estado con el que se cargó el registro: el cambio solo
  /// se aplica si en la base de datos sigue igual, así no se pisa una revisión
  /// que otra persona haya hecho mientras tanto.
  ///
  /// Si se rechaza y hay [observaciones], se guardan en `observaciones_admin`.
  /// Si un registro rechazado se aprueba, esa nota se borra.
  Future<void> actualizarRevision({
    required String id,
    required bool aprobar,
    required String estadoActual,
    String? observaciones,
  }) async {
    final nota = observaciones?.trim();
    final eraRechazado = estadoActual.trim().toLowerCase() == estadoRechazado;
    final cambios = <String, dynamic>{
      'estado_revision': aprobar ? estadoAprobado : estadoRechazado,
      if (!aprobar && nota != null && nota.isNotEmpty) 'observaciones_admin': nota,
      if (aprobar && eraRechazado) 'observaciones_admin': null,
    };

    try {
      final filas = await _client
          .from(_tabla)
          .update(cambios)
          .eq('id', id)
          .eq('estado_revision', estadoActual) // solo si nadie lo cambió mientras tanto
          .select('id');

      if ((filas as List).isEmpty) {
        throw RepositoryException(
          'No se actualizó el registro. Puede que otra persona ya lo haya modificado, '
          'o que falte una política UPDATE (RLS) para "$_tabla".',
        );
      }
    } on PostgrestException catch (e) {
      debugPrint('Supabase error ${e.code}: ${e.message} | ${e.details} | ${e.hint}');
      throw RepositoryException(_mensajeError(e, escritura: true));
    }
  }

  /// URL para mostrar una foto guardada en el bucket `evidencias_combustible`.
  ///
  /// [ruta] es lo que hay en `url_foto_voucher` / `url_foto_tablero`: puede ser
  /// una URL completa (se usa tal cual) o la ruta del archivo dentro del
  /// bucket. Para una ruta se pide una URL firmada (sirve con bucket privado) y,
  /// si eso falla, la URL pública (bucket público). Devuelve `null` si no hay
  /// foto.
  Future<String?> urlEvidencia(String? ruta) async {
    var path = ruta?.trim();
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;

    // Por si la ruta quedó guardada con "/" inicial o con el nombre del bucket.
    if (path.startsWith('/')) path = path.substring(1);
    if (path.startsWith('$_bucketEvidencias/')) {
      path = path.substring(_bucketEvidencias.length + 1);
    }

    final bucket = _client.storage.from(_bucketEvidencias);
    try {
      return await bucket.createSignedUrl(path, 60 * 60); // válida por 1 hora
    } catch (e) {
      debugPrint('No se pudo firmar la URL de "$path": $e');
      return bucket.getPublicUrl(path);
    }
  }

  String _mensajeError(PostgrestException e, {bool escritura = false}) {
    switch (e.code) {
      case '42501':
        return escritura
            ? 'Supabase rechazó la actualización (RLS). Falta una política UPDATE para "$_tabla".'
            : 'Supabase rechazó la lectura (RLS). Falta una política SELECT para "$_tabla".';
      case '23514':
        return 'La base de datos no acepta ese estado de revisión (restricción CHECK en '
            '"estado_revision"): ${e.message}';
      case 'PGRST200':
        return 'No se encontró la relación entre "$_tabla" y "conductores" o "camiones" '
            '(¿faltan las llaves foráneas conductor_rut → conductores.rut y '
            'camion_id → camiones.id?): ${e.message}';
      default:
        return escritura
            ? 'No se pudo guardar la revisión: ${e.message}'
            : 'No se pudieron cargar los registros de combustible: ${e.message}';
    }
  }
}