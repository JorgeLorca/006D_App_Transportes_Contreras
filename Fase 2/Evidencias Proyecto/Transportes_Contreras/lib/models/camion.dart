/// Un camión de la flota de Transportes Contreras.
/// Corresponde a una fila de la tabla `camiones` en Supabase.
///
/// NOTA: `tipo_camion` existe como columna en la tabla pero todavía no se
/// maneja desde este modelo (quedará como select una vez que exista su
/// catálogo de referencia en Supabase). `estado` sí se maneja, con valor
/// por defecto "disponible" al crear un camión nuevo.
class Camion {
  const Camion({
    this.id,
    required this.patente,
    required this.marca,
    required this.modelo,
    required this.anio,
    this.estado = 'disponible',
    this.urlRevisionTecnica,
    this.urlPermisoCirculacion,
    this.urlSeguroSoap,
    this.urlPadron,
    this.creadoEn,
  });

  /// Lo asigna la base de datos al crear la fila.
  final Object? id;

  final String patente;
  final String marca;
  final String modelo;
  final int anio;

  /// Por defecto un camión nuevo queda "disponible".
  final String estado;

  /// Rutas de los documentos en Storage (se envían solo si existen).
  final String? urlRevisionTecnica;
  final String? urlPermisoCirculacion;
  final String? urlSeguroSoap;
  final String? urlPadron;

  /// Lo asigna la base de datos al crear la fila.
  final DateTime? creadoEn;

  /// Datos para INSERT. Es el único lugar donde se mapean los nombres de
  /// columna de la tabla `camiones`. Las rutas de documentos solo se envían
  /// si existen.
  Map<String, dynamic> toMap() => {
        'patente': patente,
        'marca': marca,
        'modelo': modelo,
        'anio': anio,
        'estado': estado,
        if (urlRevisionTecnica != null) 'url_revision_tecnica': urlRevisionTecnica,
        if (urlPermisoCirculacion != null) 'url_permiso_circulacion': urlPermisoCirculacion,
        if (urlSeguroSoap != null) 'url_seguro_soap': urlSeguroSoap,
        if (urlPadron != null) 'url_padron': urlPadron,
      };

  /// Copia del camión con las rutas de los documentos ya subidos a Storage.
  Camion conDocumentos({
    String? urlRevisionTecnica,
    String? urlPermisoCirculacion,
    String? urlSeguroSoap,
    String? urlPadron,
  }) =>
      Camion(
        id: id,
        patente: patente,
        marca: marca,
        modelo: modelo,
        anio: anio,
        estado: estado,
        urlRevisionTecnica: urlRevisionTecnica ?? this.urlRevisionTecnica,
        urlPermisoCirculacion: urlPermisoCirculacion ?? this.urlPermisoCirculacion,
        urlSeguroSoap: urlSeguroSoap ?? this.urlSeguroSoap,
        urlPadron: urlPadron ?? this.urlPadron,
        creadoEn: creadoEn,
      );

  /// Construye un camión a partir de una fila de Supabase (para listados).
  factory Camion.fromMap(Map<String, dynamic> map) => Camion(
        id: map['id'],
        patente: map['patente'] as String,
        marca: map['marca'] as String,
        modelo: map['modelo'] as String,
        anio: map['anio'] as int,
        estado: map['estado'] as String? ?? 'disponible',
        urlRevisionTecnica: map['url_revision_tecnica'] as String?,
        urlPermisoCirculacion: map['url_permiso_circulacion'] as String?,
        urlSeguroSoap: map['url_seguro_soap'] as String?,
        urlPadron: map['url_padron'] as String?,
        creadoEn: map['creado_en'] == null
            ? null
            : DateTime.parse(map['creado_en'] as String),
      );
}