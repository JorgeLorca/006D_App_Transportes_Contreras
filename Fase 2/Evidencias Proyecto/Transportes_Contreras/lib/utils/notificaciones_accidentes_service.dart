import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificacionesAccidentesService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  static RealtimeChannel? _channel;
  static bool _inicializado = false;

  static Future<void> inicializarYEscuchar({
    required String rutConductorActual,
    BuildContext? context,
  }) async {
    if (kIsWeb) return;

    if (!_inicializado) {
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidSettings);
      
      // Corrección para flutter_local_notifications v18/v19+
      await _notificationsPlugin.initialize(
        initSettings,
      );

      final androidImpl = _notificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.requestNotificationsPermission();

      _inicializado = true;
    }

    // Evitamos duplicar suscripciones
    if (_channel != null) {
      await Supabase.instance.client.removeChannel(_channel!);
    }

    _channel = Supabase.instance.client
        .channel('canal_accidentes_ruta')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'incidentes',
          callback: (payload) {
            final nuevo = payload.newRecord;
            final tipo = (nuevo['tipo_incidente'] ?? '').toString().toLowerCase();
            final rutEmisor = (nuevo['conductor_rut'] ?? '').toString();

            // REGLA DE NEGOCIO: Solo se notifica a los DEMÁS conductores cuando es 'accidente'
            if (tipo == 'accidente' && rutEmisor != rutConductorActual) {
              final gravedad = (nuevo['gravedad'] ?? 'grave').toString().toUpperCase();
              final desc = (nuevo['descripcion'] ?? 'Precaución en la vía.').toString();

              mostrarNotificacionSistema(
                titulo: '🚨 ACCIDENTE EN RUTA ($gravedad)',
                cuerpo: desc,
              );

              if (context != null && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    duration: const Duration(seconds: 6),
                    backgroundColor: const Color(0xFFB91C1C),
                    content: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: Colors.white),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'ALERTA DE RUTA: $desc',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
            }
          },
        )
        .subscribe();
  }

  static Future<void> mostrarNotificacionSistema({
    required String titulo,
    required String cuerpo,
  }) async {
    if (kIsWeb) return;

    const androidDetails = AndroidNotificationDetails(
      'canal_accidentes_tc',
      'Alertas de Accidentes en Ruta',
      channelDescription: 'Notificaciones urgentes de accidentes reportados por otros conductores',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      color: Color(0xFFDC2626),
    );

    const details = NotificationDetails(android: androidDetails);
    final idNotif = DateTime.now().millisecondsSinceEpoch.remainder(100000);

    // Corrección para flutter_local_notifications v18/v19+
    await _notificationsPlugin.show(
      idNotif,
      titulo,
      cuerpo,
      details,
    );
  }
}