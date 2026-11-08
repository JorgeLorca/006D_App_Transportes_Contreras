import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../local_db/database_helper.dart';
import '../../local_db/sync_helper.dart';

class IncidentesScreen extends StatefulWidget {
  final String? viajeIdInicial;

  const IncidentesScreen({super.key, this.viajeIdInicial});

  @override
  State<IncidentesScreen> createState() => _IncidentesScreenState();
}

class _IncidentesScreenState extends State<IncidentesScreen> {
  bool _isLoading = true;
  bool _estaOnline = true;
  bool _obteniendoGPS = false;

  String? _rutConductor;
  String? _viajeActivoId;

  // 1. Categoría principal ('accidente', 'falla_mecanica', 'retraso')
  String _tipoIncidente = 'accidente';

  // 2. Gravedad ('leve', 'moderada', 'grave')
  String _gravedad = 'moderada';

  // 3. Selección rápida de la Lista 1 (Qué ocurrió)
  String? _hechoPredefinido;

  // 4. Voz a Texto + Descripción
  final TextEditingController _descripcionCtrl = TextEditingController();
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechDisponible = false;
  bool _escuchandoVoz = false;

  // 5. Ubicación GPS, Fecha/Hora y Foto opcional
  double _latitud = -33.437514;
  double _longitud = -70.782836;
  bool _gpsConfirmado = false;
  DateTime _fechaHoraReporte = DateTime.now();
  String? _rutaFotoEvidencia;
  final ImagePicker _picker = ImagePicker();

  ListaRegistros _historialIncidentes = [];

  final Color _primaryColor = const Color(0xFF0F172A);
  final Color _redAccidentColor = const Color(0xFFDC2626);
  final Color _yellowMechColor = const Color(0xFFD97706);
  final Color _orangeDelayColor = const Color(0xFFEA580C);

  Map<String, List<String>> get _catalogoHechosPorTipo => {
        'accidente': [
          'Choque de terceros en la ruta (Camión sin daños)',
          'Camión propio involucrado en choque / colisión',
          'Ruta cortada por accidente grave más adelante',
          'Volcamiento o carga derramada en la pista',
          'Atropello o emergencia médica en la vía',
        ],
        'falla_mecanica': [
          'Pinchazo o reventón de neumático',
          'Sobrecalentamiento de motor / Temperatura alta',
          'Falla en sistema de frenos o pérdida de aire',
          'Falla eléctrica / Batería o alternador',
          'Fuga de aceite, agua o combustible',
          'Camión en pana total (Requiere asistencia en ruta)',
        ],
        'retraso': [
          'Taco / Congestión severa en autopista o ruta',
          'Demora excesiva en planta de carga o descarga',
          'Fiscalización en ruta (Carabineros / Ministerio / Aduana)',
          'Condiciones climáticas adversas (Neblina, lluvia, nieve)',
          'Espera de documentación o guía de despacho',
        ],
      };

  @override
  void initState() {
    super.initState();
    _hechoPredefinido = _catalogoHechosPorTipo['accidente']!.first;
    _inicializarModulo();
  }

  @override
  void dispose() {
    _speech.stop();
    _descripcionCtrl.dispose();
    super.dispose();
  }

