/// Resumen de un ciclo (del 21 al 20) de un conductor: una fila de la tabla
/// `planillas_mensuales` + los totales calculados desde `viajes` completados.
class PlanillaMensual {
  const PlanillaMensual({
    required this.id,
    required this.conductorRut,
    required this.conductorNombre,
    required this.inicioCiclo,
    required this.finCiclo,
    required this.estado,
    required this.viajesCompletados,
    required this.palletsMovidos,
    this.urlPdf,
  });

  // Valores que acepta planillas_mensuales_estado_check en la base.
  static const estadoEnRevision = 'en_revision';
  static const estadoAprobada = 'aprobado';

  final String id;
  final String conductorRut;

  /// Nombre completo; si no se pudo obtener, queda el RUT.
  final String conductorNombre;
  final DateTime inicioCiclo;
  final DateTime finCiclo;
  final String estado;

  /// Viajes con estado "completado" del conductor dentro del ciclo.
  final int viajesCompletados;
  final int palletsMovidos;
  final String? urlPdf;

  bool get aprobada => estado.trim().toLowerCase() == estadoAprobada;

  PlanillaMensual copyWith({String? estado}) => PlanillaMensual(
        id: id,
        conductorRut: conductorRut,
        conductorNombre: conductorNombre,
        inicioCiclo: inicioCiclo,
        finCiclo: finCiclo,
        estado: estado ?? this.estado,
        viajesCompletados: viajesCompletados,
        palletsMovidos: palletsMovidos,
        urlPdf: urlPdf,
      );
}

/// Un viaje completado que aparece en el detalle de una planilla.
class ViajePlanilla {
  const ViajePlanilla({
    required this.fecha,
    required this.numeroGuia,
    required this.patente,
    required this.region,
    required this.cliente,
    required this.consignatario,
    required this.pallets,
    required this.horasNocturnas,
    required this.horasSabado,
    this.montoTag,
    this.montoPeonetas,
    this.guiaPetroleo,
    this.observacion,
  });

  final DateTime fecha;
  final String numeroGuia;
  final String patente;

  /// Nombre de la región (tabla `regiones`).
  final String region;

  /// `clientes.nombre_empresa`.
  final String cliente;

  /// `consignatarios.nombre_empresa`.
  final String consignatario;
  final int pallets;

  /// Horas de carga o descarga nocturna (`viajes.horas_nocturnas`).
  final double horasNocturnas;

  /// Horas trabajadas en sábado (`viajes.horas_sabado`).
  final double horasSabado;

  /// `viajes.monto_tag`, en pesos.
  final int? montoTag;

  /// `viajes.monto_peonetas`, en pesos.
  final int? montoPeonetas;
  final String? guiaPetroleo;

  /// `viajes.observaciones_conductor`.
  final String? observacion;
}