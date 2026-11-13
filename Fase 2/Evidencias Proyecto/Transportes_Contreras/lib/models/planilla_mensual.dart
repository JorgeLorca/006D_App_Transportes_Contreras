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
  static const estadoRechazada = 'rechazado';

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
  bool get rechazada => estado.trim().toLowerCase() == estadoRechazada;

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
    required this.origen,
    required this.destino,
    required this.pallets,
    required this.horasNocturnas,
    required this.horasSabado,
    this.guiaPetroleo,
  });

  final DateTime fecha;
  final String numeroGuia;
  final String patente;

  /// Nombre del cliente.
  final String origen;

  /// Nombre del consignatario.
  final String destino;
  final int pallets;
  final double horasNocturnas;
  final double horasSabado;
  final String? guiaPetroleo;

  /// Horas extra = nocturnas + sábado.
  double get horasExtra => horasNocturnas + horasSabado;
}