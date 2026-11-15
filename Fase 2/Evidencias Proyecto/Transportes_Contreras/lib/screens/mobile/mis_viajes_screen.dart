import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../local_db/database_helper.dart';
import '../../local_db/sync_helper.dart';
import 'asistencia_screen.dart';
import 'incidentes_screen.dart';

enum VistaViaje { lista, detalle, enCurso, completado }

class MisViajesScreen extends StatefulWidget {
  final bool abrirViajeActivo;

  const MisViajesScreen({super.key, this.abrirViajeActivo = false});

  @override
  State<MisViajesScreen> createState() => _MisViajesScreenState();
}

class _MisViajesScreenState extends State<MisViajesScreen> {
  // UUID por defecto antiguo que tenía Supabase en la columna consignatario_id
  static const String _uuidConsignatarioDefault = '762e3e28-f091-4c28-af8f-8ff1fbdcd8c6';

  bool _isLoading = true;
  VistaViaje _vistaActual = VistaViaje.lista;
  String? _rutConductor;
  bool _turnoAsistenciaActivo = false;

  RegistroMapa? _viajeSeleccionado;
  RegistroMapa? _viajeActivo;
  List _viajesPendientes = [];
  List _viajesRechazados = [];
  ListaRegistros _catalogoConsignatarios = [];

  final Color _primaryColor = const Color(0xFF0F172A);
  final Color _orangeColor = const Color(0xFFE67E22);
  final Color _redColor = const Color(0xFFDC2626);

  @override
  void initState() {
    super.initState();
    _cargarViajes();
  }

