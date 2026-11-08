import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../local_db/database_helper.dart';
import '../../local_db/sync_helper.dart';

class AsistenciaScreen extends StatefulWidget {
  const AsistenciaScreen({super.key});

  @override
  State<AsistenciaScreen> createState() => _AsistenciaScreenState();
}

class _AsistenciaScreenState extends State<AsistenciaScreen> {
  // Coordenadas exactas de Transportes Contreras y radio máximo de 500 metros
  static const double _baseLatitud = -33.437514;
  static const double _baseLongitud = -70.782836;
  static const double _radioMaximoMetros = 500.0;

  bool _isLoading = true;
  bool _obteniendoUbicacion = false;
  bool _estaOnline = true;

  String? _rutConductor;
  String _nombreConductor = 'Conductor';

  double? _latitudActual;
  double? _longitudActual;
  double? _distanciaMetros;
  String? _errorUbicacion;

  String _proximoEvento = 'entrada';
  ListaRegistros _historial = [];

  final Color _primaryColor = const Color(0xFF0F172A);
  final Color _orangeColor = const Color(0xFFE67E22);

  @override
  void initState() {
    super.initState();
    _inicializarModulo();
  }

  Future<void> _inicializarModulo() async {
    setState(() => _isLoading = true);
    try {
      final sesion = await DatabaseHelper.instance.obtenerSesionConductor();
      if (sesion != null) {
        _rutConductor = sesion['rut']?.toString();
        _nombreConductor = sesion['nombre_completo']?.toString() ?? 'Conductor';
      } else {
        final user = Supabase.instance.client.auth.currentUser;
        if (user != null) {
          final perfil = await Supabase.instance.client
              .from('conductores')
              .select('rut, nombre_completo')
              .eq('auth_id', user.id)
              .single();
          _rutConductor = perfil['rut'].toString();
          _nombreConductor = perfil['nombre_completo'].toString();
          await DatabaseHelper.instance.guardarSesionConductor(
            user.id,
            _rutConductor!,
            _nombreConductor,
          );
        }
      }

      if (_rutConductor != null) {
        await _cargarAsistenciaDesdeSQLite(_rutConductor!);
        await _verificarUbicacionGPS();

        final syncOk = await SyncHelper.sincronizarTodo(_rutConductor!);
        if (mounted) setState(() => _estaOnline = syncOk);
        if (syncOk) {
          await _cargarAsistenciaDesdeSQLite(_rutConductor!);
        }
      }
    } catch (e) {
      debugPrint('Error inicializando asistencia: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _cargarAsistenciaDesdeSQLite(String rut) async {
    final lista = await DatabaseHelper.instance.obtenerHistorialAsistencia(rut);
    final ultimo = await DatabaseHelper.instance.obtenerUltimoEventoAsistencia(rut);
    final online = await SyncHelper.tieneInternet();

    String siguiente = 'entrada';
    if (ultimo != null) {
      final ultimoTipo = (ultimo['tipo_evento'] ?? 'salida').toString().toLowerCase();
      siguiente = (ultimoTipo == 'entrada') ? 'salida' : 'entrada';
    }

    if (mounted) {
      setState(() {
        _historial = lista;
        _proximoEvento = siguiente;
        _estaOnline = online;
      });
    }
  }

  Future<void> _verificarUbicacionGPS() async {
    setState(() {
      _obteniendoUbicacion = true;
      _errorUbicacion = null;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _errorUbicacion = 'Active el GPS del teléfono para validar el radio de 500m.';
          _obteniendoUbicacion = false;
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _errorUbicacion = 'Permiso de ubicación denegado. Es obligatorio para marcar asistencia.';
            _obteniendoUbicacion = false;
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _errorUbicacion = 'Permiso GPS bloqueado. Habilítelo en Ajustes del teléfono.';
          _obteniendoUbicacion = false;
        });
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final distancia = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        _baseLatitud,
        _baseLongitud,
      );

      if (mounted) {
        setState(() {
          _latitudActual = pos.latitude;
          _longitudActual = pos.longitude;
          _distanciaMetros = distancia;
          _obteniendoUbicacion = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorUbicacion = 'No se pudo obtener la señal GPS: $e';
          _obteniendoUbicacion = false;
        });
      }
    }
  }

