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
  String _estadoRevisionAdmin = 'en_revision'; // 'en_revision', 'aprobado', 'rechazado'

  // Mes y año de cierre del ciclo seleccionado (El ciclo cierra el día 20 de este mes/año)
  late int _mesCierreCiclo;
  late int _anioCierreCiclo;

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

  /// Ciclo contable automático: del día 21 al día 20 del mes siguiente
  void _inicializarCicloActual() {
    final hoy = DateTime.now();
    if (hoy.day >= 21) {
      if (hoy.month == 12) {
        _mesCierreCiclo = 1;
        _anioCierreCiclo = hoy.year + 1;
      } else {
        _mesCierreCiclo = hoy.month + 1;
        _anioCierreCiclo = hoy.year;
      }
    } else {
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

  String _formatoDateSQL(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  void _cambiarCiclo(int deltaMeses) {
    setState(() {
      _rangoFechasPersonalizado = null;
      final nuevaFecha = DateTime(_anioCierreCiclo, _mesCierreCiclo + deltaMeses, 1);
      _mesCierreCiclo = nuevaFecha.month;
      _anioCierreCiclo = nuevaFecha.year;
    });
    _sincronizarRegistroPlanillaMensual();
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
          await _sincronizarRegistroPlanillaMensual();
        }
      }
    } catch (e) {
      debugPrint('Error cargando planilla: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sincronizarRegistroPlanillaMensual() async {
    if (_rutConductor == null) return;
    final online = await SyncHelper.tieneInternet();
    if (!online) return;

    try {
      final inicioSql = _formatoDateSQL(_inicioCicloSeleccionado);
      final finSql = _formatoDateSQL(_finCicloSeleccionado);

      final viajesDelCiclo = _todosViajesCompletados.where((v) {
        final f = _obtenerFechaViaje(v);
        return !f.isBefore(_inicioCicloSeleccionado) && !f.isAfter(_finCicloSeleccionado);
      }).length;

      final existente = await Supabase.instance.client
          .from('planillas_mensuales')
          .select()
          .eq('conductor_rut', _rutConductor!)
          .eq('inicio_ciclo', inicioSql)
          .eq('fin_ciclo', finSql)
          .maybeSingle();

      if (existente != null) {
        if ((existente['total_viajes'] ?? 0) != viajesDelCiclo) {
          await Supabase.instance.client
              .from('planillas_mensuales')
              .update({'total_viajes': viajesDelCiclo})
              .eq('id', existente['id']);
        }
        if (mounted) {
          setState(() {
            _estadoRevisionAdmin = (existente['estado'] ?? 'en_revision').toString();
          });
        }
      } else if (viajesDelCiclo > 0) {
        final insertada = await Supabase.instance.client
            .from('planillas_mensuales')
            .insert({
              'conductor_rut': _rutConductor,
              'inicio_ciclo': inicioSql,
              'fin_ciclo': finSql,
              'total_viajes': viajesDelCiclo,
              'monto_total': 0,
              'estado': 'en_revision',
            })
            .select()
            .single();

        if (mounted) {
          setState(() {
            _estadoRevisionAdmin = (insertada['estado'] ?? 'en_revision').toString();
          });
        }
      } else {
        if (mounted) setState(() => _estadoRevisionAdmin = 'en_revision');
      }
    } catch (e) {
      debugPrint('Aviso sincronizando tabla planillas_mensuales: $e');
    }
  }

  Future<void> _leerCompletadosDesdeSQLite(String rut) async {
    final completados = await DatabaseHelper.instance.obtenerViajesPorEstado(rut, 'completado');
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
      final guiaPet = (v['guia_petroleo'] ?? '').toString().toLowerCase();
      final cliente = _safeString(v['clientes'], ['nombre_empresa', 'nombre'], '').toLowerCase();
      final destino = _safeString(v['consignatarios'], ['nombre_empresa', 'nombre'], '').toLowerCase();
      final region = _safeString(v['regiones'], ['nombre'], '').toLowerCase();
      final patente = _safeString(v['camiones'], ['patente'], '').toLowerCase();

      return guia.contains(q) ||
          guiaPet.contains(q) ||
          cliente.contains(q) ||
          destino.contains(q) ||
          region.contains(q) ||
          patente.contains(q);
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

  String _formatearHoraIso(String? iso) {
    if (iso == null || iso.isEmpty) return '--:--';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '--:--';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} hrs';
  }

  String _formatearHoraDecimal(dynamic valor) {
    final numVal = (valor is num) ? valor.toDouble() : double.tryParse(valor?.toString() ?? '0') ?? 0.0;
    if (numVal <= 0) return 'No aplica';
    final int hora = numVal.floor();
    final int min = ((numVal - hora) * 100).round();
    return '${hora.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')} hrs';
  }

  @override
  Widget build(BuildContext context) {
    final listaCiclo = _viajesFiltrados;

    final int totalViajes = listaCiclo.length;
    int totalPallets = 0;
    int totalTags = 0;

    for (final v in listaCiclo) {
      totalPallets += (v['pallets'] is int)
          ? (v['pallets'] as int)
          : int.tryParse(v['pallets']?.toString() ?? '0') ?? 0;
      totalTags += (v['monto_tag'] is int)
          ? (v['monto_tag'] as int)
          : int.tryParse(v['monto_tag']?.toString() ?? '0') ?? 0;
    }

    final inicioCiclo = _inicioCicloSeleccionado;
    final finCiclo = _finCicloSeleccionado;

    String textoEstadoCiclo = 'CICLO ACTIVO (CIERRA EL DÍA 20)';
    Color colorEstadoCiclo = Colors.greenAccent;
    if (_estadoRevisionAdmin == 'aprobado') {
      textoEstadoCiclo = 'PLANILLA RENDIDA Y APROBADA';
      colorEstadoCiclo = Colors.greenAccent;
    } else if (_estadoRevisionAdmin == 'rechazado') {
      textoEstadoCiclo = 'PLANILLA CON OBSERVACIONES';
      colorEstadoCiclo = Colors.amberAccent;
    } else if (!_esCicloAbierto) {
      textoEstadoCiclo = 'CICLO CERRADO EL 20 • EN REVISIÓN';
      colorEstadoCiclo = Colors.orangeAccent;
    }

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
            tooltip: 'Sincronizar Planilla',
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
                  // 1. TARJETA SUPERIOR DE CICLO CONTABLE (21 AL 20)
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
                                color: Colors.white.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _esCicloAbierto ? Icons.autorenew : Icons.verified_outlined,
                                    size: 13,
                                    color: colorEstadoCiclo,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    textoEstadoCiclo,
                                    style: TextStyle(
                                      color: colorEstadoCiclo,
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
                                        : 'Ciclo: 21 ${_mesesCortos[inicioCiclo.month - 1]} ${inicioCiclo.year} al 20 ${_mesesCortos[finCiclo.month - 1]} ${finCiclo.year}',
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

                        // CONTADORES OPERATIVOS
                        Row(
                          children: [
                            _buildMetricaCiclo(
                              valor: totalViajes.toString().padLeft(2, '0'),
                              etiqueta: 'VUELTAS CICLO',
                              icono: Icons.local_shipping_outlined,
                              destacado: true,
                            ),
                            const SizedBox(width: 8),
                            _buildMetricaCiclo(
                              valor: totalPallets.toString(),
                              etiqueta: 'PALLETS',
                              icono: Icons.inventory_2_outlined,
                            ),
                            const SizedBox(width: 8),
                            _buildMetricaCiclo(
                              valor: totalTags.toString(),
                              etiqueta: 'TAGS TOTALES',
                              icono: Icons.toll,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 2. BUSCADOR Y SELECTOR DE FECHAS
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _buscadorCtrl,
                          onChanged: (val) => setState(() => _textoBusqueda = val),
                          decoration: InputDecoration(
                            hintText: 'Buscar por guía, cliente, destino o patente...',
                            hintStyle: const TextStyle(fontSize: 12.5, color: Colors.grey),
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

                  // 3. LISTADO TIPO CARTOLA
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'CARTOLA DE VIAJES (CLIENTE ➔ CONSIGNATARIO)',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: _primaryColor, letterSpacing: 0.4),
                      ),
                      Text(
                        '$totalViajes ${totalViajes == 1 ? "vuelta" : "vueltas"}',
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
                            'Al finalizar un viaje en Mis Viajes, se agregará automáticamente a esta planilla con todos sus datos.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  else
                    for (int idx = 0; idx < listaCiclo.length; idx++)
                      _buildItemCartola(listaCiclo[idx], totalViajes - idx),
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
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
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
              style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold),
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
    final cliente = _safeString(viaje['clientes'], ['nombre_empresa', 'nombre', 'razon_social'], 'Cliente Origen');
    final destino = _safeString(viaje['consignatarios'], ['nombre_empresa', 'nombre', 'razon_social'], 'Consignatario Destino');
    final region = _safeString(viaje['regiones'], ['nombre'], '');
    final patente = _safeString(viaje['camiones'], ['patente'], 'S/P');
    final tipoCamion = _safeString(viaje['camiones'], ['tipo_camion'], '');

    final guia = (viaje['numero_guia'] ?? 'S/G').toString();
    final pallets = (viaje['pallets'] ?? 0).toString();
    final guiaPetroleo = (viaje['guia_petroleo'] ?? '').toString();
    final hNoct = (viaje['horas_nocturnas'] is num)
        ? (viaje['horas_nocturnas'] as num).toDouble()
        : double.tryParse(viaje['horas_nocturnas']?.toString() ?? '0') ?? 0.0;
    final hSab = (viaje['horas_sabado'] is num)
        ? (viaje['horas_sabado'] as num).toDouble()
        : double.tryParse(viaje['horas_sabado']?.toString() ?? '0') ?? 0.0;
    final int cantTag = (viaje['monto_tag'] is num)
        ? (viaje['monto_tag'] as num).toInt()
        : int.tryParse(viaje['monto_tag']?.toString() ?? '0') ?? 0;
    final int cantPeonetas = (viaje['monto_peonetas'] is num)
        ? (viaje['monto_peonetas'] as num).toInt()
        : int.tryParse(viaje['monto_peonetas']?.toString() ?? '0') ?? 0;
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
            Container(
              width: 52,
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
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Text(
                        '🚛 $patente${tipoCamion.isNotEmpty ? " ($tipoCamion)" : ""}',
                        style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600),
                      ),
                      Text('📦 $pallets plts', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      if (region.isNotEmpty)
                        Text('📍 $region', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      if (hNoct > 0)
                        Text('🌙 Salida: ${_formatearHoraDecimal(hNoct)}', style: TextStyle(fontSize: 11, color: _orangeColor, fontWeight: FontWeight.w600)),
                      if (hSab > 0)
                        Text('📅 Sáb: ${_formatearHoraDecimal(hSab)}', style: TextStyle(fontSize: 11, color: _orangeColor, fontWeight: FontWeight.w600)),
                      if (guiaPetroleo.isNotEmpty)
                        Text('⛽ Guía Pet: $guiaPetroleo', style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
                      if (cantTag > 0)
                        Text('🛣️ $cantTag TAGs', style: const TextStyle(fontSize: 11, color: Colors.teal, fontWeight: FontWeight.w600)),
                      if (cantPeonetas > 0)
                        Text('👷 $cantPeonetas Peon.', style: const TextStyle(fontSize: 11, color: Colors.indigo, fontWeight: FontWeight.w600)),
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

  /// Modal con TODOS los datos relevantes de la tabla `viajes`
  void _mostrarDetalleCartola(RegistroMapa viaje, int numeroVuelta) {
    final fechaDt = _obtenerFechaViaje(viaje);
    final cliente = _safeString(viaje['clientes'], ['nombre_empresa', 'nombre', 'razon_social'], 'Cliente Origen');
    final clienteDir = _safeString(viaje['clientes'], ['direccion', 'ubicacion'], 'Sin dirección');
    final destino = _safeString(viaje['consignatarios'], ['nombre_empresa', 'nombre', 'razon_social'], 'Consignatario Destino');
    final destinoDir = _safeString(viaje['consignatarios'], ['direccion', 'ubicacion'], 'Sin dirección');
    final region = _safeString(viaje['regiones'], ['nombre'], 'No especificada');
    final patente = _safeString(viaje['camiones'], ['patente'], 'S/P');
    final tipoCamion = _safeString(viaje['camiones'], ['tipo_camion'], 'Estándar');

    final guia = (viaje['numero_guia'] ?? 'Sin Guía').toString();
    final pallets = (viaje['pallets'] ?? 0).toString();
    final guiaPetroleo = (viaje['guia_petroleo'] ?? '').toString();
    final horaCargaProg = (viaje['hora_carga'] ?? '--:--').toString();
    final horaDescargaProg = (viaje['hora_descarga'] ?? '--:--').toString();
    final horaInicioReal = _formatearHoraIso(viaje['iniciado_en']?.toString());
    final horaFinReal = _formatearHoraIso(viaje['finalizado_en']?.toString());

    final obsConductor = (viaje['observaciones_conductor'] ?? '').toString();
    final obsAdmin = (viaje['observaciones_admin'] ?? '').toString();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Ficha de Planilla • Vuelta #$numeroVuelta',
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
                  const Divider(height: 22),
                  _filaFicha('Fecha del Viaje', _formatearFechaCorta(fechaDt)),
                  _filaFicha('Número de Guía', guia),
                  _filaFicha('Desde (Cliente Origen)', '$cliente\n$clienteDir'),
                  _filaFicha('Hacia (Consignatario)', '$destino\n$destinoDir'),
                  _filaFicha('Región Operativa', region),
                  _filaFicha('Camión / Tipo', '$patente ($tipoCamion)'),
                  _filaFicha('Pallets Movilizados', '$pallets Pallets'),
                  _filaFicha('Horario Programado', 'Carga: $horaCargaProg  |  Descarga: $horaDescargaProg'),
                  _filaFicha('Inicio / Fin Real', 'Inicio: $horaInicioReal  |  Cierre: $horaFinReal'),
                  _filaFicha(
                    'Salida Nocturna / Sábado',
                    'Nocturna: ${_formatearHoraDecimal(viaje['horas_nocturnas'])}  |  Sábado: ${_formatearHoraDecimal(viaje['horas_sabado'])}',
                  ),
                  _filaFicha('Guía de Petróleo', guiaPetroleo.isEmpty ? 'No registrada' : guiaPetroleo),
                  _filaFicha(
                    'TAGs / Peonetas',
                    'TAGs: ${viaje['monto_tag'] ?? 0} unid.  |  Peonetas: ${viaje['monto_peonetas'] ?? 0} unid.',
                  ),
                  if (obsConductor.isNotEmpty)
                    _filaFicha('Obs. Conductor', obsConductor),
                  if (obsAdmin.isNotEmpty)
                    _filaFicha('Notas Despacho Admin', obsAdmin),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryColor,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cerrar Ficha', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
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
            width: 150,
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