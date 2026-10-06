import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/comuna.dart';
import '../models/region.dart';

/// Acceso de solo lectura a las tablas de referencia `regiones` y `comunas`
/// en Supabase. Se usan para poblar los Dropdown de Región/Comuna en los
/// formularios (Consignatario, y a futuro cualquier otro que necesite
/// ubicación).
///
/// VERSIÓN SIN AUTH: usa la anon key. Requiere una política RLS que permita
/// SELECT al rol `anon` en `regiones` y `comunas` (son datos públicos de
/// referencia, no hay problema en exponerlos para lectura).
class UbicacionesRepository {
  UbicacionesRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const _tablaRegiones = 'regiones';
  static const _tablaComunas = 'comunas';

  /// Trae todas las regiones, ordenadas alfabéticamente.
  Future<List<Region>> obtenerRegiones() async {
    final data = await _client.from(_tablaRegiones).select().order('nombre');
    return (data as List)
        .map((fila) => Region.fromMap(fila as Map<String, dynamic>))
        .toList();
  }

  /// Trae las comunas que pertenecen a [regionId], ordenadas
  /// alfabéticamente.
  Future<List<Comuna>> obtenerComunasPorRegion(String regionId) async {
    final data = await _client
        .from(_tablaComunas)
        .select()
        .eq('region_id', regionId)
        .order('nombre');
    return (data as List)
        .map((fila) => Comuna.fromMap(fila as Map<String, dynamic>))
        .toList();
  }
}