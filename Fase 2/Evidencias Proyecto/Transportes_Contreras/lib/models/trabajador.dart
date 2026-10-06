/// Un trabajador (conductor) de Transportes Contreras.
/// Corresponde a una fila de la tabla `conductores` en Supabase.
class Trabajador {
  const Trabajador({
    required this.rut,
    required this.nombreCompleto,
    this.fechaNacimiento,
    required this.correo,
    required this.telefono,
    this.authId,
    this.urlCedulaIdentidad,
    this.urlLicenciaConducir,
    this.creadoEn,
  });

  final String rut;
  final String nombreCompleto;
  final DateTime? fechaNacimiento;

  /// Columna `email` en la base de datos.
  final String correo;
  final String telefono;
  
  /// Usuario de Supabase Auth asociado (se completará cuando agreguemos Auth).
  final String? authId;

  /// Rutas de los documentos en Storage (se completarán cuando subamos archivos).
  final String? urlCedulaIdentidad;
  final String? urlLicenciaConducir;

  /// Lo asigna la base de datos al crear la fila.
  final DateTime? creadoEn;

  /// Datos para INSERT. Es el único lugar donde se mapean los nombres de
  /// columna de la tabla `conductores`. Las rutas de documentos solo se
  /// envían si existen.
  Map<String, dynamic> toMap() => {
        'rut': rut,
        if (authId != null) 'auth_id': authId,
        'nombre_completo': nombreCompleto,
        'fecha_nacimiento': fechaNacimiento?.toIso8601String().split('T').first,
        'email': correo,
        'telefono': telefono,
        if (urlCedulaIdentidad != null) 'url_cedula_identidad': urlCedulaIdentidad,
        if (urlLicenciaConducir != null) 'url_licencia_conducir': urlLicenciaConducir,
      };

  /// Copia del trabajador con las rutas de los documentos ya subidos a Storage.
  Trabajador conDocumentos({String? urlCedulaIdentidad, String? urlLicenciaConducir}) =>
      Trabajador(
        rut: rut,
        authId: authId,
        nombreCompleto: nombreCompleto,
        fechaNacimiento: fechaNacimiento,
        correo: correo,
        telefono: telefono,
        urlCedulaIdentidad: urlCedulaIdentidad ?? this.urlCedulaIdentidad,
        urlLicenciaConducir: urlLicenciaConducir ?? this.urlLicenciaConducir,
        creadoEn: creadoEn,
      );

  /// Construye un trabajador a partir de una fila de Supabase (para listados).
  factory Trabajador.fromMap(Map<String, dynamic> map) => Trabajador(
        rut: map['rut'] as String,
        nombreCompleto: map['nombre_completo'] as String,
        fechaNacimiento: map['fecha_nacimiento'] == null
            ? null
            : DateTime.parse(map['fecha_nacimiento'] as String),
        correo: map['email'] as String,
        telefono: map['telefono'] as String,
        authId: map['auth_id'] as String?,
        urlCedulaIdentidad: map['url_cedula_identidad'] as String?,
        urlLicenciaConducir: map['url_licencia_conducir'] as String?,
        creadoEn: map['creado_en'] == null
            ? null
            : DateTime.parse(map['creado_en'] as String),
      );
}