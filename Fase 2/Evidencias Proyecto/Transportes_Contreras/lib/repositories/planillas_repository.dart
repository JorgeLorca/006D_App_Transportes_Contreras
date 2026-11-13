import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/planilla_mensual.dart';
import 'repository_exception.dart';

/// Acceso a `planillas_mensuales` y a los viajes completados que la componen.
///
/// Las planillas ya existen en la base (estado por defecto "en_revision");
/// aquí solo se leen, se calculan sus totales desde `viajes` y se aprueban.
class PlanillasRepository {
  PlanillasRepository({SupabaseClient? client}) : _db = client ?? Supabase.instance.client;

  final SupabaseClient _db;

  static const _estadoViajeCompletado = 'completado';

  // AJUSTAR si en tu base se llaman distinto: la tabla de conductores y la
  // columna de nombre de la tabla "clientes".
  static const _tablaConductores = 'conductores';
  static const _colNombreCompleto = 'nombre_completo';
  static const _colNombreCliente = 'nombre_empresa';

  static String _fecha(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Todas las planillas (más reciente primero) con vueltas y pallets
  /// calculados desde los viajes "completado" de cada ciclo.
  Future<List<PlanillaMensual>> obtenerTodas() async {
    try {
      final filas = await _db
          .from('planillas_mensuales')
          .select('id, conductor_rut, inicio_ciclo, fin_ciclo, estado, url_pdf, '
              '$_tablaConductores($_colNombreCompleto)')
          .order('inicio_ciclo', ascending: false);

      if (filas.isEmpty) return [];

      final inicios = filas.map((f) => DateTime.parse(f['inicio_ciclo'] as String));
      final fines = filas.map((f) => DateTime.parse(f['fin_ciclo'] as String));
      final desde = inicios.reduce((a, b) => a.isBefore(b) ? a : b);
      final hasta = fines.reduce((a, b) => a.isAfter(b) ? a : b);

      final viajes = await _db
          .from('viajes')
          .select('conductor_rut, fecha_viaje, pallets')
          .eq('estado', _estadoViajeCompletado)
          .gte('fecha_viaje', _fecha(desde))
          .lte('fecha_viaje', _fecha(hasta));

      return filas.map<PlanillaMensual>((f) {
        final rut = f['conductor_rut'] as String;
        final inicio = DateTime.parse(f['inicio_ciclo'] as String);
        final fin = DateTime.parse(f['fin_ciclo'] as String);

        var cantidad = 0;
        var pallets = 0;
        for (final v in viajes) {
          if (v['conductor_rut'] != rut) continue;
          final fecha = DateTime.parse(v['fecha_viaje'] as String);
          if (fecha.isBefore(inicio) || fecha.isAfter(fin)) continue;
          cantidad++;
          pallets += (v['pallets'] as num?)?.toInt() ?? 0;
        }

        return PlanillaMensual(
          id: f['id'] as String,
          conductorRut: rut,
          conductorNombre: _nombre(f[_tablaConductores], rut),
          inicioCiclo: inicio,
          finCiclo: fin,
          estado: (f['estado'] as String?) ?? PlanillaMensual.estadoEnRevision,
          viajesCompletados: cantidad,
          palletsMovidos: pallets,
          urlPdf: f['url_pdf'] as String?,
        );
      }).toList();
    } on PostgrestException catch (e) {
      throw RepositoryException('No se pudieron cargar las planillas (${e.message}).');
    }
  }

  static String _nombre(dynamic conductor, String rutPorDefecto) {
    if (conductor is Map) {
      final nombre = (conductor[_colNombreCompleto] as String?)?.trim();
      if (nombre != null && nombre.isNotEmpty) return nombre;
    }
    return rutPorDefecto;
  }

  /// Todos los viajes completados del conductor dentro del ciclo de [p].
  Future<List<ViajePlanilla>> obtenerViajes(PlanillaMensual p) async {
    try {
      final filas = await _db
          .from('viajes')
          .select('fecha_viaje, numero_guia, pallets, horas_nocturnas, horas_sabado, guia_petroleo, '
              'camiones(patente), clientes($_colNombreCliente), consignatarios(nombre_empresa)')
          .eq('conductor_rut', p.conductorRut)
          .eq('estado', _estadoViajeCompletado)
          .gte('fecha_viaje', _fecha(p.inicioCiclo))
          .lte('fecha_viaje', _fecha(p.finCiclo))
          .order('fecha_viaje', ascending: true);

      return filas.map<ViajePlanilla>((f) {
        String texto(dynamic tabla, String col) => (tabla is Map ? tabla[col] as String? : null) ?? '—';
        final guiaPetroleo = (f['guia_petroleo'] as String?)?.trim();
        return ViajePlanilla(
          fecha: DateTime.parse(f['fecha_viaje'] as String),
          numeroGuia: (f['numero_guia'] as String?) ?? '—',
          patente: texto(f['camiones'], 'patente'),
          origen: texto(f['clientes'], _colNombreCliente),
          destino: texto(f['consignatarios'], 'nombre_empresa'),
          pallets: (f['pallets'] as num?)?.toInt() ?? 0,
          horasNocturnas: (f['horas_nocturnas'] as num?)?.toDouble() ?? 0,
          horasSabado: (f['horas_sabado'] as num?)?.toDouble() ?? 0,
          guiaPetroleo: (guiaPetroleo == null || guiaPetroleo.isEmpty) ? null : guiaPetroleo,
        );
      }).toList();
    } on PostgrestException catch (e) {
      throw RepositoryException('No se pudieron cargar los viajes de la planilla (${e.message}).');
    }
  }

  /// Marca la planilla como aprobada o rechazada. [nuevoEstado] debe ser
  /// [PlanillaMensual.estadoAprobada] o [PlanillaMensual.estadoRechazada].
  Future<void> cambiarEstado(String planillaId, String nuevoEstado) async {
    try {
      await _db.from('planillas_mensuales').update({'estado': nuevoEstado}).eq('id', planillaId);
    } on PostgrestException catch (e) {
      final accion = nuevoEstado == PlanillaMensual.estadoRechazada ? 'rechazar' : 'aprobar';
      throw RepositoryException('No se pudo $accion la planilla (${e.message}).');
    }
  }
}