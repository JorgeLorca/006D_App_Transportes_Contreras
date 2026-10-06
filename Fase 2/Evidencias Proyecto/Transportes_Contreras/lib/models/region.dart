/// Una región de Chile. Corresponde a una fila de la tabla `regiones` en
/// Supabase. Es una tabla de referencia (solo lectura desde la app).
class Region {
  const Region({
    required this.id,
    required this.nombre,
  });

  final String id;
  final String nombre;

  factory Region.fromMap(Map<String, dynamic> map) => Region(
        id: map['id'] as String,
        nombre: map['nombre'] as String,
      );

  @override
  String toString() => nombre;
}