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
      // 0. Descargar el catálogo completo de camiones para que el chofer pueda elegir patente
      await _descargarCatalogoCamiones();

      // 1. Subir y descargar Viajes
      await _subirCambiosPendientesViajes();
      await _descargarViajesDelConductor(rutConductor);

      // 2. Subir y descargar Combustible
      await _subirCombustiblesPendientes();
      await _descargarCombustiblesDelConductor(rutConductor);

      return true;
    } catch (e) {
      debugPrint('Aviso de sincronización (trabajando en modo local): $e');
      return false;
    }
  }

  static Future<void> _descargarCatalogoCamiones() async {
    try {
      final camionesRemotos = await Supabase.instance.client.from('camiones').select();
      for (final c in camionesRemotos) {
        await DatabaseHelper.instance.upsertCamionDesdeSupabase(Map<String, dynamic>.from(c));
      }
    } catch (e) {
      debugPrint('Aviso descargando catálogo de camiones: $e');
    }
  }

  // ================================================================= //
  // SINCRONIZACIÓN DE VIAJES
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
        if (viaje['horas_nocturnas'] != null) updateData['horas_nocturnas'] = viaje['horas_nocturnas'];
        if (viaje['horas_sabado'] != null) updateData['horas_sabado'] = viaje['horas_sabado'];
        if (viaje['monto_tag'] != null) updateData['monto_tag'] = viaje['monto_tag'];
        if (viaje['guia_petroleo'] != null) updateData['guia_petroleo'] = viaje['guia_petroleo'];
        if (viaje['observaciones_conductor'] != null) {
          updateData['observaciones_conductor'] = viaje['observaciones_conductor'];
        }

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

    for (final v in viajesRemotos) {
      await DatabaseHelper.instance.upsertViajeDesdeSupabase(Map<String, dynamic>.from(v));
    }
  }

  // ================================================================= //
  // SINCRONIZACIÓN DE COMBUSTIBLE
  // ================================================================= //
  static Future<void> _subirCombustiblesPendientes() async {
    final pendientes = await DatabaseHelper.instance.obtenerCombustiblesNoSincronizados();

    for (final reg in pendientes) {
      try {
        String? urlVoucher = reg['url_foto_voucher']?.toString();
        String? urlTablero = reg['url_foto_tablero']?.toString();

        final localVoucher = reg['local_path_voucher']?.toString();
        if (localVoucher != null && localVoucher.isNotEmpty && File(localVoucher).existsSync()) {
          urlVoucher = await _intentarSubirFotoStorage(localVoucher, 'voucher_${reg['id']}.jpg') ?? urlVoucher;
        }

        final localTablero = reg['local_path_tablero']?.toString();
        if (localTablero != null && localTablero.isNotEmpty && File(localTablero).existsSync()) {
          urlTablero = await _intentarSubirFotoStorage(localTablero, 'tablero_${reg['id']}.jpg') ?? urlTablero;
        }

        String? camionId = reg['camion_id']?.toString();
        final String patenteElegida = (reg['camion_patente'] ?? '').toString().trim().toUpperCase();

        // Si el chofer escribió otra patente manualmente, buscamos su ID en Supabase o la registramos
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

  static Future<String?> _intentarSubirFotoStorage(String filePath, String fileName) async {
    try {
      final file = File(filePath);
      await Supabase.instance.client.storage
          .from('evidencias_combustible')
          .upload(fileName, file, fileOptions: const FileOptions(upsert: true));

      return Supabase.instance.client.storage
          .from('evidencias_combustible')
          .getPublicUrl(fileName);
    } catch (e) {
      debugPrint('No se pudo subir imagen al bucket evidencias_combustible: $e');
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
}