  String _generarUuidV4() {
    final rnd = Random.secure();
    const chars = '0123456789abcdef';
    final buf = StringBuffer();
    for (int i = 0; i < 36; i++) {
      if (i == 8 || i == 13 || i == 18 || i == 23) {
        buf.write('-');
      } else if (i == 14) {
        buf.write('4');
      } else if (i == 19) {
        buf.write(chars[(rnd.nextInt(16) & 0x3) | 0x8]);
      } else {
        buf.write(chars[rnd.nextInt(16)]);
      }
    }
    return buf.toString();
  }

  bool get _dentroDeRango =>
      _distanciaMetros != null && _distanciaMetros! <= _radioMaximoMetros;

  Future<void> _marcarEventoAsistencia() async {
    if (_rutConductor == null) return;

    await _verificarUbicacionGPS();

    if (!_dentroDeRango || _latitudActual == null || _longitudActual == null) {
      if (mounted) {
        final distTexto = _distanciaMetros != null ? '${_distanciaMetros!.round()} m' : 'desconocida';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Fuera de rango ($distTexto). Debe estar a máximo 500m de Transportes Contreras.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final eventoARegistrar = _proximoEvento;
    final nuevoId = _generarUuidV4();
    final ahoraIso = DateTime.now().toUtc().toIso8601String();

    setState(() => _isLoading = true);

    try {
      await DatabaseHelper.instance.insertarAsistenciaOffline({
        'id': nuevoId,
        'conductor_rut': _rutConductor,
        'tipo_evento': eventoARegistrar,
        'latitud': _latitudActual,
        'longitud': _longitudActual,
        'hora_evento': ahoraIso,
      });

      await _cargarAsistenciaDesdeSQLite(_rutConductor!);

      final subido = await SyncHelper.sincronizarTodo(_rutConductor!);
      if (mounted) {
        await _cargarAsistenciaDesdeSQLite(_rutConductor!);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              subido
                  ? 'Marca de ${eventoARegistrar.toUpperCase()} registrada y sincronizada.'
                  : 'Sin señal: Marca de ${eventoARegistrar.toUpperCase()} guardada en el teléfono.',
            ),
            backgroundColor: subido ? Colors.green : _orangeColor,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error registrando asistencia: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatearFecha(String? iso) {
    if (iso == null || iso.isEmpty) return 'Hoy';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return 'Hoy';
    final ahora = DateTime.now();
    if (dt.year == ahora.year && dt.month == ahora.month && dt.day == ahora.day) {
      return 'Hoy';
    }
    const meses = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];
    return '${dt.day.toString().padLeft(2, '0')} ${meses[dt.month - 1]} ${dt.year}';
  }

  String _formatearHora(String? iso) {
    if (iso == null || iso.isEmpty) return '--:--';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '--:--';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} hrs';
  }

  @override
  Widget build(BuildContext context) {
    final bool esEntrada = _proximoEvento == 'entrada';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: _primaryColor,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TRANSPORTES CONTRERAS',
              style: TextStyle(fontSize: 10, color: Colors.white70, fontWeight: FontWeight.bold, letterSpacing: 0.8),
            ),
            Text(
              'Control de Asistencia',
              style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location, color: Colors.white),
            tooltip: 'Actualizar GPS',
            onPressed: _verificarUbicacionGPS,
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: _orangeColor))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: _primaryColor,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: esEntrada ? Colors.grey.shade800 : Colors.green.shade700,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    esEntrada ? Icons.timer_off_outlined : Icons.access_time_filled,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    esEntrada ? 'FUERA DE TURNO' : 'JORNADA EN CURSO',
                                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: _estaOnline ? Colors.green.withOpacity(0.2) : _orangeColor.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                _estaOnline ? '● Online' : '● Offline',
                                style: TextStyle(
                                  color: _estaOnline ? Colors.greenAccent : Colors.orangeAccent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _nombreConductor,
                          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'RUT: ${_rutConductor ?? "--"}',
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          child: Divider(color: Colors.white24, height: 1),
                        ),
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: _dentroDeRango
                                  ? Colors.green.withOpacity(0.2)
                                  : Colors.red.withOpacity(0.2),
                              child: Icon(
                                _dentroDeRango ? Icons.verified_user : Icons.location_off,
                                color: _dentroDeRango ? Colors.greenAccent : Colors.redAccent,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _obteniendoUbicacion
                                        ? 'Verificando posición GPS...'
                                        : _dentroDeRango
                                            ? 'Dentro del rango permitido (≤ 500m)'
                                            : 'Fuera del rango de la empresa (> 500m)',
                                    style: TextStyle(
                                      color: _dentroDeRango ? Colors.greenAccent : Colors.amberAccent,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _errorUbicacion != null
                                        ? _errorUbicacion!
                                        : _distanciaMetros != null
                                            ? 'Distancia actual a la base: ${_distanciaMetros!.round()} metros (Máx. 500m)'
                                            : 'Toque actualizar GPS para medir distancia',
                                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      children: [
                        Text(
                          esEntrada ? 'Registro de Inicio de Jornada' : 'Registro de Fin de Jornada',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _primaryColor),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _dentroDeRango
                              ? 'Ubicación validada en base. Puede registrar su ${esEntrada ? "entrada" : "salida"}.'
                              : 'Acérquese a un radio máximo de 500 metros de la base para habilitar el botón.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          height: 64,
                          child: ElevatedButton.icon(
                            onPressed: (_dentroDeRango && !_obteniendoUbicacion)
                                ? _marcarEventoAsistencia
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: esEntrada ? Colors.green.shade600 : const Color(0xFFDC2626),
                              disabledBackgroundColor: Colors.grey.shade300,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              elevation: _dentroDeRango ? 3 : 0,
                            ),
                            icon: Icon(
                              esEntrada ? Icons.login_rounded : Icons.logout_rounded,
                              color: _dentroDeRango ? Colors.white : Colors.grey.shade600,
                              size: 26,
                            ),
                            label: Text(
                              esEntrada ? 'MARCAR ENTRADA' : 'MARCAR SALIDA',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: _dentroDeRango ? Colors.white : Colors.grey.shade600,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: _obteniendoUbicacion ? null : _verificarUbicacionGPS,
                          icon: Icon(Icons.refresh, size: 16, color: _orangeColor),
                          label: Text(
                            'Volver a comprobar mi ubicación GPS',
                            style: TextStyle(color: _orangeColor, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'HISTORIAL DE ASISTENCIA',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _primaryColor),
                      ),
                      Text(
                        '${_historial.length} registros',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  if (_historial.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: const Center(
                        child: Text(
                          'Aún no tienes registros de entrada o salida.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                  else
                    ..._historial.map((reg) {
                      final tipo = (reg['tipo_evento'] ?? 'entrada').toString().toLowerCase();
                      final bool isSynced = (reg['is_synced'] ?? 1) == 1;
                      final fecha = _formatearFecha(reg['hora_evento']?.toString());
                      final hora = _formatearHora(reg['hora_evento']?.toString());
                      final lat = (reg['latitud'] as num?)?.toStringAsFixed(5) ?? '';
                      final lng = (reg['longitud'] as num?)?.toStringAsFixed(5) ?? '';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: tipo == 'entrada'
                                  ? const Color(0xFFDCFCE7)
                                  : const Color(0xFFFEE2E2),
                              child: Icon(
                                tipo == 'entrada' ? Icons.login : Icons.logout,
                                color: tipo == 'entrada'
                                    ? const Color(0xFF15803D)
                                    : const Color(0xFFB91C1C),
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        tipo == 'entrada' ? 'Entrada a Jornada' : 'Salida de Jornada',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: _primaryColor,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: isSynced ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          isSynced ? 'sincronizado' : 'pendiente',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: isSynced ? const Color(0xFF15803D) : const Color(0xFFB45309),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '$fecha • $hora',
                                    style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'GPS: $lat, $lng',
                                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}