/// Un evento de asistencia (ej: "entrada") marcado por un conductor desde la
/// app móvil. Una fila de la tabla de asistencia de Supabase.
class RegistroAsistencia {
  const RegistroAsistencia({
    required this.id,
    required this.conductorRut,
    required this.conductorNombre,
    required this.tipoEvento,
    required this.horaEvento,
    this.latitud,
    this.longitud,
  });

  final String id;
  final String conductorRut;

  /// Nombre completo sacado de la tabla de conductores. Si no se encuentra,
  /// queda el RUT para que la fila nunca salga vacía.
  final String conductorNombre;

  final String tipoEvento;
  final DateTime horaEvento; // en UTC, como viene de Supabase
  final double? latitud;
  final double? longitud;

  factory RegistroAsistencia.fromMap(Map<String, dynamic> map, {required String nombre}) {
    return RegistroAsistencia(
      id: map['id'] as String,
      conductorRut: map['conductor_rut'] as String,
      conductorNombre: nombre,
      tipoEvento: (map['tipo_evento'] as String?) ?? '',
      horaEvento: DateTime.parse(map['hora_evento'] as String),
      latitud: (map['latitud'] as num?)?.toDouble(),
      longitud: (map['longitud'] as num?)?.toDouble(),
    );
  }
}