  Future<void> _inicializarModulo() async {
    setState(() => _isLoading = true);
    try {
      final sesion = await DatabaseHelper.instance.obtenerSesionConductor();
      if (sesion != null) {
        _rutConductor = sesion['rut']?.toString();
      } else {
        final user = Supabase.instance.client.auth.currentUser;
        if (user != null) {
          final perfil = await Supabase.instance.client
              .from('conductores')
              .select('rut, nombre_completo')
              .eq('auth_id', user.id)
              .single();
          _rutConductor = perfil['rut'].toString();
          await DatabaseHelper.instance.guardarSesionConductor(
            user.id,
            _rutConductor!,
            perfil['nombre_completo'].toString(),
          );
        }
      }

      if (_rutConductor != null) {
        if (widget.viajeIdInicial != null && widget.viajeIdInicial!.isNotEmpty) {
          _viajeActivoId = widget.viajeIdInicial;
        } else {
          final activos = await DatabaseHelper.instance.obtenerViajesPorEstado(_rutConductor!, 'en_curso');
          if (activos.isNotEmpty) {
            _viajeActivoId = activos.first['id']?.toString();
          } else {
            final pendientes = await DatabaseHelper.instance.obtenerViajesPorEstado(_rutConductor!, 'pendiente');
            if (pendientes.isNotEmpty) {
              _viajeActivoId = pendientes.first['id']?.toString();
            }
          }
        }

        await _cargarHistorialLocal(_rutConductor!);
      }

      _actualizarTextoPredefinido();
      _capturarUbicacionYHora();
      _inicializarVozATexto();
    } catch (e) {
      debugPrint('Error inicializando módulo de incidentes: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _cargarHistorialLocal(String rut) async {
    final lista = await DatabaseHelper.instance.obtenerHistorialIncidentes(rut);
    final online = await SyncHelper.tieneInternet();
    if (mounted) {
      setState(() {
        _historialIncidentes = lista;
        _estaOnline = online;
      });
    }
  }

  Future<void> _inicializarVozATexto() async {
    try {
      final disponible = await _speech.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            if (mounted) setState(() => _escuchandoVoz = false);
          }
        },
        onError: (error) {
          debugPrint('Aviso SpeechToText: $error');
          if (mounted) setState(() => _escuchandoVoz = false);
        },
      );
      if (mounted) setState(() => _speechDisponible = disponible);
    } catch (e) {
      debugPrint('Voz a texto no disponible en este dispositivo: $e');
    }
  }

  Future<void> _alternarGrabacionVoz() async {
    if (!_speechDisponible) {
      await _inicializarVozATexto();
    }

    if (!_speechDisponible) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('El micrófono de voz a texto no está disponible. Puede usar las listas rápidas de arriba.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    if (_escuchandoVoz) {
      await _speech.stop();
      setState(() => _escuchandoVoz = false);
    } else {
      final textoBasePrevio = _descripcionCtrl.text.trim();
      setState(() => _escuchandoVoz = true);

      await _speech.listen(
        localeId: 'es_CL',
        listenFor: const Duration(seconds: 40),
        pauseFor: const Duration(seconds: 5),
        onResult: (result) {
          if (mounted) {
            setState(() {
              final vozTranscrita = result.recognizedWords;
              if (textoBasePrevio.isEmpty) {
                _descripcionCtrl.text = vozTranscrita;
              } else {
                _descripcionCtrl.text = '$textoBasePrevio. $vozTranscrita';
              }
              _descripcionCtrl.selection = TextSelection.fromPosition(
                TextPosition(offset: _descripcionCtrl.text.length),
              );
            });
          }
        },
      );
    }
  }

  Future<void> _capturarUbicacionYHora() async {
    setState(() {
      _obteniendoGPS = true;
      _fechaHoraReporte = DateTime.now();
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceEnabled) {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
          final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
          if (mounted) {
            setState(() {
              _latitud = pos.latitude;
              _longitud = pos.longitude;
              _gpsConfirmado = true;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Usando última coordenada disponible: $e');
    } finally {
      if (mounted) setState(() => _obteniendoGPS = false);
    }
  }

  void _cambiarCategoria(String nuevoTipo) {
    setState(() {
      _tipoIncidente = nuevoTipo;
      final listaOpciones = _catalogoHechosPorTipo[nuevoTipo]!;
      _hechoPredefinido = listaOpciones.first;
      if (nuevoTipo == 'accidente') {
        _gravedad = 'grave';
      } else if (nuevoTipo == 'falla_mecanica') {
        _gravedad = 'moderada';
      } else {
        _gravedad = 'leve';
      }
      _actualizarTextoPredefinido();
    });
  }

  void _actualizarTextoPredefinido() {
    String etiquetaEstado = '';
    if (_gravedad == 'leve') {
      etiquetaEstado = 'Estado: Leve (Conductor bien, en movimiento lento)';
    } else if (_gravedad == 'moderada') {
      etiquetaEstado = 'Estado: Moderado (Complicado / Requiere atención)';
    } else {
      etiquetaEstado = 'Estado: Grave (Detenido / Emergencia en ruta)';
    }

    final hecho = _hechoPredefinido ?? '';
    _descripcionCtrl.text = '$hecho — $etiquetaEstado';
  }

  Future<void> _tomarFotoEvidencia() async {
    try {
      final XFile? picked = await _picker.pickImage(source: ImageSource.camera, imageQuality: 75);
      if (picked == null) return;

      final appDir = await getApplicationDocumentsDirectory();
      final nombreArchivo = 'incidente_${DateTime.now().millisecondsSinceEpoch}${p.extension(picked.path)}';
      final copiaLocal = await File(picked.path).copy(p.join(appDir.path, nombreArchivo));

      if (mounted) {
        setState(() => _rutaFotoEvidencia = copiaLocal.path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo tomar la foto: $e'), backgroundColor: Colors.red),
        );
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

  Future<void> _enviarReporteIncidente() async {
    if (_rutConductor == null) return;

    if (_escuchandoVoz) {
      await _speech.stop();
      setState(() => _escuchandoVoz = false);
    }

    final descripcionFinal = _descripcionCtrl.text.trim().isEmpty
        ? (_hechoPredefinido ?? 'Incidente en ruta reportado por el conductor')
        : _descripcionCtrl.text.trim();

    setState(() => _isLoading = true);

    try {
      final nuevoId = _generarUuidV4();
      final ahoraIso = DateTime.now().toUtc().toIso8601String();

      await DatabaseHelper.instance.insertarIncidenteOffline({
        'id': nuevoId,
        'viaje_id': _viajeActivoId,
        'conductor_rut': _rutConductor,
        'tipo_incidente': _tipoIncidente,
        'gravedad': _gravedad,
        'descripcion': descripcionFinal,
        'latitud': _latitud,
        'longitud': _longitud,
        'local_path_evidencia': _rutaFotoEvidencia,
        'url_evidencia_fotografica': _rutaFotoEvidencia,
        'reportado_en': ahoraIso,
      });

      _rutaFotoEvidencia = null;
      await _cargarHistorialLocal(_rutConductor!);

      final subido = await SyncHelper.sincronizarTodo(_rutConductor!);
      if (mounted) {
        await _cargarHistorialLocal(_rutConductor!);

        final esAccidenteRuta = _tipoIncidente == 'accidente';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 4),
            backgroundColor: subido
                ? (esAccidenteRuta ? _redAccidentColor : Colors.green.shade700)
                : _orangeDelayColor,
            content: Text(
              subido
                  ? (esAccidenteRuta
                      ? '🚨 Alerta de Accidente enviada a todos los conductores y al Administrador.'
                      : '✅ Reporte enviado al Panel del Administrador.')
                  : '📡 Sin señal: Reporte guardado en el teléfono (se enviará automáticamente al recuperar red).',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error guardando incidente: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Color get _colorActivo {
    if (_tipoIncidente == 'accidente') return _redAccidentColor;
    if (_tipoIncidente == 'falla_mecanica') return _yellowMechColor;
    return _orangeDelayColor;
  }

  String _formatearFechaHora(DateTime dt) {
    final local = dt.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final m = local.month.toString().padLeft(2, '0');
    final y = local.year;
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$d/$m/$y • $h:$min hrs';
  }

  @override
  Widget build(BuildContext context) {
    final opcionesActuales = _catalogoHechosPorTipo[_tipoIncidente] ?? [];

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
              'Reporte de Incidentes en Ruta',
              style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: _colorActivo))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _primaryColor,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: Colors.white12,
                          child: Icon(
                            _obteniendoGPS ? Icons.gps_not_fixed : Icons.location_on,
                            color: _gpsConfirmado ? Colors.greenAccent : Colors.amberAccent,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Fecha y Hora: ${_formatearFechaHora(_fechaHoraReporte)}',
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _obteniendoGPS
                                    ? 'Detectando coordenadas GPS del incidente...'
                                    : 'GPS detectado: ${_latitud.toStringAsFixed(5)}, ${_longitud.toStringAsFixed(5)}',
                                style: const TextStyle(color: Colors.white70, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh, color: Colors.white70, size: 20),
                          tooltip: 'Actualizar GPS y Hora',
                          onPressed: _capturarUbicacionYHora,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  const Text(
                    '1. SELECCIONE EL TIPO DE REPORTE',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                  ),
                  const SizedBox(height: 10),

                  _buildBotonSeccion(
                    codigo: 'accidente',
                    titulo: 'ACCIDENTE EN RUTA',
                    subtitulo: 'Notifica con alerta emergente a todos los choferes y al Admin',
                    icono: Icons.car_crash_outlined,
                    colorBase: _redAccidentColor,
                  ),
                  const SizedBox(height: 10),
                  _buildBotonSeccion(
                    codigo: 'falla_mecanica',
                    titulo: 'PROBLEMA MECÁNICO / PANA',
                    subtitulo: 'Aviso interno directo al Panel del Administrador',
                    icono: Icons.build_circle_outlined,
                    colorBase: _yellowMechColor,
                  ),
                  const SizedBox(height: 10),
                  _buildBotonSeccion(
                    codigo: 'retraso',
                    titulo: 'RETRASO EN RUTA O PLANTA',
                    subtitulo: 'Aviso interno de demora solo para el Administrador',
                    icono: Icons.schedule_send_outlined,
                    colorBase: _orangeDelayColor,
                  ),

                  const SizedBox(height: 22),

                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: _colorActivo.withOpacity(0.4), width: 1.5),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            // Corregido: touch_app_outlined en minúsculas
                            Icon(Icons.touch_app_outlined, size: 18, color: _colorActivo),
                            const SizedBox(width: 8),
                            Text(
                              '2. SELECCIÓN RÁPIDA (LISTA PREHECHA)',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _primaryColor),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Toque qué sucedió y el estado actual sin necesidad de escribir:',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                        const SizedBox(height: 14),

                        const Text(
                          '¿Qué sucedió?',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: opcionesActuales.map((opcion) {
                            final seleccionado = _hechoPredefinido == opcion;
                            return ChoiceChip(
                              label: Text(
                                opcion,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: seleccionado ? FontWeight.bold : FontWeight.normal,
                                  color: seleccionado ? Colors.white : _primaryColor,
                                ),
                              ),
                              selected: seleccionado,
                              selectedColor: _colorActivo,
                              backgroundColor: const Color(0xFFF1F5F9),
                              onSelected: (_) {
                                setState(() {
                                  _hechoPredefinido = opcion;
                                  _actualizarTextoPredefinido();
                                });
                              },
                            );
                          }).toList(),
                        ),

                        const SizedBox(height: 18),

                        const Text(
                          '¿Cuál es la situación / gravedad?',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _buildChipGravedad(
                              valor: 'leve',
                              titulo: 'Leve / Todo bien',
                              subtitulo: 'En marcha lenta',
                              color: Colors.green.shade600,
                            ),
                            const SizedBox(width: 8),
                            _buildChipGravedad(
                              valor: 'moderada',
                              titulo: 'Moderado',
                              subtitulo: 'Pista complicada',
                              color: _yellowMechColor,
                            ),
                            const SizedBox(width: 8),
                            _buildChipGravedad(
                              valor: 'grave',
                              titulo: 'Grave / Crítico',
                              subtitulo: 'Detenido / Urgente',
                              color: _redAccidentColor,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '3. RELATAR POR VOZ (OPCIONAL)',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _primaryColor),
                            ),
                            if (_escuchandoVoz)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.fiber_manual_record, color: Colors.red, size: 12),
                                    SizedBox(width: 4),
                                    Text(
                                      'Escuchando...',
                                      style: TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Toque el botón grande para dictar por voz y la app lo pasará a texto automáticamente:',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                        const SizedBox(height: 14),

                        GestureDetector(
                          onTap: _alternarGrabacionVoz,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                            decoration: BoxDecoration(
                              color: _escuchandoVoz ? _redAccidentColor : const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: (_escuchandoVoz ? _redAccidentColor : _primaryColor).withOpacity(0.25),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  _escuchandoVoz ? Icons.stop_circle_outlined : Icons.mic_rounded,
                                  color: Colors.white,
                                  size: 40,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _escuchandoVoz
                                      ? 'HABLANDO... TOQUE PARA DETENER'
                                      : 'TOCAR PARA HABLAR (VOZ A TEXTO)',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 14),

                        TextField(
                          controller: _descripcionCtrl,
                          maxLines: 3,
                          decoration: InputDecoration(
                            labelText: 'Resumen del reporte (Editable)',
                            alignLabelWithHint: true,
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              tooltip: 'Limpiar texto',
                              onPressed: () => _descripcionCtrl.clear(),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey.shade300),
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        OutlinedButton.icon(
                          onPressed: _tomarFotoEvidencia,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 44),
                            side: BorderSide(
                              color: _rutaFotoEvidencia != null ? Colors.green : Colors.grey.shade400,
                            ),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: Icon(
                            _rutaFotoEvidencia != null ? Icons.check_circle : Icons.camera_alt_outlined,
                            color: _rutaFotoEvidencia != null ? Colors.green : _primaryColor,
                          ),
                          label: Text(
                            _rutaFotoEvidencia != null
                                ? 'Foto de evidencia adjuntada (Toque para cambiar)'
                                : 'Adjuntar Foto del Incidente (Opcional)',
                            style: TextStyle(
                              color: _rutaFotoEvidencia != null ? Colors.green.shade700 : _primaryColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    height: 58,
                    child: ElevatedButton.icon(
                      onPressed: _enviarReporteIncidente,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _colorActivo,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 3,
                      ),
                      icon: Icon(
                        _tipoIncidente == 'accidente' ? Icons.campaign_rounded : Icons.send_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                      label: Text(
                        _tipoIncidente == 'accidente'
                            ? 'ALERTAR ACCIDENTE A LA FLOTA'
                            : 'ENVIAR REPORTE AL ADMINISTRADOR',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  if (_historialIncidentes.isNotEmpty) ...[
                    Text(
                      'MIS REPORTES ENVIADOS (${_historialIncidentes.length})',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _primaryColor),
                    ),
                    const SizedBox(height: 10),
                    ..._historialIncidentes.take(5).map((inc) {
                      final tipo = (inc['tipo_incidente'] ?? 'retraso').toString();
                      final grav = (inc['gravedad'] ?? 'leve').toString().toUpperCase();
                      final desc = (inc['descripcion'] ?? '').toString();
                      final synced = (inc['is_synced'] ?? 1) == 1;
                      final dt = DateTime.tryParse(inc['reportado_en']?.toString() ?? '') ?? DateTime.now();

                      Color badgeColor = _orangeDelayColor;
                      String tituloTipo = 'Retraso Operativo';
                      if (tipo == 'accidente') {
                        badgeColor = _redAccidentColor;
                        tituloTipo = 'Accidente en Ruta (Alerta Global)';
                      } else if (tipo == 'falla_mecanica') {
                        badgeColor = _yellowMechColor;
                        tituloTipo = 'Falla Mecánica';
                      }

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(color: badgeColor, shape: BoxShape.circle),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '$tituloTipo • $grav',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _primaryColor),
                                    ),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: synced ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    synced ? 'sincronizado' : 'pendiente',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: synced ? const Color(0xFF15803D) : const Color(0xFFB45309),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(desc, style: const TextStyle(fontSize: 12, color: Color(0xFF334155))),
                            const SizedBox(height: 4),
                            Text(
                              _formatearFechaHora(dt),
                              style: const TextStyle(fontSize: 10, color: Colors.grey),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildBotonSeccion({
    required String codigo,
    required String titulo,
    required String subtitulo,
    required IconData icono,
    required Color colorBase,
  }) {
    final bool activo = _tipoIncidente == codigo;

    return InkWell(
      onTap: () => _cambiarCategoria(codigo),
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: activo ? colorBase : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: activo ? colorBase : Colors.grey.shade300,
            width: activo ? 2 : 1,
          ),
          boxShadow: activo
              ? [BoxShadow(color: colorBase.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))]
              : [],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: activo ? Colors.white24 : colorBase.withOpacity(0.12),
              child: Icon(icono, color: activo ? Colors.white : colorBase, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: activo ? Colors.white : _primaryColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitulo,
                    style: TextStyle(
                      fontSize: 11,
                      color: activo ? Colors.white.withOpacity(0.9) : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              activo ? Icons.radio_button_checked : Icons.radio_button_off,
              color: activo ? Colors.white : Colors.grey,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChipGravedad({
    required String valor,
    required String titulo,
    required String subtitulo,
    required Color color,
  }) {
    final bool activo = _gravedad == valor;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _gravedad = valor;
            _actualizarTextoPredefinido();
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: activo ? color.withOpacity(0.12) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: activo ? color : Colors.grey.shade300,
              width: activo ? 1.8 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                activo ? Icons.check_circle : Icons.circle_outlined,
                color: activo ? color : Colors.grey,
                size: 18,
              ),
              const SizedBox(height: 4),
              Text(
                titulo,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: activo ? color : _primaryColor,
                ),
              ),
              Text(
                subtitulo,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 9, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}