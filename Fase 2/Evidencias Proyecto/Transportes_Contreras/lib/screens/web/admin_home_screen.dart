import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/app_colors.dart';
import '../../widgets/admin_shell.dart';
import 'asignar_viaje_screen.dart';
import 'web_map_helper.dart';
import 'gestion_viajes_asignados_screen.dart';

enum ModoCumplimiento { dia, semana, ciclo }

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  bool _isLoading = true;

  int _conductoresCount = 0;
  int _viajesActivosCount = 0;
  int _cargasPendientesCount = 0;
  int _alertasCount = 0;

  Map<String, dynamic>? _ultimoIncidente;
  List<dynamic> _todosLosViajes = [];

  // Estado del Resumen de Cumplimiento (Día / Semana / Ciclo)
  ModoCumplimiento _modoCumplimiento = ModoCumplimiento.ciclo;
  DateTime _fechaBaseCumplimiento = DateTime.now();
  late int _mesCierreResumen;
  late int _anioCierreResumen;

  // Filtros de la tabla de viajes
  final TextEditingController _busquedaViajesCtrl = TextEditingController();
  DateTime _fechaSeleccionada = DateTime.now();
  String _estadoFiltro = 'todos'; // 'todos', 'en_curso', 'pendiente', 'completado'

  // Mapas de búsqueda rápida por ID / RUT para resolver nombres y patentes con 100% de certeza
  Map<String, String> _mapaConductores = {};
  Map<String, String> _mapaCamiones = {};
  Map<String, String> _mapaConsignatarios = {};
  Map<String, String> _mapaRegiones = {};

  final ScrollController _tablaScrollController = ScrollController();

  final Color _redAccidentColor = const Color(0xFFDC2626);
  final Color _yellowMechColor = const Color(0xFFD97706);
  final Color _orangeDelayColor = const Color(0xFFEA580C);

  bool _descripcionExpandida = false;
  bool _recargandoIncidentes = false;

  static const List<String> _nombresMesesCiclo = [
    'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
    'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'
  ];

  static const List<String> _mesesCortosCiclo = [
    'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
    'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'
  ];

  /// Devuelve (mesCierre, anioCierre) del ciclo activo (21 del mes anterior al 20 del mes actual)
  (int, int) _obtenerCicloActual() {
    final hoy = DateTime.now();
    if (hoy.day >= 21) {
      return hoy.month == 12 ? (1, hoy.year + 1) : (hoy.month + 1, hoy.year);
    }
    return (hoy.month, hoy.year);
  }

  DateTime _inicioCiclo(int mesCierre, int anioCierre) {
    final mesInicio = mesCierre == 1 ? 12 : mesCierre - 1;
    final anioInicio = mesCierre == 1 ? anioCierre - 1 : anioCierre;
    return DateTime(anioInicio, mesInicio, 21, 0, 0, 0);
  }

  DateTime _finCiclo(int mesCierre, int anioCierre) {
    return DateTime(anioCierre, mesCierre, 20, 23, 59, 59);
  }

  DateTime _inicioSemana(DateTime ref) {
    final lunes = ref.subtract(Duration(days: ref.weekday - 1));
    return DateTime(lunes.year, lunes.month, lunes.day, 0, 0, 0);
  }

  DateTime _finSemana(DateTime ref) {
    final inicio = _inicioSemana(ref);
    final domingo = inicio.add(const Duration(days: 6));
    return DateTime(domingo.year, domingo.month, domingo.day, 23, 59, 59);
  }

  void _seleccionarModoCumplimiento(ModoCumplimiento nuevoModo) {
    if (_modoCumplimiento == nuevoModo) return;
    setState(() {
      _modoCumplimiento = nuevoModo;
      if (nuevoModo == ModoCumplimiento.dia || nuevoModo == ModoCumplimiento.semana) {
        _fechaBaseCumplimiento = DateTime.now();
      } else {
        final (mesAct, anioAct) = _obtenerCicloActual();
        _mesCierreResumen = mesAct;
        _anioCierreResumen = anioAct;
      }
    });
  }

  void _navegarPeriodoCumplimiento(int delta) {
    setState(() {
      if (_modoCumplimiento == ModoCumplimiento.dia) {
        _fechaBaseCumplimiento = _fechaBaseCumplimiento.add(Duration(days: delta));
      } else if (_modoCumplimiento == ModoCumplimiento.semana) {
        _fechaBaseCumplimiento = _fechaBaseCumplimiento.add(Duration(days: delta * 7));
      } else {
        final nueva = DateTime(_anioCierreResumen, _mesCierreResumen + delta, 1);
        _mesCierreResumen = nueva.month;
        _anioCierreResumen = nueva.year;
      }
    });
  }

  Future<void> _elegirFechaCumplimiento() async {
    if (_modoCumplimiento == ModoCumplimiento.ciclo) return;
    final now = DateTime.now();
    final elegida = await showDatePicker(
      context: context,
      initialDate: _fechaBaseCumplimiento,
      firstDate: DateTime(2024),
      lastDate: DateTime(now.year + 2),
      helpText: _modoCumplimiento == ModoCumplimiento.dia
          ? 'Seleccionar día de cumplimiento'
          : 'Seleccionar cualquier día de la semana',
      cancelText: 'CANCELAR',
      confirmText: 'ACEPTAR',
      locale: const Locale('es', 'CL'),
    );
    if (elegida != null) {
      setState(() {
        _fechaBaseCumplimiento = elegida;
      });
    }
  }

  (DateTime, DateTime) _obtenerRangoActivoCumplimiento() {
    if (_modoCumplimiento == ModoCumplimiento.dia) {
      final d = _fechaBaseCumplimiento;
      return (
        DateTime(d.year, d.month, d.day, 0, 0, 0),
        DateTime(d.year, d.month, d.day, 23, 59, 59),
      );
    } else if (_modoCumplimiento == ModoCumplimiento.semana) {
      return (
        _inicioSemana(_fechaBaseCumplimiento),
        _finSemana(_fechaBaseCumplimiento),
      );
    } else {
      return (
        _inicioCiclo(_mesCierreResumen, _anioCierreResumen),
        _finCiclo(_mesCierreResumen, _anioCierreResumen),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    final (mesAct, anioAct) = _obtenerCicloActual();
    _mesCierreResumen = mesAct;
    _anioCierreResumen = anioAct;
    _cargarMetricas();
  }

  @override
  void dispose() {
    _tablaScrollController.dispose();
    _busquedaViajesCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarMetricas() async {
    try {
      final supabase = Supabase.instance.client;
      final (mesCicloActual, anioCicloActual) = _obtenerCicloActual();
      final inicioCicloIso = _inicioCiclo(mesCicloActual, anioCicloActual).toUtc().toIso8601String();
      final finCicloIso = _finCiclo(mesCicloActual, anioCicloActual).toUtc().toIso8601String();

      final results = await Future.wait([
        supabase.from('conductores').count(CountOption.exact),
        supabase.from('viajes').count(CountOption.exact).eq('estado', 'en_curso'),
        supabase.from('viajes').count(CountOption.exact).eq('estado', 'pendiente'),
        supabase
            .from('incidentes')
            .count(CountOption.exact)
            .gte('reportado_en', inicioCicloIso)
            .lte('reportado_en', finCicloIso)
            .catchError((_) => 0),
        supabase
            .from('incidentes')
            .select('id, conductor_rut, tipo_incidente, gravedad, descripcion, latitud, longitud, url_evidencia_fotografica, reportado_en, conductores(nombre_completo, telefono)')
            .gte('reportado_en', inicioCicloIso)
            .lte('reportado_en', finCicloIso)
            .order('reportado_en', ascending: false)
            .limit(1)
            .catchError((_) => <dynamic>[]),
        supabase
            .from('viajes')
            .select('*, clientes(nombre_empresa)')
            .order('fecha_viaje', ascending: false)
            .catchError((_) => <dynamic>[]),
        supabase.from('conductores').select('*').catchError((_) => <dynamic>[]),
        supabase.from('camiones').select('*').catchError((_) => <dynamic>[]),
        supabase.from('consignatarios').select('*').catchError((_) => <dynamic>[]),
        supabase.from('regiones').select('*').catchError((_) => <dynamic>[]),
      ]);

      final int conductoresCount = results[0] as int;
      final int activosCount = results[1] as int;
      final int pendientesCount = results[2] as int;
      final int totalIncidentesCiclo = results[3] as int;
      final List<dynamic> incidentesData = results[4] as List<dynamic>;
      final List<dynamic> viajesData = results[5] as List<dynamic>;

      final List<dynamic> listaConductores = results[6] as List<dynamic>;
      final List<dynamic> listaCamiones = results[7] as List<dynamic>;
      final List<dynamic> listaConsignatarios = results[8] as List<dynamic>;
      final List<dynamic> listaRegiones = results[9] as List<dynamic>;

      final Map<String, String> mapCond = {};
      for (final c in listaConductores) {
        final nombre = (c['nombre_completo'] ?? c['nombre'] ?? '').toString().trim();
        if (nombre.isNotEmpty) {
          if (c['id'] != null) mapCond[c['id'].toString()] = nombre;
          if (c['rut'] != null) mapCond[c['rut'].toString()] = nombre;
        }
      }

      final Map<String, String> mapCam = {};
      for (final cam in listaCamiones) {
        final patente = (cam['patente'] ?? cam['placa'] ?? '').toString().trim().toUpperCase();
        if (patente.isNotEmpty && cam['id'] != null) {
          mapCam[cam['id'].toString()] = patente;
        }
      }

      final Map<String, String> mapCons = {};
      for (final cons in listaConsignatarios) {
        final nombre = (cons['nombre'] ?? cons['nombre_empresa'] ?? cons['razon_social'] ?? '').toString().trim();
        if (nombre.isNotEmpty && cons['id'] != null) {
          mapCons[cons['id'].toString()] = nombre;
        }
      }

      final Map<String, String> mapReg = {};
      for (final reg in listaRegiones) {
        final nombre = (reg['nombre'] ?? reg['region'] ?? '').toString().trim();
        if (nombre.isNotEmpty && reg['id'] != null) {
          mapReg[reg['id'].toString()] = nombre;
        }
      }

      Map<String, dynamic>? ultimoIncidente;
      if (incidentesData.isNotEmpty) {
        ultimoIncidente = incidentesData.first as Map<String, dynamic>;
      }

      if (mounted) {
        setState(() {
          _conductoresCount = conductoresCount;
          _viajesActivosCount = activosCount;
          _cargasPendientesCount = pendientesCount;
          _alertasCount = totalIncidentesCiclo;
          _ultimoIncidente = ultimoIncidente;
          _todosLosViajes = viajesData;
          _mapaConductores = mapCond;
          _mapaCamiones = mapCam;
          _mapaConsignatarios = mapCons;
          _mapaRegiones = mapReg;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error cargando métricas del admin: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Extrae la fecha exacta de la columna fecha_viaje (YYYY-MM-DD) sin desfase de zona horaria
  DateTime? _obtenerFechaViaje(dynamic item) {
    final raw = item['fecha_viaje']?.toString().trim() ?? '';
    if (raw.isEmpty) return null;

    if (raw.length >= 10) {
      final partes = raw.substring(0, 10).split('-');
      if (partes.length == 3) {
        final anio = int.tryParse(partes[0]);
        final mes = int.tryParse(partes[1]);
        final dia = int.tryParse(partes[2]);
        if (anio != null && mes != null && dia != null) {
          return DateTime(anio, mes, dia);
        }
      }
    }

    final parsed = DateTime.tryParse(raw);
    if (parsed != null) {
      return DateTime(parsed.year, parsed.month, parsed.day);
    }
    return null;
  }

  /// Combina fecha_viaje (YYYY-MM-DD) con hora_descarga (HH:mm:ss) en hora local
  DateTime? _obtenerFechaHoraLimiteDescarga(dynamic item) {
    final fechaBase = _obtenerFechaViaje(item);
    if (fechaBase == null) return null;

    final horaRaw = (item['hora_descarga'] ?? '').toString().trim();
    if (horaRaw.isEmpty || horaRaw.toLowerCase() == 'null') {
      return DateTime(fechaBase.year, fechaBase.month, fechaBase.day, 23, 59, 59);
    }

    final partes = horaRaw.split(':');
    final int hora = int.tryParse(partes[0]) ?? 23;
    final int min = partes.length > 1 ? (int.tryParse(partes[1]) ?? 59) : 59;
    final int seg = partes.length > 2 ? (int.tryParse(partes[2].split('.').first) ?? 0) : 0;

    return DateTime(fechaBase.year, fechaBase.month, fechaBase.day, hora, min, seg);
  }

  Map<String, dynamic> _calcularMetricasCumplimiento() {
    final (inicio, fin) = _obtenerRangoActivoCumplimiento();
    final ahora = DateTime.now();

    int realizados = 0;
    int aTiempo = 0;
    int retrasados = 0;
    int pendientes = 0;
    int totalOperativos = 0;

    for (final v in _todosLosViajes) {
      final fechaViaje = _obtenerFechaViaje(v);
      if (fechaViaje == null) continue;
      if (fechaViaje.isBefore(inicio) || fechaViaje.isAfter(fin)) continue;

      final estado = (v['estado'] ?? '').toString().toLowerCase().trim();
      final limiteDescarga = _obtenerFechaHoraLimiteDescarga(v);

      if (estado != 'rechazado') {
        totalOperativos++;
      }

      if (estado == 'pendiente') {
        pendientes++;
      }

      if (estado == 'completado') {
        realizados++;

        final finRaw = (v['finalizado_en'] ?? '').toString().trim();
        final finalizadoDt = DateTime.tryParse(finRaw)?.toLocal();

        if (limiteDescarga != null && finalizadoDt != null) {
          if (!finalizadoDt.isAfter(limiteDescarga)) {
            aTiempo++;
          } else {
            retrasados++;
          }
        } else {
          aTiempo++;
        }
      } else if (estado != 'rechazado') {
        if (limiteDescarga != null && ahora.isAfter(limiteDescarga)) {
          retrasados++;
        }
      }
    }

    final double porcentaje = totalOperativos > 0 ? (realizados / totalOperativos) : 0.0;

    return {
      'realizados': realizados,
      'aTiempo': aTiempo,
      'retrasados': retrasados,
      'pendientes': pendientes,
      'porcentaje': porcentaje,
    };
  }

  bool _mismoDia(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// Lista filtrada por día seleccionado (fecha_viaje), texto y estado
  List<dynamic> get _filasAMostrar {
    final query = _busquedaViajesCtrl.text.toLowerCase().trim();

    final filtrados = _todosLosViajes.where((item) {
      final fechaItem = _obtenerFechaViaje(item);
      if (fechaItem == null || !_mismoDia(fechaItem, _fechaSeleccionada)) {
        return false;
      }

      final estadoRaw = (item['estado'] ?? '').toString().toLowerCase().trim();
      if (_estadoFiltro != 'todos') {
        if (_estadoFiltro == 'en_curso') {
          if (estadoRaw != 'en_curso' && estadoRaw != 'en ruta') return false;
        } else if (estadoRaw != _estadoFiltro) {
          return false;
        }
      }

      if (query.isNotEmpty) {
        final datos = _extraerDatosFilaViaje(item);
        final conductor = datos['conductor']!.toLowerCase();
        final camion = datos['camion']!.toLowerCase();
        final cliente = datos['cliente']!.toLowerCase();
        final consignatario = datos['consignatario']!.toLowerCase();

        final coincide = conductor.contains(query) ||
            camion.contains(query) ||
            cliente.contains(query) ||
            consignatario.contains(query);
        if (!coincide) return false;
      }

      return true;
    }).toList();

    filtrados.sort((a, b) {
      final fa = _obtenerFechaViaje(a) ?? DateTime(2000);
      final fb = _obtenerFechaViaje(b) ?? DateTime(2000);
      final cmpFecha = fb.compareTo(fa);
      if (cmpFecha != 0) return cmpFecha;

      final ha = (a['hora_carga'] ?? '').toString();
      final hb = (b['hora_carga'] ?? '').toString();
      return ha.compareTo(hb);
    });

    return filtrados;
  }

  Future<void> _seleccionarFechaTabla() async {
    final now = DateTime.now();
    final elegida = await showDatePicker(
      context: context,
      initialDate: _fechaSeleccionada,
      firstDate: DateTime(2024),
      lastDate: DateTime(now.year + 2),
      helpText: 'Seleccionar día de operación',
      cancelText: 'CANCELAR',
      confirmText: 'ACEPTAR',
      locale: const Locale('es', 'CL'),
    );
    if (elegida != null) {
      setState(() {
        _fechaSeleccionada = elegida;
      });
    }
  }

  Future<void> _abrirFiltroEstadoViajes() async {
    final opciones = [
      {'valor': 'todos', 'etiqueta': 'Todos los estados'},
      {'valor': 'en_curso', 'etiqueta': 'En Curso'},
      {'valor': 'pendiente', 'etiqueta': 'Pendiente'},
      {'valor': 'completado', 'etiqueta': 'Completado'},
    ];

    final seleccion = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text(
          'Filtrar viajes por estado',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
        children: opciones.map((op) {
          final activo = _estadoFiltro == op['valor'];
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, op['valor']),
            child: Row(
              children: [
                Icon(
                  activo ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  size: 18,
                  color: activo ? AppColors.primary : AppColors.textSecondary,
                ),
                const SizedBox(width: 10),
                Text(
                  op['etiqueta']!,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: activo ? FontWeight.bold : FontWeight.normal,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );

    if (seleccion != null) {
      setState(() {
        _estadoFiltro = seleccion;
      });
    }
  }

  String get _rotuloFechaTabla {
    final hoy = DateTime.now();
    final fechaFmt =
        '${_fechaSeleccionada.day.toString().padLeft(2, '0')}/${_fechaSeleccionada.month.toString().padLeft(2, '0')}/${_fechaSeleccionada.year}';
    if (_mismoDia(_fechaSeleccionada, hoy)) {
      return 'Hoy ($fechaFmt)';
    }
    return fechaFmt;
  }

  String get _rotuloEstadoTabla {
    switch (_estadoFiltro) {
      case 'en_curso':
        return 'Estado: En Curso';
      case 'pendiente':
        return 'Estado: Pendiente';
      case 'completado':
        return 'Estado: Completado';
      default:
        return 'Estado: Todos';
    }
  }

  /// Extrae los valores resueltos de cada fila de viaje
  Map<String, String> _extraerDatosFilaViaje(dynamic item) {
    final String idCorto = _formatearId(item['id'].toString());

    final String rawCondId = (item['conductor_id'] ?? '').toString();
    final String rawCondRut = (item['conductor_rut'] ?? '').toString();
    final String conductor = _mapaConductores[rawCondId] ??
        _mapaConductores[rawCondRut] ??
        (item['conductor_nombre'] ?? (rawCondRut.isNotEmpty ? rawCondRut : 'Sin asignar')).toString();

    final String rawCamId = (item['camion_id'] ?? item['id_camion'] ?? '').toString();
    final String camion = _mapaCamiones[rawCamId] ??
        (item['camion_patente'] ?? item['patente'] ?? 'Por asignar').toString().toUpperCase();

    final String cliente = (item['clientes']?['nombre_empresa'] ??
            item['cliente_nombre'] ??
            'Sin cliente')
        .toString();

    final String rawConsId = (item['consignatario_id'] ?? item['id_consignatario'] ?? '').toString();
    final String consignatario = _mapaConsignatarios[rawConsId] ??
        (item['consignatario_nombre'] ?? item['consignatario'] ?? 'No especificado').toString();

    final String rawRegId = (item['region_id'] ?? item['id_region'] ?? '').toString();
    final String region = _mapaRegiones[rawRegId] ??
        (item['region_nombre'] ?? item['region'] ?? 'Por definir').toString();

    return {
      'id': idCorto,
      'conductor': conductor,
      'camion': camion,
      'cliente': cliente,
      'consignatario': consignatario,
      'region': region,
      'estado': (item['estado'] ?? 'desconocido').toString(),
    };
  }

  String _formatearId(String rawId) {
    if (rawId.length > 8) {
      return '#${rawId.substring(0, 8).toUpperCase()}';
    }
    return rawId.startsWith('#') ? rawId : '#$rawId';
  }

  String _formatearClp(dynamic valor) {
    if (valor == null) return '\$0';
    final num numero = valor is num ? valor : (num.tryParse(valor.toString()) ?? 0);
    final int entero = numero.round();
    final String str = entero.abs().toString();
    final StringBuffer buffer = StringBuffer();

    for (int i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) {
        buffer.write('.');
      }
      buffer.write(str[i]);
    }
    return '${entero < 0 ? '-' : ''}\$${buffer.toString()}';
  }

  String _formatearFechaCorta(dynamic raw) {
    final dt = _obtenerFechaViaje({'fecha_viaje': raw});
    if (dt == null) return '—';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  String _formatearTimestamp(dynamic raw) {
    final str = raw?.toString().trim() ?? '';
    if (str.isEmpty || str.toLowerCase() == 'null') return 'No registrado';
    final dt = DateTime.tryParse(str);
    if (dt == null) return str;
    final d = dt.toLocal();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String _formatearHoraSimple(dynamic raw) {
    final str = raw?.toString().trim() ?? '';
    if (str.isEmpty || str.toLowerCase() == 'null') return '—';
    if (str.length >= 5) return str.substring(0, 5);
    return str;
  }

  String _valorTexto(dynamic raw, [String fallback = '—']) {
    final str = raw?.toString().trim() ?? '';
    if (str.isEmpty || str.toLowerCase() == 'null') return fallback;
    return str;
  }

  /// Modal completo con todos los campos de la tabla viajes (excluyendo creado_en)
  void _abrirModalDetalleViaje(dynamic item) {
    final datosResueltos = _extraerDatosFilaViaje(item);

    final String estadoRaw = datosResueltos['estado']!.toLowerCase();
    Color colorEstado = AppColors.warning;
    String textoEstado = 'Pendiente';
    if (estadoRaw == 'en_curso' || estadoRaw == 'en ruta') {
      colorEstado = Colors.green;
      textoEstado = 'En Ruta';
    } else if (estadoRaw == 'retrasado') {
      colorEstado = Colors.red;
      textoEstado = 'Retrasado';
    } else if (estadoRaw == 'completado') {
      colorEstado = Colors.grey;
      textoEstado = 'Completado';
    }

    final String latInicio = _valorTexto(item['lat_inicio'], '');
    final String lngInicio = _valorTexto(item['lng_inicio'], '');
    final String coordsInicio = (latInicio.isNotEmpty && lngInicio.isNotEmpty)
        ? '$latInicio, $lngInicio'
        : 'No registradas';

    final String latFin = _valorTexto(item['lat_fin'], '');
    final String lngFin = _valorTexto(item['lng_fin'], '');
    final String coordsFin = (latFin.isNotEmpty && lngFin.isNotEmpty)
        ? '$latFin, $lngFin'
        : 'No registradas';

    showDialog(
      context: context,
      builder: (ctx) {
        final screenWidth = MediaQuery.of(ctx).size.width;
        final isCompact = screenWidth < 650;

        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: Colors.white,
          insetPadding: EdgeInsets.symmetric(
            horizontal: isCompact ? 12 : 24,
            vertical: 20,
          ),
          child: Container(
            width: 680,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.90,
            ),
            padding: EdgeInsets.all(isCompact ? 16 : 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.local_shipping_outlined, color: AppColors.primary, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      'Viaje ${datosResueltos['id']}',
                                      style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: colorEstado.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        textoEstado,
                                        style: TextStyle(
                                          color: colorEstado,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Fecha programada: ${_formatearFechaCorta(item['fecha_viaje'])}',
                                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppColors.textSecondary, size: 20),
                      tooltip: 'Cerrar',
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(height: 1, color: AppColors.border),
                const SizedBox(height: 14),

                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildTituloSeccionModal('ASIGNACIÓN Y RUTA'),
                        _buildCajaSeccionModal([
                          _buildFilaModal('ID Viaje', datosResueltos['id']!),
                          _buildFilaModal('Conductor', datosResueltos['conductor']!),
                          _buildFilaModal('Patente Camión', datosResueltos['camion']!),
                          _buildFilaModal('Cliente', datosResueltos['cliente']!),
                          _buildFilaModal('Consignatario', datosResueltos['consignatario']!),
                          _buildFilaModal('Región', datosResueltos['region']!),
                          _buildFilaModal('Fecha Viaje', _formatearFechaCorta(item['fecha_viaje']), ultima: true),
                        ]),

                        const SizedBox(height: 16),

                        _buildTituloSeccionModal('CARGA, GUÍAS Y HORARIOS'),
                        _buildCajaSeccionModal([
                          _buildFilaModal('Número de Guía', _valorTexto(item['numero_guia'])),
                          _buildFilaModal('Guía Petróleo', _valorTexto(item['guia_petroleo'])),
                          _buildFilaModal('Pallets', _valorTexto(item['pallets'], '0')),
                          _buildFilaModal('Hora de Carga', _formatearHoraSimple(item['hora_carga'])),
                          _buildFilaModal('Hora de Descarga', _formatearHoraSimple(item['hora_descarga'])),
                          _buildFilaModal('Iniciado en', _formatearTimestamp(item['iniciado_en'])),
                          _buildFilaModal('Finalizado en', _formatearTimestamp(item['finalizado_en']), ultima: true),
                        ]),

                        const SizedBox(height: 16),

                        _buildTituloSeccionModal('HORAS ADICIONALES Y MONTOS'),
                        _buildCajaSeccionModal([
                          _buildFilaModal('Horas Nocturnas', _valorTexto(item['horas_nocturnas'], '0')),
                          _buildFilaModal('Horas Sábado', _valorTexto(item['horas_sabado'], '0')),
                          _buildFilaModal('Monto TAG', _formatearClp(item['monto_tag'])),
                          _buildFilaModal('Monto Peonetas', _formatearClp(item['monto_peonetas']), ultima: true),
                        ]),

                        const SizedBox(height: 16),

                        _buildTituloSeccionModal('GEOLOCALIZACIÓN'),
                        _buildCajaSeccionModal([
                          _buildFilaModal('Latitud / Longitud Inicio', coordsInicio),
                          _buildFilaModal('Latitud / Longitud Fin', coordsFin, ultima: true),
                        ]),

                        const SizedBox(height: 16),

                        _buildTituloSeccionModal('OBSERVACIONES'),
                        _buildCajaSeccionModal([
                          _buildFilaModal(
                            'Observaciones Admin',
                            _valorTexto(item['observaciones_admin'], 'Sin observaciones'),
                          ),
                          _buildFilaModal(
                            'Observaciones Conductor',
                            _valorTexto(item['observaciones_conductor'], 'Sin observaciones'),
                            ultima: true,
                          ),
                        ]),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTituloSeccionModal(String titulo) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        titulo,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: AppColors.primary,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  Widget _buildCajaSeccionModal(List<Widget> hijos) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: hijos,
      ),
    );
  }

  Widget _buildFilaModal(String etiqueta, String valor, {bool ultima = false}) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 170,
              child: Text(
                etiqueta,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Expanded(
              child: Text(
                valor,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        if (!ultima) const Divider(height: 16, color: AppColors.border),
      ],
    );
  }

  String _formatearTiempoRelativo(String? timestampStr) {
    if (timestampStr == null || timestampStr.isEmpty) return 'reciente';
    final dt = DateTime.tryParse(timestampStr);
    if (dt == null) return 'reciente';

    final diferencia = DateTime.now().toUtc().difference(dt.toUtc());

    if (diferencia.inSeconds < 60) return 'hace un momento';
    if (diferencia.inMinutes < 60) return 'hace ${diferencia.inMinutes} min';
    if (diferencia.inHours < 24) return 'hace ${diferencia.inHours} h';
    if (diferencia.inDays < 7) return 'hace ${diferencia.inDays} d';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  Future<void> _abrirUrlExterna(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _contactarConductor(String rutConductor, [String? nombreInicial]) async {
    String telefono = '';
    String nombre = nombreInicial ?? 'Conductor';

    try {
      final res = await Supabase.instance.client
          .from('conductores')
          .select('nombre_completo, telefono')
          .eq('rut', rutConductor)
          .maybeSingle();

      if (res != null) {
        telefono = (res['telefono'] ?? '').toString().trim();
        final String nombreDb = (res['nombre_completo'] ?? '').toString().trim();
        if (nombreDb.isNotEmpty) nombre = nombreDb;
      }
    } catch (e) {
      debugPrint('Error obteniendo teléfono del conductor: $e');
    }

    if (telefono.isEmpty) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange, size: 22),
                SizedBox(width: 10),
                Expanded(child: Text('Sin teléfono registrado', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold))),
              ],
            ),
            content: const Text(
              'El conductor no registra un número telefónico en su ficha.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                child: const Text('Entendido', style: TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ],
          ),
        );
      }
      return;
    }

    final String soloNumeros = telefono.replaceAll(RegExp(r'[^0-9+]'), '');
    final String numeroLimpio = soloNumeros.startsWith('+') ? soloNumeros : '+56$soloNumeros';

    if (!kIsWeb) {
      final uriTel = Uri.parse('tel:$numeroLimpio');
      if (await canLaunchUrl(uriTel)) {
        await launchUrl(uriTel);
      }
      return;
    }

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.phone_in_talk, color: AppColors.primary, size: 22),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Contacto del Conductor',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(nombre, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              Text('RUT: $rutConductor', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          const Icon(Icons.phone, size: 18, color: Colors.green),
                          const SizedBox(width: 8),
                          Flexible(
                            child: SelectableText(
                              telefono,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 18, color: AppColors.textSecondary),
                      tooltip: 'Copiar número',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: telefono));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Número copiado al portapapeles'), duration: Duration(seconds: 2)),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Desde PC no es posible realizar llamadas directas. Puede copiar el número o abrir una conversación directa en WhatsApp Web.',
                style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
              ),
            ],
          ),
          actions: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    final wsUrl =
                        'https://web.whatsapp.com/send?phone=${numeroLimpio.replaceAll('+', '')}&text=${Uri.encodeComponent('Hola $nombre, nos comunicamos desde la administración de Transportes Contreras respecto a su reporte en ruta.')}';
                    _abrirUrlExterna(wsUrl);
                    Navigator.of(ctx).pop();
                  },
                  icon: const Icon(Icons.chat, size: 16, color: Colors.green),
                  label: const Text('Abrir WhatsApp Web', style: TextStyle(color: Colors.green, fontSize: 12)),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                  child: const Text('Cerrar', style: TextStyle(color: Colors.white, fontSize: 12)),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  void _abrirModalImagen({
    required String? urlImagen,
    required String titulo,
    required String conductor,
    required Color colorAlerta,
  }) {
    final String urlLimpia = (urlImagen ?? '').trim();

    if (urlLimpia.isEmpty || urlLimpia.toLowerCase() == 'null' || !urlLimpia.startsWith('http')) {
      showDialog(
        context: context,
        builder: (alertCtx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Row(
            children: [
              Icon(Icons.image_not_supported_outlined, color: AppColors.textSecondary, size: 22),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Sin fotografía adjunta',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
          content: const Text(
            'Este incidente no cuenta con una evidencia fotográfica adjuntada por el conductor.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(alertCtx).pop(),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('Cerrar', style: TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (imgCtx) {
        final screenWidth = MediaQuery.of(imgCtx).size.width;
        final isMobileModal = screenWidth < 600;

        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: Colors.white,
          insetPadding: EdgeInsets.symmetric(
            horizontal: isMobileModal ? 12 : 24,
            vertical: 24,
          ),
          child: Container(
            width: 680,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(imgCtx).size.height * 0.88,
            ),
            padding: EdgeInsets.all(isMobileModal ? 16 : 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: colorAlerta.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.photo_camera_outlined, color: colorAlerta, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Evidencia: $titulo',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Conductor: $conductor',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppColors.textSecondary, size: 20),
                      tooltip: 'Cerrar Imagen',
                      onPressed: () => Navigator.of(imgCtx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Flexible(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(minHeight: 240),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: InteractiveViewer(
                        minScale: 0.8,
                        maxScale: 4.0,
                        child: Image.network(
                          urlLimpia,
                          fit: BoxFit.contain,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return SizedBox(
                              height: 300,
                              child: Center(
                                child: CircularProgressIndicator(
                                  value: loadingProgress.expectedTotalBytes != null
                                      ? loadingProgress.cumulativeBytesLoaded /
                                          loadingProgress.expectedTotalBytes!
                                      : null,
                                  color: Colors.white,
                                ),
                              ),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return const SizedBox(
                              height: 240,
                              child: Center(
                                child: Padding(
                                  padding: EdgeInsets.all(20.0),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.broken_image_outlined, color: Colors.white54, size: 42),
                                      SizedBox(height: 10),
                                      Text(
                                        'No se pudo cargar la imagen desde el servidor.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(color: Colors.white70, fontSize: 13),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    const Text(
                      'Deslice o pellizque para ampliar',
                      style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                    TextButton.icon(
                      onPressed: () => _abrirUrlExterna(urlLimpia),
                      icon: const Icon(Icons.open_in_new, size: 14),
                      label: const Text('Abrir original', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _abrirModalMapa({
    required double lat,
    required double lng,
    required String titulo,
    required String conductor,
    required String descripcion,
    required Color colorAlerta,
  }) {
    final String viewType = 'map-view-${lat.toStringAsFixed(4)}-${lng.toStringAsFixed(4)}-${DateTime.now().millisecondsSinceEpoch}';

    if (kIsWeb) {
      registrarIFrameMapa(viewType, lat, lng);
    }

    showDialog(
      context: context,
      builder: (mapCtx) {
        final screenWidth = MediaQuery.of(mapCtx).size.width;
        final isMobileModal = screenWidth < 600;

        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: Colors.white,
          insetPadding: EdgeInsets.symmetric(
            horizontal: isMobileModal ? 12 : 24,
            vertical: 24,
          ),
          child: Container(
            width: 750,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(mapCtx).size.height * 0.88,
            ),
            padding: EdgeInsets.all(isMobileModal ? 16 : 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: colorAlerta.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.location_on, color: colorAlerta, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  titulo,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Conductor: $conductor',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppColors.textSecondary, size: 20),
                      tooltip: 'Cerrar Mapa',
                      onPressed: () => Navigator.of(mapCtx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: kIsWeb
                          ? Stack(
                              children: [
                                Positioned.fill(
                                  child: construirVistaMapaWeb(viewType),
                                ),
                              ],
                            )
                          : Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.map_outlined, size: 48, color: colorAlerta),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Ubicación: ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 12),
                                  ElevatedButton.icon(
                                    onPressed: () => _abrirUrlExterna('https://www.google.com/maps/search/?api=1&query=$lat,$lng'),
                                    icon: const Icon(Icons.open_in_new, size: 16),
                                    label: const Text('Abrir en Google Maps'),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final bool estrecho = constraints.maxWidth < 480;

                    if (estrecho) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.my_location, size: 14, color: AppColors.textSecondary),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Coords: ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 38,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                _abrirUrlExterna('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
                              },
                              icon: const Icon(Icons.open_in_new, size: 14),
                              label: const Text('Abrir en Google Maps', style: TextStyle(fontSize: 12)),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: AppColors.border),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                        ],
                      );
                    }

                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.my_location, size: 14, color: AppColors.textSecondary),
                            const SizedBox(width: 6),
                            Text(
                              'Coordenadas: ${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        OutlinedButton.icon(
                          onPressed: () {
                            _abrirUrlExterna('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
                          },
                          icon: const Icon(Icons.open_in_new, size: 14),
                          label: const Text('Abrir en Google Maps', style: TextStyle(fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            side: const BorderSide(color: AppColors.border),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobileKpis = screenWidth < 780;
    final bool isStackedMiddle = screenWidth < 1150;
    final bool useHorizontalTableScroll = screenWidth < 1460;
    final bool isSmallMobile = screenWidth < 750;

    return AdminShell(
      selectedIndex: 0,
      title: 'Panel de Control',
      subtitle: 'Resumen de Operaciones',
      showBackButton: false,
      child: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : SingleChildScrollView(
              padding: EdgeInsets.all(isSmallMobile ? 16.0 : 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeroBanner(isSmallMobile),
                  const SizedBox(height: 24),
                  _buildKpisSection(isMobileKpis),
                  const SizedBox(height: 24),
                  if (!isStackedMiddle)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 2, child: _buildResumenDiario(isSmallMobile)),
                        const SizedBox(width: 24),
                        Expanded(flex: 1, child: _buildAlertasCriticas()),
                      ],
                    )
                  else ...[
                    _buildResumenDiario(isSmallMobile),
                    const SizedBox(height: 24),
                    _buildAlertasCriticas(),
                  ],
                  const SizedBox(height: 24),
                  const Text('Acciones Rápidas', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  _buildAccionesRapidas(isSmallMobile),
                  const SizedBox(height: 32),
                  const Text('Actividad Reciente de Flota', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  _buildBarraFiltrosTabla(isSmallMobile),
                  const SizedBox(height: 14),
                  _buildTablaActividadOriginal(useHorizontalTableScroll),
                ],
              ),
            ),
    );
  }

  Widget _buildHeroBanner(bool isSmallMobile) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isSmallMobile ? 20 : 32),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Flota Operativa ACTUALIZADO: EN TIEMPO REAL',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('ESTADO DE OPERACIONES', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 11)),
          Text(
            'Transportes Contreras',
            style: TextStyle(color: Colors.white, fontSize: isSmallMobile ? 24 : 32, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
            child: const Text('Sincronizado con Central', style: TextStyle(color: Colors.white70, fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Widget _buildKpisSection(bool isMobileKpis) {
    final kpis = [
      _KpiData('VIAJES ACTIVOS', _viajesActivosCount.toString(), Icons.local_shipping, Colors.blue),
      _KpiData('CARGAS PENDIENTES', _cargasPendientesCount.toString(), Icons.inventory_2, AppColors.warning),
      _KpiData('CONDUCTORES', _conductoresCount.toString(), Icons.person, AppColors.success),
      _KpiData('INCIDENTES', _alertasCount.toString(), Icons.warning_amber_rounded, Colors.red),
    ];

    if (!isMobileKpis) {
      return Row(
        children: kpis
            .map((kpi) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6.0),
                    child: _buildKpiCard(kpi.title, kpi.value, kpi.icon, kpi.color),
                  ),
                ))
            .toList(),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: kpis.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 2.2,
      ),
      itemBuilder: (context, index) {
        final kpi = kpis[index];
        return _buildKpiCard(kpi.title, kpi.value, kpi.icon, kpi.color);
      },
    );
  }

  Widget _buildKpiCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildResumenDiario(bool isSmallMobile) {
    final metricas = _calcularMetricasCumplimiento();
    final int realizados = metricas['realizados'] as int;
    final int aTiempo = metricas['aTiempo'] as int;
    final int retrasados = metricas['retrasados'] as int;
    final int pendientes = metricas['pendientes'] as int;
    final double porcentaje = metricas['porcentaje'] as double;

    String tituloResumen;
    String textoPeriodo;

    if (_modoCumplimiento == ModoCumplimiento.dia) {
      tituloResumen = 'Resumen Diario';
      final d = _fechaBaseCumplimiento;
      final hoy = DateTime.now();
      final fechaTxt = '${d.day.toString().padLeft(2, '0')} ${_mesesCortosCiclo[d.month - 1]} ${d.year}';
      textoPeriodo = _mismoDia(d, hoy) ? 'Hoy • $fechaTxt' : fechaTxt;
    } else if (_modoCumplimiento == ModoCumplimiento.semana) {
      tituloResumen = 'Resumen Semanal';
      final iniSem = _inicioSemana(_fechaBaseCumplimiento);
      final finSem = _finSemana(_fechaBaseCumplimiento);
      textoPeriodo =
          '${iniSem.day} ${_mesesCortosCiclo[iniSem.month - 1]} – ${finSem.day} ${_mesesCortosCiclo[finSem.month - 1]} ${finSem.year}';
    } else {
      tituloResumen = 'Resumen del Ciclo';
      final iniCiclo = _inicioCiclo(_mesCierreResumen, _anioCierreResumen);
      final finCiclo = _finCiclo(_mesCierreResumen, _anioCierreResumen);
      textoPeriodo =
          '21 ${_mesesCortosCiclo[iniCiclo.month - 1]} – 20 ${_mesesCortosCiclo[finCiclo.month - 1]} ${finCiclo.year}';
    }

    // Selector segmentado mutuamente excluyente: Día | Semana | Ciclo
    Widget buildPillModo(ModoCumplimiento modo, String label) {
      final bool activo = _modoCumplimiento == modo;
      return InkWell(
        onTap: () => _seleccionarModoCumplimiento(modo),
        borderRadius: BorderRadius.circular(7),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: activo ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: activo ? Colors.white : AppColors.textSecondary,
            ),
          ),
        ),
      );
    }

    final Widget selectorModos = Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          buildPillModo(ModoCumplimiento.dia, 'Día'),
          buildPillModo(ModoCumplimiento.semana, 'Semana'),
          buildPillModo(ModoCumplimiento.ciclo, 'Ciclo'),
        ],
      ),
    );

    final bool permiteCalendario = _modoCumplimiento != ModoCumplimiento.ciclo;

    final Widget navegadorPeriodo = Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: () => _navegarPeriodoCumplimiento(-1),
            icon: const Icon(Icons.chevron_left, size: 17, color: AppColors.textPrimary),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            tooltip: 'Anterior',
          ),
          InkWell(
            onTap: permiteCalendario ? _elegirFechaCumplimiento : null,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (permiteCalendario) ...[
                    const Icon(Icons.calendar_today_outlined, size: 12, color: AppColors.primary),
                    const SizedBox(width: 5),
                  ],
                  Text(
                    textoPeriodo,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            onPressed: () => _navegarPeriodoCumplimiento(1),
            icon: const Icon(Icons.chevron_right, size: 17, color: AppColors.textPrimary),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            tooltip: 'Siguiente',
          ),
        ],
      ),
    );

    return Container(
      padding: EdgeInsets.all(isSmallMobile ? 16 : 24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isSmallMobile)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tituloResumen,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Monitoreo de cumplimiento en tiempo real',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
                Flexible(
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 10,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      selectorModos,
                      navegadorPeriodo,
                    ],
                  ),
                ),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tituloResumen,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Monitoreo de cumplimiento en tiempo real',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    selectorModos,
                    navegadorPeriodo,
                  ],
                ),
              ],
            ),
          const SizedBox(height: 24),
          if (!isSmallMobile)
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _buildProgresoRutas(porcentaje),
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 4,
                  child: _buildEstadisticasConteo(
                    realizados: realizados,
                    aTiempo: aTiempo,
                    retrasados: retrasados,
                    pendientes: pendientes,
                  ),
                ),
              ],
            )
          else ...[
            _buildProgresoRutas(porcentaje),
            const SizedBox(height: 20),
            const Divider(color: AppColors.border),
            const SizedBox(height: 12),
            _buildEstadisticasConteo(
              realizados: realizados,
              aTiempo: aTiempo,
              retrasados: retrasados,
              pendientes: pendientes,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProgresoRutas(double porcentaje) {
    final int porcentajeEntero = (porcentaje * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Cumplimiento de Rutas', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const Text('Progreso Global de Despachos', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: porcentaje.clamp(0.0, 1.0),
                  backgroundColor: Colors.grey[200],
                  color: AppColors.primary,
                  minHeight: 8,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text('$porcentajeEntero%', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ],
        )
      ],
    );
  }

  Widget _buildEstadisticasConteo({
    required int realizados,
    required int aTiempo,
    required int retrasados,
    required int pendientes,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildStatBox('REALIZADOS', realizados.toString(), AppColors.primary),
        _buildStatBox('A TIEMPO', aTiempo.toString(), AppColors.success),
        _buildStatBox('RETRASADOS', retrasados.toString(), Colors.red),
        _buildStatBox('PENDIENTES', pendientes.toString(), Colors.grey),
      ],
    );
  }

  Widget _buildStatBox(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  Widget _buildAlertasCriticas() {
    if (_ultimoIncidente == null) {
      final (mesCiclo, anioCiclo) = _obtenerCicloActual();
      final ini = _inicioCiclo(mesCiclo, anioCiclo);
      final fin = _finCiclo(mesCiclo, anioCiclo);
      final rangoTexto =
          '${ini.day} ${_mesesCortosCiclo[ini.month - 1]} al ${fin.day} ${_mesesCortosCiclo[fin.month - 1]}';

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_outline, color: Colors.green, size: 20),
                      SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Registro de Incidentes',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                _recargandoIncidentes
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                      )
                    : IconButton(
                        icon: const Icon(Icons.refresh, color: AppColors.textSecondary, size: 20),
                        tooltip: 'Recargar incidentes',
                        onPressed: _recargarIncidentes,
                      ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Sin incidentes reportados en el ciclo en curso.',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Período activo: $rangoTexto • Flota operando sin novedades.',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed: _abrirModalHistorialAlertas,
                child: const Text(
                  'Ver historial de alertas anteriores',
                  style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final String tipoRaw = (_ultimoIncidente!['tipo_incidente'] ?? 'retraso').toString().toLowerCase();
    final String gravedadRaw = (_ultimoIncidente!['gravedad'] ?? 'leve').toString().toLowerCase();
    final String conductorRut = (_ultimoIncidente!['conductor_rut'] ?? '').toString();
    final String conductorNombre = (_ultimoIncidente!['conductores']?['nombre_completo'] ?? conductorRut).toString();
    final String descripcion = (_ultimoIncidente!['descripcion'] ?? 'Sin detalle reportado').toString();
    final String tiempoRelativo = _formatearTiempoRelativo(_ultimoIncidente!['reportado_en']?.toString());
    final double lat = double.tryParse(_ultimoIncidente!['latitud']?.toString() ?? '') ?? -33.437514;
    final double lng = double.tryParse(_ultimoIncidente!['longitud']?.toString() ?? '') ?? -70.782836;
    final String? urlFoto = _ultimoIncidente!['url_evidencia_fotografica']?.toString();

    Color colorBase = _orangeDelayColor;
    String tituloTipo = 'Retraso Operativo';

    if (tipoRaw == 'accidente') {
      colorBase = _redAccidentColor;
      tituloTipo = 'Accidente en Ruta';
    } else if (tipoRaw == 'falla_mecanica') {
      colorBase = _yellowMechColor;
      tituloTipo = 'Falla Mecánica';
    }

    String textoGravedad = 'Leve';
    if (gravedadRaw == 'moderada') {
      textoGravedad = 'Moderada';
    } else if (gravedadRaw == 'grave') {
      textoGravedad = 'Grave';
    }

    final bool esTextoLargo = descripcion.split('\n').length > 5 || descripcion.length > 200;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: colorBase, size: 20),
                    const SizedBox(width: 8),
                    const Flexible(
                      child: Text(
                        'Registro de Incidentes',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              _recargandoIncidentes
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                    )
                  : IconButton(
                      icon: const Icon(Icons.refresh, color: AppColors.textSecondary, size: 20),
                      tooltip: 'Recargar incidentes',
                      onPressed: _recargarIncidentes,
                    ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colorBase.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colorBase.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: colorBase,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              tituloTipo.toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const Text(
                            '•',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            textoGravedad,
                            style: TextStyle(
                              color: colorBase,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      tiempoRelativo,
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Conductor: $conductorNombre',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  descripcion,
                  maxLines: _descripcionExpandida ? null : 5,
                  overflow: _descripcionExpandida ? TextOverflow.visible : TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                if (esTextoLargo) ...[
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () {
                      setState(() {
                        _descripcionExpandida = !_descripcionExpandida;
                      });
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2.0),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _descripcionExpandida ? 'Mostrar menos' : 'Mostrar más',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: colorBase,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(
                            _descripcionExpandida ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                            size: 16,
                            color: colorBase,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    TextButton.icon(
                      onPressed: () => _contactarConductor(conductorRut, conductorNombre),
                      icon: const Icon(Icons.phone, size: 14),
                      label: const Text('Contactar Driver', style: TextStyle(fontSize: 12)),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        _abrirModalMapa(
                          lat: lat,
                          lng: lng,
                          titulo: tituloTipo,
                          conductor: conductorNombre,
                          descripcion: descripcion,
                          colorAlerta: colorBase,
                        );
                      },
                      icon: const Icon(Icons.map, size: 14, color: AppColors.textSecondary),
                      label: const Text('Ver Mapa', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        _abrirModalImagen(
                          urlImagen: urlFoto,
                          titulo: tituloTipo,
                          conductor: conductorNombre,
                          colorAlerta: colorBase,
                        );
                      },
                      icon: const Icon(Icons.image_outlined, size: 14, color: AppColors.textSecondary),
                      label: const Text('Ver Imagen', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ),
                  ],
                )
              ],
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: _abrirModalHistorialAlertas,
              child: const Text('Ver historial de alertas', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccionesRapidas(bool isSmallMobile) {
    final botones = [
      ElevatedButton.icon(
        onPressed: () => Navigator.of(context).push(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const AsignarViajeScreen(),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          ),
        ),
        icon: const Icon(Icons.add, size: 16, color: Colors.white),
        label: const Text('NUEVA CARGA', style: TextStyle(color: Colors.white, fontSize: 12)),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      OutlinedButton.icon(
        onPressed: () {},
        icon: const Icon(Icons.picture_as_pdf, size: 16),
        label: const Text('REPORTES PDF', style: TextStyle(fontSize: 12)),
        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
      ),
      OutlinedButton.icon(
        onPressed: () => Navigator.of(context).push(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const GestionViajesAsignadosScreen(),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          ),
        ),
        icon: const Icon(Icons.edit_road_outlined, size: 16, color: AppColors.primary),
        label: const Text('GESTIONAR / CANCELAR VIAJES', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary)),
        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
      ),
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: botones,
    );
  }

  Widget _buildBarraFiltrosTabla(bool isSmallMobile) {
    final bool filtroEstadoActivo = _estadoFiltro != 'todos';

    final Widget campoBusqueda = SizedBox(
      height: 42,
      child: TextField(
        controller: _busquedaViajesCtrl,
        onChanged: (_) => setState(() {}),
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: isSmallMobile
              ? 'Buscar conductor, patente, cliente...'
              : 'Buscar por conductor, patente, cliente o consignatario...',
          hintStyle: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          prefixIcon: const Icon(Icons.search, size: 18, color: AppColors.textSecondary),
          suffixIcon: _busquedaViajesCtrl.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 16, color: AppColors.textSecondary),
                  onPressed: () {
                    _busquedaViajesCtrl.clear();
                    setState(() {});
                  },
                )
              : null,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
          ),
        ),
      ),
    );

    final Widget botonCalendario = OutlinedButton.icon(
      onPressed: _seleccionarFechaTabla,
      icon: const Icon(Icons.calendar_today_outlined, size: 15, color: AppColors.primary),
      label: Text(
        _rotuloFechaTabla,
        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
      ),
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white,
        side: const BorderSide(color: AppColors.border),
        minimumSize: const Size(0, 42),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );

    final Widget botonEstado = OutlinedButton.icon(
      onPressed: _abrirFiltroEstadoViajes,
      icon: Icon(
        Icons.filter_list,
        size: 16,
        color: filtroEstadoActivo ? AppColors.primary : AppColors.textSecondary,
      ),
      label: Text(
        _rotuloEstadoTabla,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: filtroEstadoActivo ? AppColors.primary : AppColors.textPrimary,
        ),
      ),
      style: OutlinedButton.styleFrom(
        backgroundColor: filtroEstadoActivo ? AppColors.primary.withOpacity(0.08) : Colors.white,
        side: BorderSide(color: filtroEstadoActivo ? AppColors.primary : AppColors.border),
        minimumSize: const Size(0, 42),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );

    if (isSmallMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          campoBusqueda,
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              botonCalendario,
              botonEstado,
            ],
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: campoBusqueda),
        const SizedBox(width: 12),
        botonCalendario,
        const SizedBox(width: 10),
        botonEstado,
      ],
    );
  }

  Widget _buildTablaActividadOriginal(bool useHorizontalScroll) {
    final filas = _filasAMostrar;

    if (filas.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            const Icon(Icons.local_shipping_outlined, size: 36, color: Color(0xFF94A3B8)),
            const SizedBox(height: 10),
            Text(
              'No hay viajes registrados para $_rotuloFechaTabla',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 4),
            const Text(
              'Prueba seleccionando otra fecha en el calendario o limpiando los filtros aplicados.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: useHorizontalScroll
          ? Scrollbar(
              controller: _tablaScrollController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _tablaScrollController,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: 1260,
                  child: Column(
                    children: [
                      _buildEncabezadoActividadMovil(),
                      ...filas.map((item) => Column(
                            children: [
                              _buildFilaActividadMovil(item),
                              const Divider(height: 1, color: Color(0xFFF1F5F9)),
                            ],
                          )),
                    ],
                  ),
                ),
              ),
            )
          : Column(
              children: [
                _buildEncabezadoActividadPC(),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filas.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                  itemBuilder: (context, index) {
                    return _buildFilaActividadPC(filas[index]);
                  },
                ),
              ],
            ),
    );
  }

  Widget _buildEncabezadoActividadMovil() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: const [
          SizedBox(width: 105, child: Text('ID VIAJE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: AppColors.textSecondary))),
          SizedBox(width: 14),
          SizedBox(width: 180, child: Text('CONDUCTOR', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: AppColors.textSecondary))),
          SizedBox(width: 14),
          SizedBox(width: 105, child: Text('CAMIÓN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: AppColors.textSecondary))),
          SizedBox(width: 14),
          SizedBox(width: 150, child: Text('CLIENTE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: AppColors.textSecondary))),
          SizedBox(width: 14),
          SizedBox(width: 185, child: Text('CONSIGNATARIO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: AppColors.textSecondary))),
          SizedBox(width: 14),
          SizedBox(width: 145, child: Text('REGIÓN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: AppColors.textSecondary))),
          SizedBox(width: 14),
          SizedBox(width: 105, child: Text('ESTADO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: AppColors.textSecondary))),
          SizedBox(width: 14),
          SizedBox(width: 125, child: Text('ACCIÓN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: AppColors.textSecondary))),
        ],
      ),
    );
  }

  Widget _buildFilaActividadMovil(dynamic item) {
    final datos = _extraerDatosFilaViaje(item);
    final String estadoStr = datos['estado']!;

    Color colorEstado;
    String textoEstado;

    switch (estadoStr.toLowerCase()) {
      case 'en_curso':
      case 'en ruta':
        colorEstado = Colors.green;
        textoEstado = 'En Ruta';
        break;
      case 'retrasado':
        colorEstado = Colors.red;
        textoEstado = 'Retrasado';
        break;
      case 'completado':
        colorEstado = Colors.grey;
        textoEstado = 'Completado';
        break;
      default:
        colorEstado = AppColors.warning;
        textoEstado = 'Pendiente';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          SizedBox(
            width: 105,
            child: Text(
              datos['id']!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 13),
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 180,
            child: Text(
              datos['conductor']!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: AppColors.textPrimary, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 105,
            child: Text(
              datos['camion']!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 150,
            child: Text(
              datos['cliente']!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 185,
            child: Text(
              datos['consignatario']!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 145,
            child: Text(
              datos['region']!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 105,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colorEstado.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  textoEstado,
                  style: TextStyle(color: colorEstado, fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 125,
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _abrirModalDetalleViaje(item),
                icon: const Icon(Icons.visibility_outlined, size: 14, color: AppColors.primary),
                label: const Text('Ver Detalles', style: TextStyle(fontSize: 11.5, color: AppColors.primary, fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  side: const BorderSide(color: AppColors.primary),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEncabezadoActividadPC() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: const [
          Expanded(flex: 2, child: Text('ID VIAJE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: AppColors.textSecondary))),
          SizedBox(width: 12),
          Expanded(flex: 3, child: Text('CONDUCTOR', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: AppColors.textSecondary))),
          SizedBox(width: 12),
          Expanded(flex: 2, child: Text('CAMIÓN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: AppColors.textSecondary))),
          SizedBox(width: 12),
          Expanded(flex: 3, child: Text('CLIENTE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: AppColors.textSecondary))),
          SizedBox(width: 12),
          Expanded(flex: 3, child: Text('CONSIGNATARIO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: AppColors.textSecondary))),
          SizedBox(width: 12),
          Expanded(flex: 3, child: Text('REGIÓN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: AppColors.textSecondary))),
          SizedBox(width: 12),
          Expanded(flex: 2, child: Text('ESTADO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: AppColors.textSecondary))),
          SizedBox(width: 12),
          Expanded(flex: 2, child: Text('ACCIÓN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: AppColors.textSecondary))),
        ],
      ),
    );
  }

  Widget _buildFilaActividadPC(dynamic item) {
    final datos = _extraerDatosFilaViaje(item);
    final String estadoStr = datos['estado']!;

    Color colorEstado;
    String textoEstado;

    switch (estadoStr.toLowerCase()) {
      case 'en_curso':
      case 'en ruta':
        colorEstado = Colors.green;
        textoEstado = 'En Ruta';
        break;
      case 'retrasado':
        colorEstado = Colors.red;
        textoEstado = 'Retrasado';
        break;
      case 'completado':
        colorEstado = Colors.grey;
        textoEstado = 'Completado';
        break;
      default:
        colorEstado = AppColors.warning;
        textoEstado = 'Pendiente';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              datos['id']!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 13),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Text(
              datos['conductor']!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: AppColors.textPrimary, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Text(
              datos['camion']!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Text(
              datos['cliente']!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Text(
              datos['consignatario']!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Text(
              datos['region']!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colorEstado.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  textoEstado,
                  style: TextStyle(color: colorEstado, fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _abrirModalDetalleViaje(item),
                icon: const Icon(Icons.visibility_outlined, size: 14, color: AppColors.primary),
                label: const Text('Ver Detalles', style: TextStyle(fontSize: 11.5, color: AppColors.primary, fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  side: const BorderSide(color: AppColors.primary),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _abrirModalHistorialAlertas() {
    var (mesCierreModal, anioCierreModal) = _obtenerCicloActual();
    final Future<List<dynamic>> futuroIncidentes = Supabase.instance.client
        .from('incidentes')
        .select('id, conductor_rut, tipo_incidente, gravedad, descripcion, latitud, longitud, url_evidencia_fotografica, reportado_en, conductores(nombre_completo, telefono)')
        .order('reportado_en', ascending: false);

    showDialog(
      context: context,
      builder: (dialogCtx) {
        final screenWidth = MediaQuery.of(dialogCtx).size.width;
        final isCompact = screenWidth < 600;

        return StatefulBuilder(
          builder: (context, setModalState) {
            final inicio = _inicioCiclo(mesCierreModal, anioCierreModal);
            final fin = _finCiclo(mesCierreModal, anioCierreModal);
            final ahora = DateTime.now();
            final esCicloAbierto = ahora.isBefore(fin) || ahora.isAtSameMomentAs(fin);

            void cambiarCicloModal(int deltaMeses) {
              setModalState(() {
                final nueva = DateTime(anioCierreModal, mesCierreModal + deltaMeses, 1);
                mesCierreModal = nueva.month;
                anioCierreModal = nueva.year;
              });
            }

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              backgroundColor: Colors.white,
              insetPadding: EdgeInsets.symmetric(
                horizontal: isCompact ? 12 : 24,
                vertical: 24,
              ),
              child: Container(
                width: 680,
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(dialogCtx).size.height * 0.88,
                ),
                padding: EdgeInsets.all(isCompact ? 16 : 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Row(
                            children: [
                              Icon(Icons.history_rounded, color: AppColors.primary, size: 22),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Historial de Incidentes',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: AppColors.textSecondary, size: 20),
                          tooltip: 'Cerrar',
                          onPressed: () => Navigator.of(dialogCtx).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Registro histórico de incidentes, fallas y retrasos filtrados por ciclo contable (día 21 al 20).',
                      style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 14),

                    // SELECTOR DE CICLOS (21 AL 20)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: () => cambiarCicloModal(-1),
                            icon: const Icon(Icons.chevron_left, color: Colors.white, size: 24),
                            style: IconButton.styleFrom(backgroundColor: Colors.white12),
                            tooltip: 'Ciclo anterior',
                          ),
                          Expanded(
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.white12,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    esCicloAbierto ? 'CICLO EN CURSO' : 'CICLO CERRADO',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.bold,
                                      color: esCicloAbierto ? Colors.greenAccent : Colors.orangeAccent,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Período ${_nombresMesesCiclo[mesCierreModal - 1]} $anioCierreModal',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Ciclo: 21 ${_mesesCortosCiclo[inicio.month - 1]} ${inicio.year} al 20 ${_mesesCortosCiclo[fin.month - 1]} ${fin.year}',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Color(0xFFE67E22),
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => cambiarCicloModal(1),
                            icon: const Icon(Icons.chevron_right, color: Colors.white, size: 24),
                            style: IconButton.styleFrom(backgroundColor: Colors.white12),
                            tooltip: 'Ciclo siguiente',
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),
                    const Divider(height: 1, color: AppColors.border),
                    const SizedBox(height: 12),

                    Expanded(
                      child: FutureBuilder<List<dynamic>>(
                        future: futuroIncidentes,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(color: AppColors.primary),
                            );
                          }

                          if (snapshot.hasError) {
                            return Center(
                              child: Text(
                                'Error al cargar el historial: ${snapshot.error}',
                                style: const TextStyle(color: Colors.red, fontSize: 13),
                              ),
                            );
                          }

                          final List<dynamic> todos = snapshot.data ?? [];
                          final List<dynamic> delCiclo = todos.where((raw) {
                            final dt = DateTime.tryParse((raw['reportado_en'] ?? '').toString())?.toLocal();
                            if (dt == null) return false;
                            return !dt.isBefore(inicio) && !dt.isAfter(fin);
                          }).toList();

                          if (delCiclo.isEmpty) {
                            return Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.event_busy_outlined, size: 36, color: Color(0xFF94A3B8)),
                                  const SizedBox(height: 10),
                                  Text(
                                    'No hay incidentes en el ciclo ${_nombresMesesCiclo[mesCierreModal - 1]} $anioCierreModal.',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Total histórico registrado: ${todos.length}',
                                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
                                  ),
                                ],
                              ),
                            );
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Text(
                                  'Mostrando ${delCiclo.length} ${delCiclo.length == 1 ? "incidente" : "incidentes"} en este ciclo (Histórico total: ${todos.length})',
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: ListView.separated(
                                  itemCount: delCiclo.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 14),
                                  itemBuilder: (context, index) {
                                    final item = Map<String, dynamic>.from(delCiclo[index] as Map);
                                    return _buildTarjetaIncidente(item);
                                  },
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTarjetaIncidente(Map<String, dynamic> item) {
    final String tipoRaw = (item['tipo_incidente'] ?? 'retraso').toString().toLowerCase();
    final String gravedadRaw = (item['gravedad'] ?? 'leve').toString().toLowerCase();
    final String conductorRut = (item['conductor_rut'] ?? '').toString();
    final String conductorNombre = (item['conductores']?['nombre_completo'] ?? conductorRut).toString();
    final String descripcion = (item['descripcion'] ?? 'Sin detalle reportado').toString();
    final String tiempoRelativo = _formatearTiempoRelativo(item['reportado_en']?.toString());
    final double lat = double.tryParse(item['latitud']?.toString() ?? '') ?? -33.437514;
    final double lng = double.tryParse(item['longitud']?.toString() ?? '') ?? -70.782836;
    final String? urlFoto = item['url_evidencia_fotografica']?.toString();

    Color colorBase = _orangeDelayColor;
    String tituloTipo = 'Retraso Operativo';

    if (tipoRaw == 'accidente') {
      colorBase = _redAccidentColor;
      tituloTipo = 'Accidente en Ruta';
    } else if (tipoRaw == 'falla_mecanica') {
      colorBase = _yellowMechColor;
      tituloTipo = 'Falla Mecánica';
    }

    String textoGravedad = 'Leve';
    if (gravedadRaw == 'moderada') {
      textoGravedad = 'Moderada';
    } else if (gravedadRaw == 'grave') {
      textoGravedad = 'Grave';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorBase.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorBase.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: colorBase,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        tituloTipo.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Text(
                      '•',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      textoGravedad,
                      style: TextStyle(
                        color: colorBase,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                tiempoRelativo,
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Conductor: $conductorNombre',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            descripcion,
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton.icon(
                onPressed: () => _contactarConductor(conductorRut, conductorNombre),
                icon: const Icon(Icons.phone, size: 14),
                label: const Text('Contactar Driver', style: TextStyle(fontSize: 12)),
              ),
              TextButton.icon(
                onPressed: () {
                  _abrirModalMapa(
                    lat: lat,
                    lng: lng,
                    titulo: tituloTipo,
                    conductor: conductorNombre,
                    descripcion: descripcion,
                    colorAlerta: colorBase,
                  );
                },
                icon: const Icon(Icons.map, size: 14, color: AppColors.textSecondary),
                label: const Text('Ver Mapa', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ),
              TextButton.icon(
                onPressed: () {
                  _abrirModalImagen(
                    urlImagen: urlFoto,
                    titulo: tituloTipo,
                    conductor: conductorNombre,
                    colorAlerta: colorBase,
                  );
                },
                icon: const Icon(Icons.image_outlined, size: 14, color: AppColors.textSecondary),
                label: const Text('Ver Imagen', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ),
            ],
          )
        ],
      ),
    );
  }

  Future<void> _recargarIncidentes() async {
    setState(() => _recargandoIncidentes = true);
    try {
      final supabase = Supabase.instance.client;
      final (mesCicloActual, anioCicloActual) = _obtenerCicloActual();
      final inicioCicloIso = _inicioCiclo(mesCicloActual, anioCicloActual).toUtc().toIso8601String();
      final finCicloIso = _finCiclo(mesCicloActual, anioCicloActual).toUtc().toIso8601String();

      final int totalIncidentesCiclo = await supabase
          .from('incidentes')
          .count(CountOption.exact)
          .gte('reportado_en', inicioCicloIso)
          .lte('reportado_en', finCicloIso)
          .catchError((_) => 0);

      final List<dynamic> incidentesData = await supabase
          .from('incidentes')
          .select('id, conductor_rut, tipo_incidente, gravedad, descripcion, latitud, longitud, url_evidencia_fotografica, reportado_en, conductores(nombre_completo, telefono)')
          .gte('reportado_en', inicioCicloIso)
          .lte('reportado_en', finCicloIso)
          .order('reportado_en', ascending: false)
          .limit(1)
          .catchError((_) => []);

      Map<String, dynamic>? ultimoIncidente;
      if (incidentesData.isNotEmpty) {
        ultimoIncidente = incidentesData.first as Map<String, dynamic>;
      }

      if (mounted) {
        setState(() {
          _alertasCount = totalIncidentesCiclo;
          _ultimoIncidente = ultimoIncidente;
          _recargandoIncidentes = false;
        });
      }
    } catch (e) {
      debugPrint('Error recargando incidentes: $e');
      if (mounted) setState(() => _recargandoIncidentes = false);
    }
  }
}

class _KpiData {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  _KpiData(this.title, this.value, this.icon, this.color);
}