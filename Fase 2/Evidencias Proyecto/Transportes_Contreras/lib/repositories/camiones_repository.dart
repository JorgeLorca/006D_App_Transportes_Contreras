import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/camion.dart';
import '../models/opcion_viaje.dart';
import 'repository_exception.dart';

/// Acceso a la tabla `camiones` y a sus documentos en Supabase Storage.
///
/// VERSIÓN SIN AUTH: usa la anon key. Requiere políticas RLS temporales que
/// permitan INSERT/UPDATE al rol `anon` en `camiones` y en
/// `storage.objects`.
class CamionesRepository {
  CamionesRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const _tabla = 'camiones';
  static const _bucketDocumentos = 'vehiculos_docs';

  /// Prueba de conexión: si no lanza excepción, la URL y la anon key son
  /// correctas y la tabla existe. (Con RLS activo puede devolver 0 filas.)
  Future<void> probarConexion() async {
    await _client.from(_tabla).select().limit(1);
  }

  /// Camiones para el select de Asignar Viaje (se muestra la patente; el id
  /// es lo que se guarda en `viajes.camion_id`).
  Future<List<OpcionViaje>> obtenerOpcionesViaje() async {
    final data = await _client
        .from(_tabla)
        .select('id, patente')
        .order('patente');
    return (data as List).map((f) {
      final fila = f as Map<String, dynamic>;
      return OpcionViaje(
        id: fila['id'].toString(),
        nombre: fila['patente'] as String,
      );
    }).toList();
  }

  /// Sube los documentos (los que vengan) y luego inserta el camión con sus
  /// rutas.
  Future<void> crear(
    Camion camion, {
    XFile? revisionTecnica,
    XFile? permisoCirculacion,
    XFile? seguroSoap,
    XFile? padron,
  }) async {
    var aGuardar = camion;

    if (revisionTecnica != null || permisoCirculacion != null || seguroSoap != null || padron != null) {
      final urlRevision = revisionTecnica == null
          ? null
          : await _subirDocumento(camion.patente, 'revision_tecnica', revisionTecnica);
      final urlPermiso = permisoCirculacion == null
          ? null
          : await _subirDocumento(camion.patente, 'permiso_circulacion', permisoCirculacion);
      final urlSoap =
          seguroSoap == null ? null : await _subirDocumento(camion.patente, 'seguro_soap', seguroSoap);
      final urlPadron = padron == null ? null : await _subirDocumento(camion.patente, 'padron', padron);

      aGuardar = camion.conDocumentos(
        urlRevisionTecnica: urlRevision,
        urlPermisoCirculacion: urlPermiso,
        urlSeguroSoap: urlSoap,
        urlPadron: urlPadron,
      );
    }

    try {
      await _client.from(_tabla).insert(aGuardar.toMap());
    } on PostgrestException catch (e) {
      throw traducirErrorPostgrest(e, tabla: _tabla, entidad: 'camión');
    }
  }

  /// Actualiza un camión ya existente (identificado por [Camion.patente],
  /// que no se puede editar: también define la carpeta de documentos en
  /// Storage).
  ///
  /// Si se pasa alguno de los documentos, primero se sube (reemplazando el
  /// anterior) y su nueva ruta se incluye en el UPDATE. Los documentos que
  /// no se reemplazan quedan intactos.
  Future<void> actualizar(
    Camion camion, {
    XFile? revisionTecnica,
    XFile? permisoCirculacion,
    XFile? seguroSoap,
    XFile? padron,
  }) async {
    var aGuardar = camion;

    if (revisionTecnica != null || permisoCirculacion != null || seguroSoap != null || padron != null) {
      final urlRevision = revisionTecnica == null
          ? null
          : await _subirDocumento(camion.patente, 'revision_tecnica', revisionTecnica);
      final urlPermiso = permisoCirculacion == null
          ? null
          : await _subirDocumento(camion.patente, 'permiso_circulacion', permisoCirculacion);
      final urlSoap =
          seguroSoap == null ? null : await _subirDocumento(camion.patente, 'seguro_soap', seguroSoap);
      final urlPadron = padron == null ? null : await _subirDocumento(camion.patente, 'padron', padron);

      aGuardar = camion.conDocumentos(
        urlRevisionTecnica: urlRevision,
        urlPermisoCirculacion: urlPermiso,
        urlSeguroSoap: urlSoap,
        urlPadron: urlPadron,
      );
    }

    try {
      await _client.from(_tabla).update(aGuardar.toMap()).eq('patente', camion.patente);
    } on PostgrestException catch (e) {
      throw traducirErrorPostgrest(e, tabla: _tabla, entidad: 'camión');
    }
  }

  /// Sube un documento al bucket y devuelve su ruta dentro del bucket
  /// (ej: `ABCD-12/padron_1790225540330.jpg`). El nombre lleva la hora para
  /// no pisar nunca un archivo existente.
  Future<String> _subirDocumento(String patente, String tipo, XFile archivo) async {
    final punto = archivo.name.lastIndexOf('.');
    final ext = punto >= 0 ? archivo.name.substring(punto + 1).toLowerCase() : 'jpg';
    final ruta = '$patente/${tipo}_${DateTime.now().millisecondsSinceEpoch}.$ext';

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