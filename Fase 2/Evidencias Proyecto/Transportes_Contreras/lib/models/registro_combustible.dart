/// Un registro de combustible que carga un conductor desde la app móvil.
/// Corresponde a una fila de la tabla `registros_combustible` en Supabase.
///
/// La web solo los lee y revisa (la creación la hace la app móvil), por eso
/// este modelo no tiene `toMap()`.
class RegistroCombustible {
  const RegistroCombustible({
    required this.id,
    required this.conductorRut,
    this.conductorNombre,
    this.camionId,
    this.camionPatente,
    required this.odometro,
    this.tipoCombustible,
    required this.litros,
    required this.costoTotal,
    this.urlFotoVoucher,
    this.urlFotoTablero,
    required this.registradoEn,
    this.estacion,
    required this.estadoRevision,
    this.observacionesAdmin,
  });

  final String id;

  /// FK a `conductores.rut`.
  final String conductorRut;

  /// `conductores.nombre_completo`, cuando la consulta trae el join
  /// (`select('*, conductores(nombre_completo)')`).
  final String? conductorNombre;

  /// FK a `camiones.id`.
  final String? camionId;

  /// `camiones.patente`, cuando la consulta trae el join
  /// (`select('*, camiones(patente)')`).
  final String? camionPatente;

  final int odometro;
  final String? tipoCombustible;
  final double litros;
  final double costoTotal;

  /// Rutas/URLs de las fotos del voucher y del tablero.
  final String? urlFotoVoucher;
  final String? urlFotoTablero;

  /// Columna `registrado_en` (timestamptz). Viene en UTC: usar `.toLocal()`
  /// para mostrarla en la hora del usuario.
  final DateTime registradoEn;

  final String? estacion;

  /// Columna `estado_revision` (por ejemplo "pendiente").
  final String estadoRevision;

  final String? observacionesAdmin;

  /// Nombre del conductor, o su RUT si no se pudo traer el nombre.
  String get conductorEtiqueta => conductorNombre ?? conductorRut;

  factory RegistroCombustible.fromMap(Map<String, dynamic> map) {
    final conductor = map['conductores'];
    final camion = map['camiones'];
    return RegistroCombustible(
      id: map['id'].toString(),
      conductorRut: (map['conductor_rut'] ?? '').toString(),
      conductorNombre: conductor is Map ? conductor['nombre_completo'] as String? : null,
      camionId: map['camion_id']?.toString(),
      camionPatente: camion is Map ? camion['patente'] as String? : null,
      odometro: (map['odometro'] as num?)?.toInt() ?? 0,
      tipoCombustible: map['tipo_combustible'] as String?,
      litros: (map['litros'] as num?)?.toDouble() ?? 0,
      costoTotal: (map['costo_total'] as num?)?.toDouble() ?? 0,
      urlFotoVoucher: map['url_foto_voucher'] as String?,
      urlFotoTablero: map['url_foto_tablero'] as String?,
      registradoEn: DateTime.parse(map['registrado_en'] as String),
      estacion: map['estacion'] as String?,
      estadoRevision: (map['estado_revision'] ?? 'pendiente').toString(),
      observacionesAdmin: map['observaciones_admin'] as String?,
    );
  }
}