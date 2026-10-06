/// Una comuna de Chile. Corresponde a una fila de la tabla `comunas` en
/// Supabase. Cada comuna pertenece a una región ([regionId]). Es una tabla
/// de referencia (solo lectura desde la app).
class Comuna {
  const Comuna({
    required this.id,
    required this.nombre,
    required this.regionId,
  });

  final String id;
  final String nombre;
  final String regionId;

  factory Comuna.fromMap(Map<String, dynamic> map) => Comuna(
        id: map['id'] as String,
        nombre: map['nombre'] as String,
        regionId: map['region_id'] as String,
      );

  @override
  String toString() => nombre;
}