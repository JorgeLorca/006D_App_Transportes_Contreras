import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/opcion_viaje.dart';
import '../models/trabajador.dart';
import 'repository_exception.dart';

/// Acceso a la tabla `conductores` (los trabajadores) y a sus documentos
/// en Supabase Storage.
///
/// VERSIÓN SIN AUTH: usa la anon key. Requiere políticas RLS temporales que
/// permitan INSERT/UPDATE al rol `anon` en `conductores` y en
/// `storage.objects`.
class TrabajadoresRepository {
  TrabajadoresRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const _tabla = 'conductores';
  static const _bucketDocumentos = 'documentos_identidad';

  /// Prueba de conexión: si no lanza excepción, la URL y la anon key son
  /// correctas y la tabla existe. (Con RLS activo puede devolver 0 filas.)
  Future<void> probarConexion() async {
    await _client.from(_tabla).select().limit(1);
  }

  /// Conductores para el select de Asignar Viaje. El id es el RUT (PK de
  /// `conductores`), que es lo que se guarda en `viajes.conductor_rut`.
  Future<List<OpcionViaje>> obtenerOpcionesViaje() async {
    final data = await _client
        .from(_tabla)
        .select('rut, nombre_completo')
        .order('nombre_completo');
    return (data as List).map((f) {
      final fila = f as Map<String, dynamic>;
      final rut = fila['rut'] as String;
      return OpcionViaje(
        id: rut,
        nombre: '${fila['nombre_completo']} ($rut)',
      );
    }).toList();
  }

  /// Sube los documentos (si hay) y luego inserta al trabajador con sus rutas.
  Future<void> crear(
    Trabajador trabajador, {
    XFile? carnet,
    XFile? licencia,
  }) async {
    var aGuardar = trabajador;

    if (carnet != null || licencia != null) {
      final rutaCarnet =
          carnet == null ? null : await _subirDocumento(trabajador.rut, 'cedula', carnet);
      final rutaLicencia =
          licencia == null ? null : await _subirDocumento(trabajador.rut, 'licencia', licencia);
      aGuardar = trabajador.conDocumentos(
        urlCedulaIdentidad: rutaCarnet,
        urlLicenciaConducir: rutaLicencia,
      );
    }

    try {
      await _client.from(_tabla).insert(aGuardar.toMap());
    } on PostgrestException catch (e) {
      throw traducirErrorPostgrest(e, tabla: _tabla, entidad: 'trabajador');
    }
  }

  /// Actualiza un trabajador ya existente (identificado por [Trabajador.rut],
  /// que es la llave primaria de `conductores` y no se puede editar).
  ///
  /// Si se pasa [carnet] y/o [licencia], primero se suben (reemplazando los
  /// documentos anteriores del trabajador) y sus nuevas rutas se incluyen en
  /// el UPDATE. Si no se pasa ninguno, los documentos existentes quedan
  /// intactos (no se tocan esas columnas).
  Future<void> actualizar(
    Trabajador trabajador, {
    XFile? carnet,
    XFile? licencia,
  }) async {
    var aGuardar = trabajador;

    if (carnet != null || licencia != null) {
      final rutaCarnet =
          carnet == null ? null : await _subirDocumento(trabajador.rut, 'cedula', carnet);
      final rutaLicencia =
          licencia == null ? null : await _subirDocumento(trabajador.rut, 'licencia', licencia);
      aGuardar = trabajador.conDocumentos(
        urlCedulaIdentidad: rutaCarnet,
        urlLicenciaConducir: rutaLicencia,
      );
    }

    try {
      await _client.from(_tabla).update(aGuardar.toMap()).eq('rut', trabajador.rut);
    } on PostgrestException catch (e) {
      throw traducirErrorPostgrest(e, tabla: _tabla, entidad: 'trabajador');
    }
  }

  /// Sube un documento al bucket y devuelve su ruta dentro del bucket
  /// (ej: `23483930-4/cedula_1790225540330.jpg`). El nombre lleva la hora para
  /// no pisar nunca un archivo existente.
  Future<String> _subirDocumento(String rut, String tipo, XFile archivo) async {
    final punto = archivo.name.lastIndexOf('.');
    final ext = punto >= 0 ? archivo.name.substring(punto + 1).toLowerCase() : 'jpg';
    final ruta = '$rut/${tipo}_${DateTime.now().millisecondsSinceEpoch}.$ext';

    try {
      final bytes = await archivo.readAsBytes();
      await _client.storage.from(_bucketDocumentos).uploadBinary(
            ruta,
            bytes,
            fileOptions: FileOptions(
              contentType: archivo.mimeType ?? (ext == 'png' ? 'image/png' : 'image/jpeg'),
            ),
          );
      return ruta;
    } on StorageException catch (e) {
      debugPrint('Storage error ${e.statusCode}: ${e.message}');
      if (e.statusCode == '404') {
        throw RepositoryException('El bucket "$_bucketDocumentos" no existe en Supabase Storage.');
      }
      if (e.statusCode == '403' || e.message.contains('row-level security')) {
        throw RepositoryException(
            'Supabase rechazó la subida del documento (RLS). Falta una política de INSERT en storage.objects para el bucket "$_bucketDocumentos".');
      }
      throw RepositoryException('No se pudo subir el documento: ${e.message}');
    }
  }
}