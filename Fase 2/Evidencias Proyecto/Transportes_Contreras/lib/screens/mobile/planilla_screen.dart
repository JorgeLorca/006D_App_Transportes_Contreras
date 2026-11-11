import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../local_db/database_helper.dart';
import '../../local_db/sync_helper.dart';

class PlanillaScreen extends StatefulWidget {
  const PlanillaScreen({super.key});

  @override
  State<PlanillaScreen> createState() => _PlanillaScreenState();
}

class _PlanillaScreenState extends State<PlanillaScreen> {
  bool _isLoading = true;
  String? _rutConductor;
  String _nombreConductor = 'Conductor';

  ListaRegistros _todosViajesCompletados = [];

  // Mes y año de cierre del ciclo seleccionado (El ciclo cierra el día 20 de este mes/año)
  late int _mesCierreCiclo;
  late int _anioCierreCiclo;

  // Filtro opcional por rango de fechas personalizado (modo cartola)
  DateTimeRange? _rangoFechasPersonalizado;
  final TextEditingController _buscadorCtrl = TextEditingController();
  String _textoBusqueda = '';

  final Color _primaryColor = const Color(0xFF0F172A);
  final Color _orangeColor = const Color(0xFFE67E22);

  static const List<String> _nombresMeses = [
    'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
    'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'
  ];

  static const List<String> _mesesCortos = [
    'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
    'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'
  ];

  @override
  void initState() {
    super.initState();
    _inicializarCicloActual();
    _cargarPlanilla();
  }

  @override
  void dispose() {
    _buscadorCtrl.dispose();
    super.dispose();
  }

  /// Calcula automáticamente en qué ciclo (21 al 20) estamos hoy
  void _inicializarCicloActual() {
    final hoy = DateTime.now();
    if (hoy.day >= 21) {
      // Si es 21 o superior, este ciclo cierra el 20 del próximo mes
      if (hoy.month == 12) {
        _mesCierreCiclo = 1;
        _anioCierreCiclo = hoy.year + 1;
      } else {
        _mesCierreCiclo = hoy.month + 1;
        _anioCierreCiclo = hoy.year;
      }
    } else {
      // Si es del 1 al 20, este ciclo cierra el 20 de este mismo mes
      _mesCierreCiclo = hoy.month;
      _anioCierreCiclo = hoy.year;
    }
  }

  DateTime get _inicioCicloSeleccionado {
    final mesInicio = _mesCierreCiclo == 1 ? 12 : _mesCierreCiclo - 1;
    final anioInicio = _mesCierreCiclo == 1 ? _anioCierreCiclo - 1 : _anioCierreCiclo;
    return DateTime(anioInicio, mesInicio, 21, 0, 0, 0);
  }

  DateTime get _finCicloSeleccionado {
    return DateTime(_anioCierreCiclo, _mesCierreCiclo, 20, 23, 59, 59);
  }

  bool get _esCicloAbierto {
    final ahora = DateTime.now();
    return ahora.isBefore(_finCicloSeleccionado) || ahora.isAtSameMomentAs(_finCicloSeleccionado);
  }

  void _cambiarCiclo(int deltaMeses) {
    setState(() {
      _rangoFechasPersonalizado = null;
      final nuevaFecha = DateTime(_anioCierreCiclo, _mesCierreCiclo + deltaMeses, 1);
      _mesCierreCiclo = nuevaFecha.month;
      _anioCierreCiclo = nuevaFecha.year;
    });
  }

