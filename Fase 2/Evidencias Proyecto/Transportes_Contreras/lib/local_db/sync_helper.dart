import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'database_helper.dart';

class SyncHelper {
  static Future<bool> tieneInternet() async {
    try {
      final result = await Connectivity().checkConnectivity();
      if (result.contains(ConnectivityResult.none)) {
        return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> sincronizarTodo(String rutConductor) async {
    final online = await tieneInternet();
    if (!online) return false;

    try {
      // 0. Descargar catálogos base (Camiones, Clientes, Consignatarios, Regiones)
      await _descargarCatalogosBase();

      // 1. Viajes (Sube peonetas, tag, horas, coordenadas y descarga viajes con sus relaciones)
      await _subirCambiosPendientesViajes();
      await _descargarViajesDelConductor(rutConductor);

      // 2. Combustible
      await _subirCombustiblesPendientes();
      await _descargarCombustiblesDelConductor(rutConductor);

      // 3. Asistencia (Actualiza además el estado Activo/Inactivo del conductor)
      await _subirAsistenciasPendientes();
      await _descargarAsistenciasDelConductor(rutConductor);

      // 4. Incidentes en Ruta
      await _subirIncidentesPendientes();
      await _descargarIncidentesDelConductor(rutConductor);

      return true;
    } catch (e) {
      debugPrint('Aviso de sincronización (trabajando en modo local): $e');
      return false;
    }
  }

  static Future<void> _descargarCatalogosBase() async {
    final supabase = Supabase.instance.client;
    try {
      final camionesRemotos = await supabase.from('camiones').select();
      for (final c in camionesRemotos) {
        await DatabaseHelper.instance.upsertCamionDesdeSupabase(Map<String, dynamic>.from(c));
      }
    } catch (e) {
      debugPrint('Aviso descargando catálogo de camiones: $e');
    }

    try {
      final clientesRemotos = await supabase
          .from('clientes')
          .select('id, nombre_empresa, nombre_contacto, telefono, direccion, region_id, comuna_id');
      for (final cli in clientesRemotos) {
        await DatabaseHelper.instance.upsertClienteDesdeSupabase(Map<String, dynamic>.from(cli));
      }
    } catch (e) {
      debugPrint('Aviso descargando catálogo de clientes: $e');
    }

    try {
      final consigRemotos = await supabase
          .from('consignatarios')
          .select('id, nombre_empresa, direccion, region_id, comuna_id');
      for (final con in consigRemotos) {
        await DatabaseHelper.instance.upsertConsignatarioDesdeSupabase(Map<String, dynamic>.from(con));
      }
    } catch (e) {
      debugPrint('Aviso descargando catálogo de consignatarios: $e');
    }

    try {
      final regionesRemotas = await supabase.from('regiones').select('id, nombre');
      for (final r in regionesRemotas) {
        await DatabaseHelper.instance.upsertRegionDesdeSupabase(Map<String, dynamic>.from(r));
      }
    } catch (e) {
      debugPrint('Aviso descargando catálogo de regiones: $e');
    }
  }

  // ================================================================= //
  // 1. SINCRONIZACIÓN DE VIAJES (TODOS LOS CAMPOS DE LA TABLA VIAJES)
  // ================================================================= //
  static Future<void> _subirCambiosPendientesViajes() async {
    final pendientes = await DatabaseHelper.instance.obtenerViajesNoSincronizados();

    for (final viaje in pendientes) {
      try {
        final updateData = <String, dynamic>{
          'estado': viaje['estado'],
          'iniciado_en': viaje['iniciado_en'],
          'finalizado_en': viaje['finalizado_en'],
        };

        if (viaje['numero_guia'] != null) updateData['numero_guia'] = viaje['numero_guia'];
        if (viaje['consignatario_id'] != null && viaje['consignatario_id'].toString().isNotEmpty) {
          updateData['consignatario_id'] = viaje['consignatario_id'];
        }
        if (viaje['pallets'] != null) updateData['pallets'] = viaje['pallets'];
        if (viaje['horas_nocturnas'] != null) updateData['horas_nocturnas'] = viaje['horas_nocturnas'];
        if (viaje['horas_sabado'] != null) updateData['horas_sabado'] = viaje['horas_sabado'];
        if (viaje['monto_tag'] != null) updateData['monto_tag'] = viaje['monto_tag'];
        if (viaje['monto_peonetas'] != null) updateData['monto_peonetas'] = viaje['monto_peonetas'];
        if (viaje['guia_petroleo'] != null) updateData['guia_petroleo'] = viaje['guia_petroleo'];
        if (viaje['observaciones_conductor'] != null) {
          updateData['observaciones_conductor'] = viaje['observaciones_conductor'];
        }
        if (viaje['lat_inicio'] != null) updateData['lat_inicio'] = viaje['lat_inicio'];
        if (viaje['lng_inicio'] != null) updateData['lng_inicio'] = viaje['lng_inicio'];
        if (viaje['lat_fin'] != null) updateData['lat_fin'] = viaje['lat_fin'];
        if (viaje['lng_fin'] != null) updateData['lng_fin'] = viaje['lng_fin'];

        await Supabase.instance.client
            .from('viajes')
            .update(updateData)
            .eq('id', viaje['id']);

        await DatabaseHelper.instance.marcarViajeSincronizado(viaje['id'].toString());
      } catch (e) {
        debugPrint('No se pudo subir el viaje ${viaje['id']}, se reintentará luego: $e');
      }
    }
  }

  static Future<void> _descargarViajesDelConductor(String rut) async {
    const querySelect = '''
      *,
      clientes (*),
      regiones (*),
      consignatarios (*),
      camiones (*)
    ''';

    final viajesRemotos = await Supabase.instance.client
        .from('viajes')
        .select(querySelect)
        .eq('conductor_rut', rut);

    final List<String> idsVigentes = [];
    for (final v in viajesRemotos) {
      final mapa = Map<String, dynamic>.from(v);
      if (mapa['id'] != null) {
        idsVigentes.add(mapa['id'].toString());
      }
      await DatabaseHelper.instance.upsertViajeDesdeSupabase(mapa);
    }

    // Si un viaje fue eliminado en Supabase por el Admin, lo borramos también del teléfono (Planilla / Mis Viajes)
    await DatabaseHelper.instance.eliminarViajesBorradosEnServidor(rut, idsVigentes);
  }

  // ================================================================= //
  // 2. SINCRONIZACIÓN DE COMBUSTIBLE
  // ================================================================= //
  static Future<void> _subirCombustiblesPendientes() async {
    final pendientes = await DatabaseHelper.instance.obtenerCombustiblesNoSincronizados();

    for (final reg in pendientes) {
      try {
        String? urlVoucher = reg['url_foto_voucher']?.toString();
        String? urlTablero = reg['url_foto_tablero']?.toString();

        final localVoucher = reg['local_path_voucher']?.toString();
        if (localVoucher != null && localVoucher.isNotEmpty && File(localVoucher).existsSync()) {
          urlVoucher = await _intentarSubirFotoStorage(
                'evidencias_combustible',
                localVoucher,
                'voucher_${reg['id']}.jpg',
              ) ??
              urlVoucher;
        }

        final localTablero = reg['local_path_tablero']?.toString();
        if (localTablero != null && localTablero.isNotEmpty && File(localTablero).existsSync()) {
          urlTablero = await _intentarSubirFotoStorage(
                'evidencias_combustible',
                localTablero,
                'tablero_${reg['id']}.jpg',
              ) ??
              urlTablero;
        }

        String? camionId = reg['camion_id']?.toString();
        final String patenteElegida = (reg['camion_patente'] ?? '').toString().trim().toUpperCase();

        if ((camionId == null || camionId.trim().isEmpty) && patenteElegida.isNotEmpty) {
          final busqPatente = await Supabase.instance.client
              .from('camiones')
              .select('id, patente')
              .ilike('patente', patenteElegida)
              .limit(1)
              .maybeSingle();

          if (busqPatente != null) {
            camionId = busqPatente['id']?.toString();
          } else {
            try {
              final nuevoCamion = await Supabase.instance.client
                  .from('camiones')
                  .insert({'patente': patenteElegida})
                  .select('id, patente')
                  .single();
              camionId = nuevoCamion['id']?.toString();
              await DatabaseHelper.instance.upsertCamionDesdeSupabase(Map<String, dynamic>.from(nuevoCamion));
            } catch (_) {}
          }
        }

        if (camionId == null || camionId.trim().isEmpty) {
          final camRemoto = await Supabase.instance.client.from('camiones').select('id').limit(1).maybeSingle();
          camionId = camRemoto?['id']?.toString();
        }

        final insertData = <String, dynamic>{
          'id': reg['id'],
          'conductor_rut': reg['conductor_rut'],
          'camion_id': camionId,
          'estacion': 'AIRE',
          'odometro': reg['odometro'],
          'tipo_combustible': reg['tipo_combustible'] ?? 'Diesel',
          'litros': reg['litros'],
          'costo_total': reg['costo_total'],
          'url_foto_voucher': (urlVoucher != null && urlVoucher.isNotEmpty) ? urlVoucher : 'sin_evidencia',
          'url_foto_tablero': (urlTablero != null && urlTablero.isNotEmpty) ? urlTablero : 'sin_evidencia',
          'estado_revision': reg['estado_revision'] ?? 'pendiente',
          'registrado_en': reg['registrado_en'],
        };

        await Supabase.instance.client.from('registros_combustible').upsert(insertData);

        await DatabaseHelper.instance.marcarCombustibleSincronizado(
          reg['id'].toString(),
          urlVoucher: urlVoucher,
          urlTablero: urlTablero,
          camionId: camionId,
        );
      } catch (e) {
        debugPrint('Error subiendo carga de combustible ${reg['id']}: $e');
      }
    }
  }

  static Future<String?> _intentarSubirFotoStorage(String bucket, String filePath, String fileName) async {
    try {
      final file = File(filePath);
      await Supabase.instance.client.storage
          .from(bucket)
          .upload(fileName, file, fileOptions: const FileOptions(upsert: true));

      return Supabase.instance.client.storage.from(bucket).getPublicUrl(fileName);
    } catch (e) {
      debugPrint('No se pudo subir imagen al bucket $bucket: $e');
      return null;
    }
  }

  static Future<void> _descargarCombustiblesDelConductor(String rut) async {
    try {
      final remotos = await Supabase.instance.client
          .from('registros_combustible')
          .select('*, camiones(*)')
          .eq('conductor_rut', rut)
          .order('registrado_en', ascending: false);

      for (final c in remotos) {
        await DatabaseHelper.instance.upsertCombustibleDesdeSupabase(Map<String, dynamic>.from(c));
      }
    } catch (e) {
      debugPrint('Aviso al descargar historial de combustible: $e');
    }
  }

  // ================================================================= //
  // 3. SINCRONIZACIÓN DE ASISTENCIA
  // ================================================================= //
  static Future<void> _subirAsistenciasPendientes() async {
    final pendientes = await DatabaseHelper.instance.obtenerAsistenciasNoSincronizadas();

    for (final reg in pendientes) {
      try {
        final insertData = <String, dynamic>{
          'id': reg['id'],
          'conductor_rut': reg['conductor_rut'],
          'tipo_evento': reg['tipo_evento'],
          'latitud': reg['latitud'],
          'longitud': reg['longitud'],
          'hora_evento': reg['hora_evento'],
        };

        await Supabase.instance.client.from('asistencia').upsert(insertData);
        await DatabaseHelper.instance.marcarAsistenciaSincronizada(reg['id'].toString());
      } catch (e) {
        debugPrint('Error subiendo asistencia ${reg['id']}: $e');
      }
    }
  }

  static Future<void> _descargarAsistenciasDelConductor(String rut) async {
    try {
      final remotos = await Supabase.instance.client
          .from('asistencia')
          .select()
          .eq('conductor_rut', rut)
          .order('hora_evento', ascending: false);

      for (final a in remotos) {
        await DatabaseHelper.instance.upsertAsistenciaDesdeSupabase(Map<String, dynamic>.from(a));
      }
    } catch (e) {
      debugPrint('Aviso al descargar historial de asistencia: $e');
    }
  }

  // ================================================================= //
  // 4. SINCRONIZACIÓN DE INCIDENTES EN RUTA
  // ================================================================= //
  static Future<void> _subirIncidentesPendientes() async {
    final pendientes = await DatabaseHelper.instance.obtenerIncidentesNoSincronizados();

    for (final inc in pendientes) {
      try {
        String? urlFoto = inc['url_evidencia_fotografica']?.toString();
        final localFoto = inc['local_path_evidencia']?.toString();
        if (localFoto != null && localFoto.isNotEmpty && File(localFoto).existsSync()) {
          urlFoto = await _intentarSubirFotoStorage(
                'evidencias_incidentes',
                localFoto,
                'incidente_${inc['id']}.jpg',
              ) ??
              urlFoto;
        }

        String? viajeId = inc['viaje_id']?.toString();
        if (viajeId != null && viajeId.trim().isEmpty) {
          viajeId = null;
        }

        if (viajeId == null) {
          final viajeReciente = await Supabase.instance.client
              .from('viajes')
              .select('id')
              .eq('conductor_rut', inc['conductor_rut'])
              .order('fecha_viaje', ascending: false)
              .limit(1)
              .maybeSingle();
          viajeId = viajeReciente?['id']?.toString();
        }

        final insertData = <String, dynamic>{
          'id': inc['id'],
          'conductor_rut': inc['conductor_rut'],
          'tipo_incidente': inc['tipo_incidente'],
          'gravedad': inc['gravedad'],
          'descripcion': inc['descripcion'],
          'latitud': inc['latitud'],
          'longitud': inc['longitud'],
          'url_evidencia_fotografica': urlFoto,
          'reportado_en': inc['reportado_en'],
        };

        if (viajeId != null && viajeId.isNotEmpty) {
          insertData['viaje_id'] = viajeId;
        }

        await Supabase.instance.client.from('incidentes').upsert(insertData);
        await DatabaseHelper.instance.marcarIncidenteSincronizado(inc['id'].toString(), urlFoto: urlFoto);
      } catch (e) {
        debugPrint('Error subiendo incidente ${inc['id']}: $e');
      }
    }
  }

  static Future<void> _descargarIncidentesDelConductor(String rut) async {
    try {
      final remotos = await Supabase.instance.client
          .from('incidentes')
          .select()
          .eq('conductor_rut', rut)
          .order('reportado_en', ascending: false);

      for (final inc in remotos) {
        await DatabaseHelper.instance.upsertIncidenteDesdeSupabase(Map<String, dynamic>.from(inc));
      }
    } catch (e) {
      debugPrint('Aviso al descargar historial de incidentes: $e');
    }
  }
}