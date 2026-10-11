/// Opción liviana para poblar los selects del formulario de Asignar Viaje
/// (clientes, consignatarios, conductores y camiones).
///
/// Evita cargar el modelo completo de cada entidad: solo trae lo necesario
/// para mostrar el select y, cuando aplica, autocompletar la dirección.
class OpcionViaje {
  const OpcionViaje({
    required this.id,
    required this.nombre,
    this.direccion,
  });

  /// Valor que se guarda en `viajes` (uuid, o el RUT en el caso de
  /// conductores).
  final String id;

  /// Texto que ve el usuario en el select.
  final String nombre;

  /// Solo para clientes y consignatarios: se muestra de solo lectura en el
  /// formulario al elegir la opción (no se guarda en `viajes`).
  final String? direccion;
}