/// Un consignatario (empresa receptora de la mercancía) de Transportes
/// Contreras. Corresponde a una fila de la tabla `consignatarios` en
/// Supabase.
///
/// Desde el cambio de esquema, la región y la comuna ya no se guardan como
/// texto libre: `consignatarios` solo guarda [regionId] y [comunaId], que
/// apuntan a las tablas `regiones` y `comunas` (ver [Region] y [Comuna]).
class Consignatario {
  const Consignatario({
    this.id,
    required this.nombreEmpresa,
    required this.direccion,
    required this.comunaId,
    required this.regionId,
    this.creadoEn,
  });

  /// Lo asigna la base de datos al crear la fila (uuid). No se envía en el
  /// INSERT.
  final Object? id;

  final String nombreEmpresa;
  final String direccion;

  /// FK a `comunas.id`.
  final String comunaId;

  /// FK a `regiones.id`.
  final String regionId;

  /// Lo asigna la base de datos al crear la fila.
  final DateTime? creadoEn;

  /// Datos para INSERT. Es el único lugar donde se mapean los nombres de
  /// columna de la tabla `consignatarios`.
  Map<String, dynamic> toMap() => {
        'nombre_empresa': nombreEmpresa,
        'direccion': direccion,
        'comuna_id': comunaId,
        'region_id': regionId,
      };

  /// Construye un consignatario a partir de una fila de Supabase (para
  /// listados). Si la consulta trae los datos de `regiones`/`comunas` con un
  /// join embebido (ej: `select('*, regiones(nombre), comunas(nombre)')`),
  /// usa [Consignatario.fromMapConJoin] en su lugar para tener también los
  /// nombres legibles.
  factory Consignatario.fromMap(Map<String, dynamic> map) => Consignatario(
        id: map['id'],
        nombreEmpresa: map['nombre_empresa'] as String,
        direccion: map['direccion'] as String,
        comunaId: map['comuna_id'] as String,
        regionId: map['region_id'] as String,
        creadoEn: map['created_at'] == null
            ? null
            : DateTime.parse(map['created_at'] as String),
      );
}