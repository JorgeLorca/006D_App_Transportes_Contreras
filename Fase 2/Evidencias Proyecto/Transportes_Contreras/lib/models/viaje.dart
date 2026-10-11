import 'package:flutter/material.dart' show TimeOfDay;

/// Un viaje asignado por el admin. Corresponde a una fila de la tabla
/// `viajes` en Supabase.
///
/// Este modelo cubre solo la ETAPA 1 del flujo (asignación por el admin):
/// cliente (origen), consignatario (destino), conductor, camión, región,
/// fecha, horarios programados, pallets y observaciones del admin.
///
/// Las columnas que llena el conductor al iniciar/terminar el viaje
/// (numero_guia, guia_petroleo, horas_nocturnas, horas_sabado, monto_tag,
/// monto_peoneta, iniciado_en, finalizado_en, lat/lng, observaciones_conductor)
/// no se envían aquí: quedan en null hasta que el conductor las complete.
///
/// La patente y las direcciones no se guardan en `viajes`: se obtienen de
/// `camiones`, `clientes` y `consignatarios` a través de sus ids.
class Viaje {
  const Viaje({
    this.id,
    required this.conductorRut,
    required this.camionId,
    required this.clienteId,
    required this.consignatarioId,
    required this.regionId,
    required this.fechaViaje,
    required this.horaCarga,
    required this.horaDescarga,
    required this.pallets,
    this.observacionesAdmin,
    this.creadoEn,
  });

  /// Lo asigna la base de datos al crear la fila.
  final String? id;

  /// FK a `conductores.rut`.
  final String conductorRut;

  /// FK a `camiones.id`.
  final String camionId;

  /// FK a `clientes.id`. El cliente es también el origen del viaje.
  final String clienteId;

  /// FK a `consignatarios.id`. Es el destino del viaje.
  final String consignatarioId;

  /// FK a `regiones.id`.
  final String regionId;

  final DateTime fechaViaje;
  final TimeOfDay horaCarga;
  final TimeOfDay horaDescarga;
  final int pallets;
  final String? observacionesAdmin;

  /// Lo asigna la base de datos al crear la fila.
  final DateTime? creadoEn;

  static String _fecha(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static String _hora(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  /// Datos para INSERT. Es el único lugar donde se mapean los nombres de
  /// columna de la tabla `viajes`. `id` y `creado_en` los genera la base.
  Map<String, dynamic> toMap() => {
        'conductor_rut': conductorRut,
        'camion_id': camionId,
        'cliente_id': clienteId,
        'consignatario_id': consignatarioId,
        'region_id': regionId,
        'fecha_viaje': _fecha(fechaViaje),
        'hora_carga': _hora(horaCarga),
        'hora_descarga': _hora(horaDescarga),
        'pallets': pallets,
        if (observacionesAdmin != null) 'observaciones_admin': observacionesAdmin,
      };
}