  Future<void> _cargarViajes() async {
    setState(() => _isLoading = true);
    try {
      final sesionLocal = await DatabaseHelper.instance.obtenerSesionConductor();
      if (sesionLocal != null) {
        _rutConductor = sesionLocal['rut']?.toString();
      } else {
        final userId = Supabase.instance.client.auth.currentUser?.id;
        if (userId != null) {
          final perfil = await Supabase.instance.client
              .from('conductores')
              .select('rut, nombre_completo')
              .eq('auth_id', userId)
              .single();
          _rutConductor = perfil['rut'].toString();
          await DatabaseHelper.instance.guardarSesionConductor(
            userId,
            _rutConductor!,
            perfil['nombre_completo'].toString(),
          );
        }
      }

      if (_rutConductor == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      await _refrescarDesdeSQLite(_rutConductor!);

      final sincronizado = await SyncHelper.sincronizarTodo(_rutConductor!);
      if (sincronizado) {
        await _refrescarDesdeSQLite(_rutConductor!);
      }
    } catch (e) {
      debugPrint('Error cargando viajes: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _refrescarDesdeSQLite(String rut) async {
    final activos = await DatabaseHelper.instance.obtenerViajesPorEstado(rut, 'en_curso');
    final pendientes = await DatabaseHelper.instance.obtenerViajesPorEstado(rut, 'pendiente');
    final rechazados = await DatabaseHelper.instance.obtenerViajesPorEstado(rut, 'rechazado');
    final consignatarios = await DatabaseHelper.instance.obtenerTodosLosConsignatarios();
    final enTurno = await DatabaseHelper.instance.tieneTurnoAsistenciaActivo(rut);

    if (mounted) {
      setState(() {
        _viajeActivo = activos.isNotEmpty ? activos.first : null;
        _viajesPendientes = pendientes;
        _viajesRechazados = rechazados;
        _catalogoConsignatarios = consignatarios;
        _turnoAsistenciaActivo = enTurno;

        if (widget.abrirViajeActivo && _viajeActivo != null && _vistaActual == VistaViaje.lista) {
          _viajeSeleccionado = _viajeActivo;
          _vistaActual = VistaViaje.enCurso;
        }

        _isLoading = false;
      });
    }
  }

  bool _faltaConsignatario(RegistroMapa? viaje) {
    if (viaje == null) return true;
    final idCons = (viaje['consignatario_id'] ?? '').toString().trim();
    if (idCons.isEmpty || idCons.toLowerCase() == 'null' || idCons == _uuidConsignatarioDefault) {
      return true;
    }
    final nombreCons = _safeString(viaje['consignatarios'], ['nombre_empresa', 'nombre'], '');
    return nombreCons.isEmpty;
  }

  Future<Position?> _obtenerCoordenadaOpcional() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.whileInUse || perm == LocationPermission.always) {
        return await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 5),
        );
      }
    } catch (_) {
      try {
        return await Geolocator.getLastKnownPosition();
      } catch (_) {}
    }
    return null;
  }

  Future<void> _iniciarRuta() async {
    if (_viajeSeleccionado == null || _rutConductor == null) return;

    // 1. VALIDACIÓN DE ASISTENCIA OBLIGATORIA: Verificar que haya marcado ENTRADA en Asistencia
    final enTurno = await DatabaseHelper.instance.tieneTurnoAsistenciaActivo(_rutConductor!);
    if (!enTurno) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Debes marcar tu ENTRADA en el módulo de Asistencia antes de poder iniciar un viaje.',
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    final viajeId = _viajeSeleccionado!['id'].toString();

    // 2. VALIDACIÓN DE RUTA DOBLE: Verificar que no tenga ya otro viaje en curso
    final yaEnRuta = await DatabaseHelper.instance.tieneViajeEnCurso(
      _rutConductor!,
      excluirViajeId: viajeId,
    );

    if (yaEnRuta) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Ya tienes un viaje EN CURSO. Debes finalizar tu viaje activo antes de iniciar otra ruta.',
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      final pos = await _obtenerCoordenadaOpcional();

      final datosInicio = <String, dynamic>{
        'estado': 'en_curso',
        'iniciado_en': DateTime.now().toUtc().toIso8601String(),
      };
      if (pos != null) {
        datosInicio['lat_inicio'] = pos.latitude;
        datosInicio['lng_inicio'] = pos.longitude;
      }

      await DatabaseHelper.instance.actualizarEstadoViajeOffline(viajeId, datosInicio);

      SyncHelper.sincronizarTodo(_rutConductor!);

      await _refrescarDesdeSQLite(_rutConductor!);
      if (mounted) {
        setState(() {
          _viajeSeleccionado = _viajeActivo;
          _vistaActual = VistaViaje.enCurso;
        });
      }
    } catch (e) {
      debugPrint('Error al iniciar ruta: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _mostrarDialogoRechazarViaje() {
    if (_viajeSeleccionado == null) return;
    final motivoCtrl = TextEditingController();
    final guiaCtrl = TextEditingController(
      text: (_viajeSeleccionado!['numero_guia'] ?? '').toString(),
    );

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.flag_rounded, color: _redColor, size: 24),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Marcar Viaje como Rechazado',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Al confirmar, este viaje quedará marcado con bandera roja de VIAJE RECHAZADO y se notificará a Administración.',
                  style: TextStyle(fontSize: 12.5, color: Colors.black87),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: guiaCtrl,
                  decoration: const InputDecoration(
                    labelText: 'N° de Guía (Si aplica)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.receipt_long),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: motivoCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Motivo del rechazo *',
                    hintText: 'Ej: Mercadería dañada, rechazo en recepción del consignatario, fuera de horario...',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: _redColor),
              onPressed: () {
                if (motivoCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Indique el motivo del rechazo del viaje.'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                Navigator.pop(ctx);
                _procesarRechazoViaje(
                  guia: guiaCtrl.text.trim(),
                  motivo: motivoCtrl.text.trim(),
                );
              },
              icon: const Icon(Icons.flag, size: 16, color: Colors.white),
              label: const Text('CONFIRMAR RECHAZO', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _procesarRechazoViaje({required String guia, required String motivo}) async {
    if (_viajeSeleccionado == null || _rutConductor == null) return;
    setState(() => _isLoading = true);

    try {
      final viajeId = _viajeSeleccionado!['id'].toString();
      final pos = await _obtenerCoordenadaOpcional();

      final datosRechazo = <String, dynamic>{
        'estado': 'rechazado',
        'observaciones_conductor': '[VIAJE RECHAZADO] $motivo',
        'finalizado_en': DateTime.now().toUtc().toIso8601String(),
      };

      if (guia.isNotEmpty) {
        datosRechazo['numero_guia'] = guia;
      }
      if (pos != null) {
        datosRechazo['lat_fin'] = pos.latitude;
        datosRechazo['lng_fin'] = pos.longitude;
      }

      await DatabaseHelper.instance.actualizarEstadoViajeOffline(viajeId, datosRechazo);

      SyncHelper.sincronizarTodo(_rutConductor!);

      await _refrescarDesdeSQLite(_rutConductor!);
      if (mounted) {
        setState(() {
          _vistaActual = VistaViaje.lista;
          _viajeSeleccionado = null;
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Viaje marcado con bandera de RECHAZADO.'),
            backgroundColor: _redColor,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error registrando viaje rechazado: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _mostrarFormularioFinalizacion() {
    final palletsRaw = _viajeSeleccionado?['pallets'];
    final palletsIniciales = (palletsRaw == null || palletsRaw.toString() == '0') ? '' : palletsRaw.toString();

    final bool pedirConsignatario = _faltaConsignatario(_viajeSeleccionado);
    String? consignatarioElegidoId = pedirConsignatario
        ? null
        : _viajeSeleccionado?['consignatario_id']?.toString();

    final numGuiaCtrl = TextEditingController();
    final palletsCtrl = TextEditingController(text: palletsIniciales);
    final horasNocturnasCtrl = TextEditingController();
    final horasSabadoCtrl = TextEditingController();
    final montoTagCtrl = TextEditingController();
    final montoPeonetasCtrl = TextEditingController();
    final guiaPetroleoCtrl = TextEditingController();
    final obsCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (BuildContext modalCtx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 20,
                right: 20,
                top: 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Finalizar Viaje y Enviar a Planilla',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Complete los datos operativos del recorrido para registrar la vuelta en su planilla.',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                    const SizedBox(height: 18),

                    // Si el Admin dejó el Consignatario pendiente, el conductor debe elegirlo aquí
                    if (pedirConsignatario || _catalogoConsignatarios.isNotEmpty) ...[
                      DropdownButtonFormField<String>(
                        value: _catalogoConsignatarios.any((c) => c['id']?.toString() == consignatarioElegidoId)
                            ? consignatarioElegidoId
                            : null,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: pedirConsignatario
                              ? 'Consignatario (Destino) * (Pendiente de asignar)'
                              : 'Consignatario (Destino)',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.location_on_outlined),
                        ),
                        items: _catalogoConsignatarios.map((c) {
                          final id = (c['id'] ?? '').toString();
                          final nombre = (c['nombre_empresa'] ?? 'Destino').toString();
                          return DropdownMenuItem<String>(
                            value: id,
                            child: Text(nombre, overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                        onChanged: (val) {
                          setModalState(() {
                            consignatarioElegidoId = val;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                    ],

                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: numGuiaCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Número de Guía *',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.receipt_long),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 1,
                          child: TextField(
                            controller: palletsCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: const InputDecoration(
                              labelText: 'Pallets *',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.inventory_2_outlined),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: horasNocturnasCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Hrs Nocturnas',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.mode_night),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: horasSabadoCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Hrs Sábado',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.calendar_today),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: montoTagCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: const InputDecoration(
                              labelText: 'Monto TAG',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.toll),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: montoPeonetasCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: const InputDecoration(
                              labelText: 'Peonetas',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.groups_outlined),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: guiaPetroleoCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Guía Petróleo (Opcional)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.local_gas_station),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: obsCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Observaciones del Conductor',
                        hintText: 'Detalle novedades en carga/descarga u otros eventos...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          if (consignatarioElegidoId == null || consignatarioElegidoId!.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Seleccione el Consignatario (Destino) donde entregó la carga'),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }
                          if (numGuiaCtrl.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('El Número de Guía es obligatorio'),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }
                          if (palletsCtrl.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Ingrese la cantidad de Pallets'),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }
                          Navigator.pop(context);
                          _procesarFinalizacion(
                            consignatarioId: consignatarioElegidoId!,
                            guia: numGuiaCtrl.text.trim(),
                            pallets: palletsCtrl.text.trim(),
                            hNocturnas: horasNocturnasCtrl.text,
                            hSabado: horasSabadoCtrl.text,
                            tag: montoTagCtrl.text,
                            peonetas: montoPeonetasCtrl.text,
                            petroleo: guiaPetroleoCtrl.text.trim(),
                            obs: obsCtrl.text.trim(),
                          );
                        },
                        child: const Text(
                          'CONFIRMAR Y ENVIAR A PLANILLA',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: _redColor, width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          _mostrarDialogoRechazarViaje();
                        },
                        icon: Icon(Icons.flag_rounded, color: _redColor, size: 18),
                        label: Text(
                          'MARCAR COMO VIAJE RECHAZADO',
                          style: TextStyle(color: _redColor, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _procesarFinalizacion({
    required String consignatarioId,
    required String guia,
    required String pallets,
    required String hNocturnas,
    required String hSabado,
    required String tag,
    required String peonetas,
    required String petroleo,
    required String obs,
  }) async {
    if (_viajeSeleccionado == null || _rutConductor == null) return;
    setState(() => _isLoading = true);

    try {
      final viajeId = _viajeSeleccionado!['id'].toString();
      final pos = await _obtenerCoordenadaOpcional();

      final datosCierre = <String, dynamic>{
        'estado': 'completado',
        'consignatario_id': consignatarioId,
        'numero_guia': guia,
        'pallets': int.tryParse(pallets) ?? (_viajeSeleccionado!['pallets'] ?? 0),
        'horas_nocturnas': double.tryParse(hNocturnas.replaceAll(',', '.')) ?? 0.0,
        'horas_sabado': double.tryParse(hSabado.replaceAll(',', '.')) ?? 0.0,
        'monto_tag': int.tryParse(tag) ?? 0,
        'monto_peonetas': int.tryParse(peonetas) ?? 0,
        'guia_petroleo': petroleo.isEmpty ? null : petroleo,
        'observaciones_conductor': obs.isEmpty ? null : obs,
        'finalizado_en': DateTime.now().toUtc().toIso8601String(),
      };

      if (pos != null) {
        datosCierre['lat_fin'] = pos.latitude;
        datosCierre['lng_fin'] = pos.longitude;
      }

      await DatabaseHelper.instance.actualizarEstadoViajeOffline(viajeId, datosCierre);

      SyncHelper.sincronizarTodo(_rutConductor!);

      if (mounted) {
        setState(() {
          _viajeSeleccionado!['numero_guia'] = guia;
          _vistaActual = VistaViaje.completado;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error al finalizar viaje: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _volverALista() {
    if (_rutConductor != null) {
      _refrescarDesdeSQLite(_rutConductor!);
    }
    setState(() {
      _vistaActual = VistaViaje.lista;
      _viajeSeleccionado = null;
    });
  }

  void _mostrarOpcionesContacto(String telefono) {
    final numeroLimpio = telefono.replaceAll(RegExp(r'[^0-9+]'), '');

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'Contactar al Cliente',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                ),
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFEFF6FF),
                  child: Icon(Icons.phone, color: Colors.blue),
                ),
                title: const Text('Llamar por Teléfono', style: TextStyle(fontWeight: FontWeight.w600)),
                onTap: () async {
                  Navigator.pop(context);
                  final uri = Uri.parse('tel:$numeroLimpio');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri);
                  } else {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('No se pudo abrir el marcador de llamadas')),
                      );
                    }
                  }
                },
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFF0FDF4),
                  child: Icon(Icons.chat, color: Colors.green),
                ),
                title: const Text('Enviar WhatsApp', style: TextStyle(fontWeight: FontWeight.w600)),
                onTap: () async {
                  Navigator.pop(context);
                  final uri = Uri.parse('https://wa.me/$numeroLimpio');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  } else {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('No se pudo abrir WhatsApp')),
                      );
                    }
                  }
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: _primaryColor,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: _vistaActual != VistaViaje.lista && _vistaActual != VistaViaje.completado
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: _volverALista,
              )
            : null,
        title: const Text(
          'Mis Viajes',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: _orangeColor))
          : _construirVistaActual(),
    );
  }

  Widget _construirVistaActual() {
    switch (_vistaActual) {
      case VistaViaje.lista:
        return _buildListaViajes();
      case VistaViaje.detalle:
        return _buildDetalleViaje();
      case VistaViaje.enCurso:
        return _buildViajeEnCurso();
      case VistaViaje.completado:
        return _buildViajeCompletado();
    }
  }

  String _safeString(dynamic relacion, List<String> keys, String fallback) {
    if (relacion == null) return fallback;

    Map? data;
    if (relacion is Map) {
      data = relacion;
    } else if (relacion is List && relacion.isNotEmpty && relacion.first is Map) {
      data = relacion.first;
    }

    if (data != null) {
      for (String key in keys) {
        if (data.containsKey(key) && data[key] != null && data[key].toString().trim().isNotEmpty) {
          return data[key].toString();
        }
      }
    }
    return fallback;
  }

  String _generarIdVisual(String? uuid) {
    if (uuid == null || uuid.isEmpty) return 'N/A';
    String shortId = uuid.length >= 8 ? uuid.substring(0, 8).toUpperCase() : uuid.toUpperCase();
    return 'TRP-$shortId';
  }

  // ================================================================= //
  // VISTA 1: LISTA DE VIAJES
  // ================================================================= //
  Widget _buildListaViajes() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_turnoAsistenciaActivo)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFF59E0B)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.access_time_filled, color: Color(0xFFB45309), size: 20),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Estás fuera de turno. Recuerda marcar tu ENTRADA en Asistencia para poder iniciar ruta.',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF92400E)),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AsistenciaScreen()),
                      ).then((_) => _cargarViajes());
                    },
                    child: const Text('Ir a Asistencia', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ],
              ),
            ),

          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('EN CURSO', style: TextStyle(color: Color(0xFF475569), fontSize: 11, fontWeight: FontWeight.bold)),
                      Text(
                        _viajeActivo != null ? '01' : '00',
                        style: const TextStyle(color: Color(0xFF0F172A), fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('PENDIENTES', style: TextStyle(color: Color(0xFF475569), fontSize: 11, fontWeight: FontWeight.bold)),
                      Text(
                        _viajesPendientes.length.toString().padLeft(2, '0'),
                        style: const TextStyle(color: Color(0xFF0F172A), fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('RECHAZADOS', style: TextStyle(color: _redColor, fontSize: 11, fontWeight: FontWeight.bold)),
                      Text(
                        _viajesRechazados.length.toString().padLeft(2, '0'),
                        style: TextStyle(color: _redColor, fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          if (_viajeActivo != null) ...[
            const Text('VIAJE EN CURSO ACTUALMENTE', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 12),
            _tarjetaViaje(_viajeActivo!, esEnCurso: true),
            const SizedBox(height: 24),
          ],

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('PRÓXIMOS SERVICIOS ASIGNADOS', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
              Text('TOTAL: ${_viajesPendientes.length}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 12),
          if (_viajesPendientes.isEmpty)
            const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('No tienes viajes pendientes asignados.')))
          else
            for (final viaje in _viajesPendientes)
              _tarjetaViaje(Map<String, dynamic>.from(viaje as Map), esEnCurso: false),

          if (_viajesRechazados.isNotEmpty) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                Icon(Icons.flag_rounded, color: _redColor, size: 18),
                const SizedBox(width: 6),
                Text(
                  'VIAJES RECHAZADOS (${_viajesRechazados.length})',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _redColor),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final vRech in _viajesRechazados)
              _tarjetaViaje(Map<String, dynamic>.from(vRech as Map), esEnCurso: false, esRechazado: true),
          ],
        ],
      ),
    );
  }

  Widget _tarjetaViaje(RegistroMapa viaje, {required bool esEnCurso, bool esRechazado = false}) {
    final clienteNombre = _safeString(viaje['clientes'], ['nombre_empresa', 'nombre', 'razon_social'], 'Cliente no especificado');
    final clienteDir = _safeString(viaje['clientes'], ['direccion', 'ubicacion'], '');

    final bool sinConsignatario = _faltaConsignatario(viaje);
    final consignatarioNombre = sinConsignatario
        ? 'Pendiente (Elegir al finalizar viaje)'
        : _safeString(viaje['consignatarios'], ['nombre_empresa', 'nombre', 'razon_social'], 'Pendiente de definir');
    final consignatarioDir = sinConsignatario
        ? ''
        : _safeString(viaje['consignatarios'], ['direccion', 'ubicacion'], '');

    final regionNombre = _safeString(viaje['regiones'], ['nombre', 'region'], '');
    final idCarga = _generarIdVisual(viaje['id']?.toString());

    final fechaViaje = viaje['fecha_viaje']?.toString() ?? '--/--/----';
    final horaCarga = viaje['hora_carga']?.toString() ?? '--:--';
    final pallets = (viaje['pallets'] == null || viaje['pallets'].toString() == '0')
        ? 'Pendiente'
        : viaje['pallets'].toString();
    final obsRechazo = (viaje['observaciones_conductor'] ?? '').toString();

    return GestureDetector(
      onTap: esRechazado
          ? null
          : () {
              setState(() {
                _viajeSeleccionado = viaje;
                _vistaActual = esEnCurso ? VistaViaje.enCurso : VistaViaje.detalle;
              });
            },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: esRechazado
                ? _redColor
                : (esEnCurso ? _orangeColor : Colors.grey.shade200),
            width: (esEnCurso || esRechazado) ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Icon(
                              esRechazado ? Icons.flag_rounded : Icons.local_shipping_outlined,
                              size: 18,
                              color: esRechazado ? _redColor : _primaryColor,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                idCarga,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: esRechazado
                              ? const Color(0xFFFEE2E2)
                              : (esEnCurso ? _orangeColor : const Color(0xFFE2E8F0)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (esRechazado) ...[
                              Icon(Icons.flag, size: 12, color: _redColor),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              esRechazado
                                  ? 'VIAJE RECHAZADO'
                                  : (esEnCurso ? 'EN CURSO' : 'PENDIENTE'),
                              style: TextStyle(
                                color: esRechazado
                                    ? _redColor
                                    : (esEnCurso ? Colors.white : const Color(0xFF475569)),
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (regionNombre.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.map_outlined, size: 13, color: Colors.grey),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            regionNombre,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _lineaRutaBasica(
                    'DESDE (CLIENTE ORIGEN)',
                    clienteNombre,
                    subtitulo: clienteDir,
                  ),
                  const SizedBox(height: 14),
                  _lineaRutaBasica(
                    'HACIA (CONSIGNATARIO DESTINO)',
                    consignatarioNombre,
                    subtitulo: consignatarioDir,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _columnaDetalleLigero(Icons.calendar_today, 'FECHA', fechaViaje),
                      _columnaDetalleLigero(Icons.access_time, 'HORA CARGA', horaCarga),
                      _columnaDetalleLigero(Icons.inventory_2, 'PALLETS', pallets),
                    ],
                  ),
                  if (esRechazado && obsRechazo.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        obsRechazo,
                        style: TextStyle(fontSize: 11.5, color: _redColor, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (!esRechazado)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      esEnCurso ? 'Continuar viaje en curso' : 'Ver detalles de la ruta',
                      style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    Icon(Icons.arrow_forward_ios, size: 14, color: _primaryColor),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _columnaDetalleLigero(IconData icon, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 12, color: Colors.grey),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
      ],
    );
  }

  Widget _lineaRutaBasica(String titulo, String lugar, {String? subtitulo}) {
    final esOrigen = titulo.contains('DESDE') || titulo.contains('ORIGEN');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(esOrigen ? Icons.circle_outlined : Icons.location_on, size: 18, color: esOrigen ? _primaryColor : _orangeColor),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
              Text(lugar, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
              if (subtitulo != null && subtitulo.trim().isNotEmpty)
                Text(subtitulo, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
            ],
          ),
        ),
      ],
    );
  }

  // ================================================================= //
  // VISTA 2: DETALLE DEL VIAJE PENDIENTE (CON BLOQUEO DE ASISTENCIA Y RUTA DOBLE)
  // ================================================================= //
  Widget _buildDetalleViaje() {
    final viaje = _viajeSeleccionado!;
    final idCarga = _generarIdVisual(viaje['id']?.toString());

    final clienteNombre = _safeString(viaje['clientes'], ['nombre_empresa', 'nombre', 'razon_social'], 'Cliente no especificado');
    final clienteDir = _safeString(viaje['clientes'], ['direccion', 'ubicacion'], '');
    final clienteTelefono = _safeString(viaje['clientes'], ['telefono', 'celular', 'contacto'], '+56900000000');

    final bool sinConsignatario = _faltaConsignatario(viaje);
    final consignatarioNombre = sinConsignatario
        ? 'Pendiente (Lo seleccionará al finalizar)'
        : _safeString(viaje['consignatarios'], ['nombre_empresa', 'nombre', 'razon_social'], 'Consignatario no especificado');
    final consignatarioDir = sinConsignatario
        ? ''
        : _safeString(viaje['consignatarios'], ['direccion', 'ubicacion'], '');

    final regionNombre = _safeString(viaje['regiones'], ['nombre', 'region'], 'Región Metropolitana');
    final patente = _safeString(viaje['camiones'], ['patente', 'placa'], 'No asignado');

    final fecha = viaje['fecha_viaje']?.toString() ?? '--/--/----';
    final horaCarga = viaje['hora_carga']?.toString() ?? '--:--';
    final horaDescarga = viaje['hora_descarga']?.toString() ?? '--:--';
    final obsAdmin = viaje['observaciones_admin']?.toString() ?? 'Sin observaciones del administrador.';

    final bool bloqueadoPorOtroViajeActivo =
        _viajeActivo != null && _viajeActivo!['id']?.toString() != viaje['id']?.toString();
    final bool bloqueadoPorFaltaAsistencia = !_turnoAsistenciaActivo;
    final bool botonBloqueado = bloqueadoPorOtroViajeActivo || bloqueadoPorFaltaAsistencia;

    return SingleChildScrollView(
      child: Column(
        children: [
          Container(
            height: 130,
            width: double.infinity,
            color: _primaryColor,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.route_outlined, size: 40, color: Colors.white70),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      '$clienteNombre ➔ $consignatarioNombre',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            transform: Matrix4.translationValues(0.0, -16.0, 0.0),
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('ID DE CARGA', style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
                        Text(idCarga, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(10)),
                      child: Text(regionNombre, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _primaryColor)),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                _lineaRutaBasica('DESDE (CLIENTE ORIGEN)', clienteNombre, subtitulo: clienteDir),
                const Padding(
                  padding: EdgeInsets.only(left: 8.0, top: 4, bottom: 4),
                  child: SizedBox(height: 20, child: VerticalDivider(color: Colors.grey, thickness: 1)),
                ),
                _lineaRutaBasica('HACIA (CONSIGNATARIO DESTINO)', consignatarioNombre, subtitulo: consignatarioDir),

                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: _columnaDetalleLigero(Icons.calendar_today, 'FECHA', fecha),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: _columnaDetalleLigero(Icons.access_time, 'CARGA', horaCarga),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: _columnaDetalleLigero(Icons.flag_outlined, 'DESCARGA', horaDescarga),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                if (bloqueadoPorFaltaAsistencia) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFF59E0B)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.where_to_vote_outlined, color: Color(0xFFB45309), size: 20),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Asistencia no registrada: Debes marcar tu ENTRADA en la base (radio 500m) antes de iniciar un viaje.',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF92400E)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const AsistenciaScreen()),
                              ).then((_) => _cargarViajes());
                            },
                            icon: const Icon(Icons.login, size: 15),
                            label: const Text('Ir a marcar Entrada ahora', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                if (bloqueadoPorOtroViajeActivo) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFCA5A5)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.lock_outline, color: Color(0xFFB91C1C), size: 20),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Ya tienes un viaje EN CURSO. Finaliza el viaje actual para poder iniciar esta ruta.',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFB91C1C)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: botonBloqueado ? null : _iniciarRuta,
                    icon: const Icon(Icons.navigation, color: Colors.white),
                    label: Text(
                      bloqueadoPorFaltaAsistencia
                          ? 'MARCA ENTRADA EN ASISTENCIA PRIMERO'
                          : (bloqueadoPorOtroViajeActivo ? 'RUTA BLOQUEADA (HAY UN VIAJE ACTIVO)' : 'INICIAR RUTA'),
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryColor,
                      disabledBackgroundColor: Colors.grey.shade400,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: OutlinedButton.icon(
                    onPressed: _mostrarDialogoRechazarViaje,
                    icon: Icon(Icons.flag_rounded, color: _redColor, size: 18),
                    label: Text(
                      'MARCAR VIAJE COMO RECHAZADO',
                      style: TextStyle(color: _redColor, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: _redColor, width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                const Text('INFORMACIÓN LOGÍSTICA', style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                _cajaInfo(
                  Icons.inventory_2_outlined,
                  'Carga Programada',
                  (viaje['pallets'] == null || viaje['pallets'].toString() == '0')
                      ? 'Pendiente (Ingresar al finalizar)'
                      : '${viaje['pallets']} Pallets',
                ),
                const SizedBox(height: 12),
                _cajaInfo(Icons.directions_car, 'Vehículo Asignado', 'Patente: $patente'),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFFEDD5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.description, size: 14, color: Color(0xFFEA580C)),
                          SizedBox(width: 6),
                          Text('NOTAS DE DESPACHO', style: TextStyle(fontSize: 10, color: Color(0xFFEA580C), fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('"$obsAdmin"', style: TextStyle(fontSize: 13, color: Colors.orange.shade900, fontStyle: FontStyle.italic)),
                    ],
                  ),
                ),

                const SizedBox(height: 28),
                const Text('CONTACTO CLIENTE', style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      const CircleAvatar(backgroundColor: Color(0xFFE2E8F0), child: Icon(Icons.person, color: Colors.grey)),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Contacto de Origen', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            Text(clienteNombre, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => _mostrarOpcionesContacto(clienteTelefono),
                        icon: const Icon(Icons.phone),
                        style: IconButton.styleFrom(backgroundColor: const Color(0xFFF1F5F9), foregroundColor: _primaryColor),
                      )
                    ],
                  ),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cajaInfo(IconData icono, String titulo, String subtitulo) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(icono, color: _primaryColor),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
              Text(subtitulo, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
            ],
          ),
        ],
      ),
    );
  }

  // ================================================================= //
  // VISTA 3: VIAJE EN CURSO
  // ================================================================= //
  Widget _buildViajeEnCurso() {
    final viaje = _viajeSeleccionado!;
    final idCarga = _generarIdVisual(viaje['id']?.toString());

    final clienteNombre = _safeString(viaje['clientes'], ['nombre_empresa', 'nombre', 'razon_social'], 'Cliente Origen');
    final clienteDir = _safeString(viaje['clientes'], ['direccion', 'ubicacion'], '');
    final bool sinConsignatario = _faltaConsignatario(viaje);
    final consignatarioNombre = sinConsignatario
        ? 'Pendiente (Se elige al finalizar)'
        : _safeString(viaje['consignatarios'], ['nombre_empresa', 'nombre', 'razon_social'], 'Consignatario Destino');
    final consignatarioDir = sinConsignatario
        ? ''
        : _safeString(viaje['consignatarios'], ['direccion', 'ubicacion'], '');
    final patente = _safeString(viaje['camiones'], ['patente', 'placa'], 'No asignado');

    final horaCarga = viaje['hora_carga']?.toString() ?? '--:--';
    final horaDescarga = viaje['hora_descarga']?.toString() ?? '--:--';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: _primaryColor, borderRadius: BorderRadius.circular(16)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ID DE VIAJE', style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
                    Text(idCarga, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(12)),
                      child: const Text('● En curso', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    )
                  ],
                ),
                const Icon(Icons.local_shipping, size: 60, color: Colors.white24)
              ],
            ),
          ),
          const SizedBox(height: 24),

          const Text('Recorrido (Cliente ➔ Consignatario)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.directions_car, color: _primaryColor),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('VEHÍCULO ASIGNADO', style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                    Text('Patente: $patente', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                  ],
                )
              ],
            ),
          ),
          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.history, size: 16, color: Colors.grey),
                    SizedBox(width: 8),
                    Text('HOJA DE RUTA', style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 16),
                _lineaHojaRuta(
                  Icons.radio_button_checked,
                  _primaryColor,
                  'DESDE: $clienteNombre',
                  '${clienteDir.isNotEmpty ? "$clienteDir • " : ""}SALIDA EST: $horaCarga',
                ),
                const Padding(
                  padding: EdgeInsets.only(left: 7.0, top: 2, bottom: 2),
                  child: SizedBox(height: 30, child: VerticalDivider(color: Colors.grey, thickness: 1)),
                ),
                _lineaHojaRuta(
                  Icons.location_on,
                  _orangeColor,
                  'HACIA: $consignatarioNombre',
                  '${consignatarioDir.isNotEmpty ? "$consignatarioDir • " : ""}LLEGADA EST: $horaDescarga',
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => IncidentesScreen(
                      viajeIdInicial: viaje['id']?.toString(),
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706)),
              label: const Text(
                'REPORTAR INCIDENCIA EN RUTA',
                style: TextStyle(color: Color(0xFFD97706), fontSize: 13.5, fontWeight: FontWeight.bold),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFD97706), width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _mostrarDialogoRechazarViaje,
              icon: Icon(Icons.flag_rounded, color: _redColor),
              label: Text(
                'MARCAR VIAJE COMO RECHAZADO',
                style: TextStyle(color: _redColor, fontSize: 13.5, fontWeight: FontWeight.bold),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: _redColor, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton.icon(
              onPressed: _mostrarFormularioFinalizacion,
              icon: const Icon(Icons.check_circle, color: Colors.white),
              label: const Text(
                'FINALIZAR VIAJE',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lineaHojaRuta(IconData icon, Color color, String titulo, String subtitulo) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
              Text(subtitulo, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
        ),
      ],
    );
  }

  // ================================================================= //
  // VISTA 4: COMPLETADO
  // ================================================================= //
  Widget _buildViajeCompletado() {
    final viaje = _viajeSeleccionado!;
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
              child: const Icon(Icons.check, size: 60, color: Colors.white),
            ),
            const SizedBox(height: 24),
            const Text('¡Viaje Finalizado!', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.green)),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'El viaje fue enviado automáticamente a tu Planilla del ciclo actual.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(20)),
              child: Text(
                'GUÍA: ${viaje['numero_guia'] ?? 'N/A'}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 48),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _volverALista,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text(
                    'Ver Mis Viajes',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}