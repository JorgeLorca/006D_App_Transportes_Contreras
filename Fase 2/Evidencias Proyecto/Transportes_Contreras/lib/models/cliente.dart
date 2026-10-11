/// Un cliente de Transportes Contreras.
/// Corresponde a una fila de la tabla `clientes` en Supabase.
///
/// Cada cliente tiene dos juegos de tarifas, uno por cada tipo de camión que
/// se le puede asignar a un viaje:
/// - Camión simple: [valorViajeCamion] / [tarifaNocturnaCamion] / [valorPeonetaCamion]
/// - Camión rampla: [valorViajeRampla] / [tarifaNocturnaRampla] / [valorPeonetaRampla]
///
/// Al asignar un viaje, según el tipo de camión que se use se cobra uno u
/// otro juego de tarifas.
///
/// La ubicación ([regionId]/[comunaId]) es FK a las tablas de referencia
/// `regiones` y `comunas` (ver `Region` y `Comuna`), igual que en
/// Consignatario.
/// 

class Cliente {
  const Cliente({
    this.id,
    required this.nombreEmpresa,
    required this.nombreContacto,
    required this.telefono,
    required this.direccion,
    required this.comunaId,
    required this.regionId,
    required this.valorViajeCamion,
    required this.tarifaNocturnaCamion,
    required this.valorPeonetaCamion,
    required this.valorViajeRampla,
    required this.tarifaNocturnaRampla,
    required this.valorPeonetaRampla,
    this.creadoEn,
  });

  /// Lo asigna la base de datos al crear la fila.
  final String? id;
  final String nombreEmpresa;
  final String nombreContacto;
  final String telefono;
  final String direccion;

  /// FK a `comunas.id`.
  final String comunaId;

  /// FK a `regiones.id`.
  final String regionId;

  // Tarifas — camión simple. Columnas: valor_viaje_camion,
  // tarifa_nocturna_camion, valor_peoneta_camion.
  final double valorViajeCamion;
  final double tarifaNocturnaCamion;
  final double valorPeonetaCamion;

  // Tarifas — camión rampla. Columnas: valor_viaje_rampla,
  // tarifa_nocturna_rampla, valor_peoneta_rampla.
  final double valorViajeRampla;
  final double tarifaNocturnaRampla;
  final double valorPeonetaRampla;

  /// Lo asigna la base de datos al crear la fila.
  final DateTime? creadoEn;

  /// Datos para INSERT. Es el único lugar donde se mapean los nombres de
  /// columna de la tabla `clientes`. `id` y `creado_en` los genera la base.
  Map<String, dynamic> toMap() => {
        'nombre_empresa': nombreEmpresa,
        'nombre_contacto': nombreContacto,
        'telefono': telefono,
        'direccion': direccion,
        'comuna_id': comunaId,
        'region_id': regionId,
        'valor_viaje_camion': valorViajeCamion,
        'tarifa_nocturna_camion': tarifaNocturnaCamion,
        'valor_peoneta_camion': valorPeonetaCamion,
        'valor_viaje_rampla': valorViajeRampla,
        'tarifa_nocturna_rampla': tarifaNocturnaRampla,
        'valor_peoneta_rampla': valorPeonetaRampla,
      };

  /// Construye un cliente a partir de una fila de Supabase (para listados).
  factory Cliente.fromMap(Map<String, dynamic> map) => Cliente(
        id: map['id']?.toString(),
        nombreEmpresa: map['nombre_empresa'] as String,
        nombreContacto: map['nombre_contacto'] as String,
        telefono: map['telefono'] as String,
        direccion: map['direccion'] as String,
        comunaId: map['comuna_id'] as String,
        regionId: map['region_id'] as String,
        valorViajeCamion: (map['valor_viaje_camion'] as num?)?.toDouble() ?? 0,
        tarifaNocturnaCamion: (map['tarifa_nocturna_camion'] as num?)?.toDouble() ?? 0,
        valorPeonetaCamion: (map['valor_peoneta_camion'] as num?)?.toDouble() ?? 0,
        valorViajeRampla: (map['valor_viaje_rampla'] as num?)?.toDouble() ?? 0,
        tarifaNocturnaRampla: (map['tarifa_nocturna_rampla'] as num?)?.toDouble() ?? 0,
        valorPeonetaRampla: (map['valor_peoneta_rampla'] as num?)?.toDouble() ?? 0,
        creadoEn: map['creado_en'] == null
            ? null
            : DateTime.parse(map['creado_en'] as String),
      );
}