  Future<void> _cargarPlanilla() async {
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
        await _leerCompletadosDesdeSQLite(_rutConductor!);
        final syncOk = await SyncHelper.sincronizarTodo(_rutConductor!);
        if (syncOk) {
          await _leerCompletadosDesdeSQLite(_rutConductor!);
        }
      }
    } catch (e) {
      debugPrint('Error cargando planilla: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _leerCompletadosDesdeSQLite(String rut) async {
    final completados = await DatabaseHelper.instance.obtenerViajesPorEstado(rut, 'completado');
    // Ordenamos del más reciente al más antiguo como una cartola bancaria
    completados.sort((a, b) {
      final fa = _obtenerFechaViaje(a);
      final fb = _obtenerFechaViaje(b);
      return fb.compareTo(fa);
    });

    if (mounted) {
      setState(() {
        _todosViajesCompletados = completados;
      });
    }
  }

  DateTime _obtenerFechaViaje(RegistroMapa viaje) {
    final finalizado = viaje['finalizado_en']?.toString();
    if (finalizado != null && finalizado.isNotEmpty) {
      final dt = DateTime.tryParse(finalizado)?.toLocal();
      if (dt != null) return dt;
    }

    final fechaStr = viaje['fecha_viaje']?.toString() ?? '';
    final dtDirecto = DateTime.tryParse(fechaStr)?.toLocal();
    if (dtDirecto != null) return dtDirecto;

    // Soporte formato DD/MM/YYYY o DD-MM-YYYY
    final partes = fechaStr.split(RegExp(r'[/\-]'));
    if (partes.length == 3) {
      final p0 = int.tryParse(partes[0]) ?? 1;
      final p1 = int.tryParse(partes[1]) ?? 1;
      final p2 = int.tryParse(partes[2]) ?? 2026;
      if (p0 > 1900) {
        return DateTime(p0, p1, p2, 12);
      } else {
        return DateTime(p2, p1, p0, 12);
      }
    }

    return DateTime.now();
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

  ListaRegistros get _viajesFiltrados {
    final DateTime desde = _rangoFechasPersonalizado != null
        ? DateTime(
            _rangoFechasPersonalizado!.start.year,
            _rangoFechasPersonalizado!.start.month,
            _rangoFechasPersonalizado!.start.day,
            0, 0, 0,
          )
        : _inicioCicloSeleccionado;

    final DateTime hasta = _rangoFechasPersonalizado != null
        ? DateTime(
            _rangoFechasPersonalizado!.end.year,
            _rangoFechasPersonalizado!.end.month,
            _rangoFechasPersonalizado!.end.day,
            23, 59, 59,
          )
        : _finCicloSeleccionado;

    return _todosViajesCompletados.where((v) {
      final fecha = _obtenerFechaViaje(v);
      final enRango = !fecha.isBefore(desde) && !fecha.isAfter(hasta);
      if (!enRango) return false;

      if (_textoBusqueda.trim().isEmpty) return true;

      final q = _textoBusqueda.toLowerCase();
      final guia = (v['numero_guia'] ?? '').toString().toLowerCase();
      final cliente = _safeString(v['clientes'], ['nombre_empresa', 'nombre'], '').toLowerCase();
      final destino = _safeString(v['consignatarios'], ['nombre_empresa', 'nombre'], '').toLowerCase();
      final patente = _safeString(v['camiones'], ['patente'], '').toLowerCase();

      return guia.contains(q) || cliente.contains(q) || destino.contains(q) || patente.contains(q);
    }).toList();
  }

  Future<void> _seleccionarRangoFechas() async {
    final seleccionado = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime(2030, 12, 31),
      initialDateRange: _rangoFechasPersonalizado ??
          DateTimeRange(start: _inicioCicloSeleccionado, end: _finCicloSeleccionado),
      helpText: 'FILTRAR CARTOLA POR FECHAS',
      cancelText: 'Cancelar',
      confirmText: 'Aplicar',
    );

    if (seleccionado != null) {
      setState(() {
        _rangoFechasPersonalizado = seleccionado;
      });
    }
  }

  String _formatearFechaCorta(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')} ${_mesesCortos[dt.month - 1]} ${dt.year}';
  }

  String _formatearHora(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} hrs';
  }

  @override
  Widget build(BuildContext context) {
    final listaCiclo = _viajesFiltrados;

    // Métricas operativas (Sin ningún valor monetario)
    final int totalViajes = listaCiclo.length;
    int totalPallets = 0;
    double totalHorasExtra = 0.0;

    for (final v in listaCiclo) {
      totalPallets += (v['pallets'] is int)
          ? (v['pallets'] as int)
          : int.tryParse(v['pallets']?.toString() ?? '0') ?? 0;
      final hn = (v['horas_nocturnas'] is num) ? (v['horas_nocturnas'] as num).toDouble() : 0.0;
      final hs = (v['horas_sabado'] is num) ? (v['horas_sabado'] as num).toDouble() : 0.0;
      totalHorasExtra += (hn + hs);
    }

    final inicioCiclo = _inicioCicloSeleccionado;
    final finCiclo = _finCicloSeleccionado;

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
              'Planilla y Cartola de Viajes',
              style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync, color: Colors.white),
            tooltip: 'Actualizar Planilla',
            onPressed: _cargarPlanilla,
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
                  // 1. SELECTOR DE CICLO AUTOMÁTICO (21 AL 20)
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: _primaryColor,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: _esCicloAbierto
                                    ? Colors.green.withOpacity(0.2)
                                    : Colors.blueGrey.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _esCicloAbierto ? Icons.autorenew : Icons.lock_clock,
                                    size: 13,
                                    color: _esCicloAbierto ? Colors.greenAccent : Colors.white70,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    _esCicloAbierto
                                        ? 'CICLO EN CURSO (CIERRA EL DÍA 20)'
                                        : 'PLANILLA RENDIDA / CERRADA',
                                    style: TextStyle(
                                      color: _esCicloAbierto ? Colors.greenAccent : Colors.white70,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              'Histórico: ${_todosViajesCompletados.length} vts',
                              style: const TextStyle(color: Colors.white60, fontSize: 11),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Navegador de meses del ciclo (21 al 20)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              onPressed: () => _cambiarCiclo(-1),
                              icon: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
                              style: IconButton.styleFrom(backgroundColor: Colors.white12),
                            ),
                            Expanded(
                              child: Column(
                                children: [
                                  Text(
                                    _rangoFechasPersonalizado != null
                                        ? 'Filtro de Fechas Personalizado'
                                        : 'Planilla ${_nombresMeses[_mesCierreCiclo - 1]} $_anioCierreCiclo',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _rangoFechasPersonalizado != null
                                        ? '${_formatearFechaCorta(_rangoFechasPersonalizado!.start)}  al  ${_formatearFechaCorta(_rangoFechasPersonalizado!.end)}'
                                        : 'Del 21 ${_mesesCortos[inicioCiclo.month - 1]} ${inicioCiclo.year} al 20 ${_mesesCortos[finCiclo.month - 1]} ${finCiclo.year}',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Color(0xFFE67E22), fontSize: 12, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => _cambiarCiclo(1),
                              icon: const Icon(Icons.chevron_right, color: Colors.white, size: 28),
                              style: IconButton.styleFrom(backgroundColor: Colors.white12),
                            ),
                          ],
                        ),

                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          child: Divider(color: Colors.white12, height: 1),
                        ),

                        // Contadores operativos del ciclo (CERO DINERO)
                        Row(
                          children: [
                            _buildMetricaCiclo(
                              valor: totalViajes.toString().padLeft(2, '0'),
                              etiqueta: 'VIAJES DEL CICLO',
                              icono: Icons.local_shipping_outlined,
                              destacado: true,
                            ),
                            const SizedBox(width: 10),
                            _buildMetricaCiclo(
                              valor: totalPallets.toString(),
                              etiqueta: 'PALLETS MOVIDOS',
                              icono: Icons.inventory_2_outlined,
                            ),
                            const SizedBox(width: 10),
                            _buildMetricaCiclo(
                              valor: '${totalHorasExtra.toStringAsFixed(1)} h',
                              etiqueta: 'HRS NOCT / SÁB',
                              icono: Icons.schedule,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 2. BUSCADOR Y FILTRO DE FECHAS ESTILO CARTOLA BANCARIA
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _buscadorCtrl,
                          onChanged: (val) => setState(() => _textoBusqueda = val),
                          decoration: InputDecoration(
                            hintText: 'Buscar por guía, cliente o destino...',
                            hintStyle: const TextStyle(fontSize: 13, color: Colors.grey),
                            prefixIcon: const Icon(Icons.search, size: 20),
                            suffixIcon: _textoBusqueda.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
                                    onPressed: () {
                                      _buscadorCtrl.clear();
                                      setState(() => _textoBusqueda = '');
                                    },
                                  )
                                : null,
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 14),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: Colors.grey.shade300),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: Colors.grey.shade300),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      InkWell(
                        onTap: _seleccionarRangoFechas,
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          height: 48,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: _rangoFechasPersonalizado != null ? _orangeColor : Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: _rangoFechasPersonalizado != null ? _orangeColor : Colors.grey.shade300,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.date_range,
                                size: 20,
                                color: _rangoFechasPersonalizado != null ? Colors.white : _primaryColor,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Fechas',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: _rangoFechasPersonalizado != null ? Colors.white : _primaryColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  if (_rangoFechasPersonalizado != null) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => setState(() => _rangoFechasPersonalizado = null),
                        icon: const Icon(Icons.restore, size: 16),
                        label: const Text('Volver al ciclo automático (21 al 20)', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                  ],

                  const SizedBox(height: 18),

                  // 3. CABECERA DE CARTOLA DE MOVIMIENTOS
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'CARTOLA DE VIAJES REALIZADOS',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _primaryColor, letterSpacing: 0.5),
                      ),
                      Text(
                        '$totalViajes ${totalViajes == 1 ? "vuelta registrada" : "vueltas registradas"}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  if (listaCiclo.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.receipt_long_outlined, size: 42, color: Colors.grey.shade400),
                          const SizedBox(height: 10),
                          const Text(
                            'No hay viajes finalizados en este período.',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Cada vez que finalices un viaje en ruta, aparecerá automáticamente en esta cartola.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  else
                    ...listaCiclo.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final viaje = entry.value;
                      // Numeración correlativa de la vuelta dentro del ciclo
                      final numeroVuelta = totalViajes - idx;
                      return _buildItemCartola(viaje, numeroVuelta);
                    }),
                ],
              ),
            ),
    );
  }

  Widget _buildMetricaCiclo({
    required String valor,
    required String etiqueta,
    required IconData icono,
    bool destacado = false,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: destacado ? _orangeColor : Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(icono, color: Colors.white, size: 18),
            const SizedBox(height: 6),
            Text(
              valor,
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(
              etiqueta,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemCartola(RegistroMapa viaje, int numeroVuelta) {
    final fechaDt = _obtenerFechaViaje(viaje);
    final cliente = _safeString(viaje['clientes'], ['nombre_empresa', 'nombre', 'razon_social'], 'Origen');
    final destino = _safeString(viaje['consignatarios'], ['nombre_empresa', 'nombre', 'razon_social'], 'Destino');
    final region = _safeString(viaje['regiones'], ['nombre'], '');
    final patente = _safeString(viaje['camiones'], ['patente'], 'S/P');

    final guia = (viaje['numero_guia'] ?? 'S/G').toString();
    final pallets = (viaje['pallets'] ?? 0).toString();
    final guiaPetroleo = (viaje['guia_petroleo'] ?? '').toString();
    final hNoct = (viaje['horas_nocturnas'] is num) ? (viaje['horas_nocturnas'] as num).toDouble() : 0.0;
    final hSab = (viaje['horas_sabado'] is num) ? (viaje['horas_sabado'] as num).toDouble() : 0.0;
    final bool isSynced = (viaje['is_synced'] ?? 1) == 1;

    return InkWell(
      onTap: () => _mostrarDetalleCartola(viaje, numeroVuelta),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Caja de fecha estilo cartola bancaria
            Container(
              width: 50,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  Text(
                    fechaDt.day.toString().padLeft(2, '0'),
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _primaryColor),
                  ),
                  Text(
                    _mesesCortos[fechaDt.month - 1].toUpperCase(),
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),

            // Cuerpo del movimiento
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _primaryColor.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Vuelta #$numeroVuelta • Guía $guia',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _primaryColor),
                        ),
                      ),
                      Icon(
                        isSynced ? Icons.cloud_done_outlined : Icons.cloud_upload_outlined,
                        size: 15,
                        color: isSynced ? Colors.green : _orangeColor,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$cliente ➔ $destino',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: _primaryColor),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 10,
                    runSpacing: 4,
                    children: [
                      Text('🚛 $patente', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      Text('📦 $pallets pallets', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      if (region.isNotEmpty)
                        Text('📍 $region', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      if (hNoct > 0 || hSab > 0)
                        Text(
                          '⏱️ +${(hNoct + hSab).toStringAsFixed(1)}h extra',
                          style: TextStyle(fontSize: 11, color: _orangeColor, fontWeight: FontWeight.w600),
                        ),
                      if (guiaPetroleo.isNotEmpty)
                        const Text('⛽ Guía Petróleo', style: TextStyle(fontSize: 11, color: Colors.blueGrey)),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey, size: 18),
          ],
        ),
      ),
    );
  }

  void _mostrarDetalleCartola(RegistroMapa viaje, int numeroVuelta) {
    final fechaDt = _obtenerFechaViaje(viaje);
    final cliente = _safeString(viaje['clientes'], ['nombre_empresa', 'nombre', 'razon_social'], 'Origen');
    final destino = _safeString(viaje['consignatarios'], ['nombre_empresa', 'nombre', 'razon_social'], 'Destino');
    final region = _safeString(viaje['regiones'], ['nombre'], 'No especificada');
    final patente = _safeString(viaje['camiones'], ['patente'], 'S/P');

    final guia = (viaje['numero_guia'] ?? 'Sin Guía').toString();
    final pallets = (viaje['pallets'] ?? 0).toString();
    final guiaPetroleo = (viaje['guia_petroleo'] ?? 'No registrada').toString();
    final hNoct = (viaje['horas_nocturnas'] ?? 0).toString();
    final hSab = (viaje['horas_sabado'] ?? 0).toString();
    final obsConductor = (viaje['observaciones_conductor'] ?? '').toString();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Comprobante Operativo • Vuelta #$numeroVuelta',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _primaryColor),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(10)),
                      child: const Text(
                        'EN PLANILLA',
                        style: TextStyle(color: Color(0xFF15803D), fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                _filaFicha('Fecha y Hora Cierre', '${_formatearFechaCorta(fechaDt)} • ${_formatearHora(fechaDt)}'),
                _filaFicha('Número de Guía', guia),
                _filaFicha('Origen (Cliente)', cliente),
                _filaFicha('Destino (Consignatario)', destino),
                _filaFicha('Región / Zona', region),
                _filaFicha('Camión / Patente', patente),
                _filaFicha('Carga Transportada', '$pallets Pallets'),
                _filaFicha('Horas Nocturnas / Sábado', '$hNoct hrs noct.  |  $hSab hrs sáb.'),
                _filaFicha('Guía de Petróleo', guiaPetroleo.isEmpty ? 'No registrada' : guiaPetroleo),
                if (obsConductor.isNotEmpty)
                  _filaFicha('Observaciones', obsConductor),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cerrar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _filaFicha(String label, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 155,
            child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(
              valor,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _primaryColor),
            ),
          ),
        ],
      ),
    );
  }
}