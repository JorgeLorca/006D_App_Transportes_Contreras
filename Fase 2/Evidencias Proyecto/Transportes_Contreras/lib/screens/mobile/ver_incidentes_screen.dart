import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../local_db/database_helper.dart';
import '../../local_db/sync_helper.dart';
import 'incidentes_screen.dart';

class VerIncidentesScreen extends StatefulWidget {
  const VerIncidentesScreen({super.key});

  @override
  State<VerIncidentesScreen> createState() => _VerIncidentesScreenState();
}

class _VerIncidentesScreenState extends State<VerIncidentesScreen> {
  bool _isLoading = true;
  String? _rutConductor;
  String _filtroTipo = 'todos'; // todos, accidente, falla_mecanica, retraso

  late int _mesCierreCiclo;
  late int _anioCierreCiclo;

  ListaRegistros _todosIncidentes = [];

  final Color _primaryColor = const Color(0xFF0F172A);
  final Color _orangeColor = const Color(0xFFE67E22);
  final Color _redColor = const Color(0xFFDC2626);
  final Color _amberColor = const Color(0xFFD97706);

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
    _cargarIncidentes();
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

  void _cambiarCiclo(int deltaMeses) {
    setState(() {
      final nuevaFecha = DateTime(_anioCierreCiclo, _mesCierreCiclo + deltaMeses, 1);
      _mesCierreCiclo = nuevaFecha.month;
      _anioCierreCiclo = nuevaFecha.year;
    });
  }

  String _normalizarTipo(String raw) {
    final t = raw.toLowerCase().trim();
    if (t.contains('accidente')) return 'accidente';
    if (t.contains('falla') || t.contains('mecan') || t.contains('mecán') || t.contains('pana')) {
      return 'falla_mecanica';
    }
    return 'retraso';
  }

  DateTime _obtenerFechaIncidente(RegistroMapa item) {
    final raw = (item['reportado_en'] ?? '').toString();
    final dt = DateTime.tryParse(raw)?.toLocal();
    return dt ?? DateTime.now();
  }

  Future<void> _cargarIncidentes() async {
    if (!mounted) return;
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

      if (_rutConductor != null) {
        await SyncHelper.sincronizarTodo(_rutConductor!);
      }

      final Map<String, RegistroMapa> mapaConsolidado = {};

      // 1. Cargar incidentes locales de SQLite del conductor (incluye offline pendientes)
      if (_rutConductor != null) {
        final locales = await DatabaseHelper.instance.obtenerHistorialIncidentes(_rutConductor!);
        for (final item in locales) {
          final id = (item['id'] ?? '').toString();
          if (id.isEmpty) continue;
          mapaConsolidado[id] = {
            ...RegistroMapa.from(item),
            'conductor_nombre': 'Mi reporte',
            'is_synced': item['is_synced'] ?? 0,
          };
        }
      }

      // 2. Consultar en Supabase: globales de tipo accidente + todos los propios del conductor
      final filtroOr = (_rutConductor != null && _rutConductor!.isNotEmpty)
          ? 'tipo_incidente.ilike.%accidente%,conductor_rut.eq.$_rutConductor'
          : 'tipo_incidente.ilike.%accidente%';

      final List remotos = await Supabase.instance.client
          .from('incidentes')
          .select('*, conductores(nombre_completo)')
          .or(filtroOr)
          .order('reportado_en', ascending: false);

      for (final raw in remotos) {
        if (raw is! Map) continue;
        final reg = RegistroMapa.from(raw);
        final id = (reg['id'] ?? '').toString();
        if (id.isEmpty) continue;

        final condData = reg['conductores'];
        String nombreCond = (reg['conductor_rut'] ?? 'Conductor').toString();
        if (condData is Map && condData['nombre_completo'] != null) {
          nombreCond = condData['nombre_completo'].toString();
        }

        mapaConsolidado[id] = {
          ...reg,
          'conductor_nombre': nombreCond,
          'is_synced': 1,
        };
      }

      final ListaRegistros listaFinal = mapaConsolidado.values.toList();

      listaFinal.sort((a, b) {
        final fA = _obtenerFechaIncidente(a);
        final fB = _obtenerFechaIncidente(b);
        return fB.compareTo(fA);
      });

      if (mounted) {
        setState(() {
          _todosIncidentes = listaFinal;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error cargando incidentes: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  ListaRegistros get _incidentesDelCiclo {
    final inicio = _inicioCicloSeleccionado;
    final fin = _finCicloSeleccionado;

    return _todosIncidentes.where((i) {
      final fecha = _obtenerFechaIncidente(i);
      return !fecha.isBefore(inicio) && !fecha.isAfter(fin);
    }).toList();
  }

  ListaRegistros get _incidentesFiltrados {
    final delCiclo = _incidentesDelCiclo;
    if (_filtroTipo == 'todos') return delCiclo;
    return delCiclo
        .where((i) => _normalizarTipo((i['tipo_incidente'] ?? '').toString()) == _filtroTipo)
        .toList();
  }

  String _formatearFechaHora(String? iso) {
    if (iso == null || iso.isEmpty) return '--/--/---- • --:-- hrs';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return iso;
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year;
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$d/$m/$y • $h:$min hrs';
  }

  Future<void> _abrirMapaIncidente(RegistroMapa item) async {
    final double? lat = (item['latitud'] is num)
        ? (item['latitud'] as num).toDouble()
        : double.tryParse(item['latitud']?.toString() ?? '');
    final double? lng = (item['longitud'] is num)
        ? (item['longitud'] as num).toDouble()
        : double.tryParse(item['longitud']?.toString() ?? '');

    if (lat == null || lng == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Este incidente no tiene coordenadas GPS registradas.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir la aplicación de mapas.')),
      );
    }
  }

  void _verFotoIncidente(RegistroMapa item) {
    final String urlRemota = (item['url_evidencia_fotografica'] ?? '').toString().trim();
    final String rutaLocal = (item['local_path_evidencia'] ?? '').toString().trim();

    final bool esUrlHttp = urlRemota.startsWith('http://') || urlRemota.startsWith('https://');
    final String pathArchivoLocal = rutaLocal.isNotEmpty
        ? rutaLocal
        : (!esUrlHttp && urlRemota.isNotEmpty ? urlRemota : '');

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Evidencia Fotográfica',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _primaryColor),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Container(
              constraints: const BoxConstraints(maxHeight: 420),
              width: double.infinity,
              color: Colors.black,
              child: esUrlHttp
                  ? InteractiveViewer(
                      child: Image.network(
                        urlRemota,
                        fit: BoxFit.contain,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return const SizedBox(
                            height: 220,
                            child: Center(child: CircularProgressIndicator(color: Colors.white)),
                          );
                        },
                        errorBuilder: (_, __, ___) => const SizedBox(
                          height: 200,
                          child: Center(
                            child: Text(
                              'No se pudo cargar la imagen desde el servidor.',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ),
                        ),
                      ),
                    )
                  : (pathArchivoLocal.isNotEmpty && File(pathArchivoLocal).existsSync())
                      ? InteractiveViewer(
                          child: Image.file(
                            File(pathArchivoLocal),
                            fit: BoxFit.contain,
                          ),
                        )
                      : const SizedBox(
                          height: 200,
                          child: Center(
                            child: Text(
                              'Imagen no disponible en el dispositivo.',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ),
                        ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cerrar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final listaCiclo = _incidentesDelCiclo;

    final int countAccidentes = listaCiclo
        .where((i) => _normalizarTipo((i['tipo_incidente'] ?? '').toString()) == 'accidente')
        .length;
    final int countFallas = listaCiclo
        .where((i) => _normalizarTipo((i['tipo_incidente'] ?? '').toString()) == 'falla_mecanica')
        .length;
    final int countRetrasos = listaCiclo
        .where((i) => _normalizarTipo((i['tipo_incidente'] ?? '').toString()) == 'retraso')
        .length;

    final filtrados = _incidentesFiltrados;
    final inicioCiclo = _inicioCicloSeleccionado;
    final finCiclo = _finCicloSeleccionado;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: _primaryColor,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          tooltip: 'Volver',
          onPressed: () => Navigator.pop(context),
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TRANSPORTES CONTRERAS',
              style: TextStyle(
                fontSize: 10,
                color: Colors.white70,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
            Text(
              'Incidentes en Ruta',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Recargar incidentes',
            onPressed: _cargarIncidentes,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _redColor,
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const IncidentesScreen()),
          ).then((_) => _cargarIncidentes());
        },
        icon: const Icon(Icons.add_alert_rounded, color: Colors.white),
        label: const Text(
          'Reportar',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: _orangeColor))
          : RefreshIndicator(
              color: _orangeColor,
              onRefresh: _cargarIncidentes,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. SELECTOR DE CICLO CONTABLE (DÍA 21 AL 20)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _primaryColor,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
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
                                      _esCicloAbierto ? Icons.autorenew : Icons.history,
                                      size: 13,
                                      color: _esCicloAbierto ? Colors.greenAccent : Colors.orangeAccent,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      _esCicloAbierto ? 'CICLO EN CURSO (21 AL 20)' : 'CICLO ANTERIOR CERRADO',
                                      style: TextStyle(
                                        color: _esCicloAbierto ? Colors.greenAccent : Colors.orangeAccent,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                'Histórico: ${_todosIncidentes.length}',
                                style: const TextStyle(color: Colors.white60, fontSize: 11),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
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
                                      'Período ${_nombresMeses[_mesCierreCiclo - 1]} $_anioCierreCiclo',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 17,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Ciclo: 21 ${_mesesCortos[inicioCiclo.month - 1]} ${inicioCiclo.year} al 20 ${_mesesCortos[finCiclo.month - 1]} ${finCiclo.year}',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Color(0xFFE67E22),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
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
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // 2. 3 CARDS CON CONTADORES DEL CICLO ACTUAL
                    Row(
                      children: [
                        Expanded(
                          child: _buildContadorCard(
                            tipoKey: 'accidente',
                            titulo: 'ACCIDENTES',
                            cantidad: countAccidentes,
                            colorTexto: _redColor,
                            colorFondo: const Color(0xFFFEE2E2),
                            colorBorde: const Color(0xFFFCA5A5),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildContadorCard(
                            tipoKey: 'falla_mecanica',
                            titulo: 'FALLA MEC.',
                            cantidad: countFallas,
                            colorTexto: _amberColor,
                            colorFondo: const Color(0xFFFEF3C7),
                            colorBorde: const Color(0xFFFCD34D),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildContadorCard(
                            tipoKey: 'retraso',
                            titulo: 'RETRASOS',
                            cantidad: countRetrasos,
                            colorTexto: _orangeColor,
                            colorFondo: const Color(0xFFFFEDD5),
                            colorBorde: const Color(0xFFFDBA74),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            _filtroTipo == 'todos'
                                ? 'ALERTAS GLOBALES Y MIS REPORTES'
                                : 'FILTRADO POR: ${_tituloFiltro(_filtroTipo)}',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                        if (_filtroTipo != 'todos')
                          GestureDetector(
                            onTap: () => setState(() => _filtroTipo = 'todos'),
                            child: Text(
                              'Ver todos (${listaCiclo.length})',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _primaryColor,
                              ),
                            ),
                          )
                        else
                          Text(
                            'TOTAL: ${filtrados.length}',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    if (filtrados.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: const Column(
                          children: [
                            Icon(Icons.check_circle_outline, size: 38, color: Colors.grey),
                            SizedBox(height: 10),
                            Text(
                              'No hay incidentes registrados en este ciclo.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey, fontSize: 13),
                            ),
                          ],
                        ),
                      )
                    else
                      for (final item in filtrados) _buildTarjetaIncidente(item),
                  ],
                ),
              ),
            ),
    );
  }

  String _tituloFiltro(String tipo) {
    switch (tipo) {
      case 'accidente':
        return 'ACCIDENTES';
      case 'falla_mecanica':
        return 'FALLAS MECÁNICAS';
      case 'retraso':
        return 'RETRASOS';
      default:
        return 'TODOS';
    }
  }

  Widget _buildContadorCard({
    required String tipoKey,
    required String titulo,
    required int cantidad,
    required Color colorTexto,
    required Color colorFondo,
    required Color colorBorde,
  }) {
    final bool seleccionado = _filtroTipo == tipoKey;

    return GestureDetector(
      onTap: () {
        setState(() {
          _filtroTipo = seleccionado ? 'todos' : tipoKey;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: colorFondo,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: seleccionado ? colorTexto : colorBorde,
            width: seleccionado ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titulo,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colorTexto,
                fontSize: 10.5,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              cantidad.toString().padLeft(2, '0'),
              style: TextStyle(
                color: colorTexto,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTarjetaIncidente(RegistroMapa item) {
    final tipoNorm = _normalizarTipo((item['tipo_incidente'] ?? '').toString());
    final gravedad = (item['gravedad'] ?? 'Moderada').toString().toUpperCase();
    final descripcion = (item['descripcion'] ?? 'Sin detalle').toString();
    final fechaHora = _formatearFechaHora(item['reportado_en']?.toString());
    final bool isSynced = (item['is_synced'] ?? 1) == 1;
    final bool esPropio = _rutConductor != null &&
        (item['conductor_rut'] ?? '').toString().trim() == _rutConductor!.trim();
    final conductorNombre = esPropio
        ? 'Tú (${item['conductor_nombre'] ?? 'Mi reporte'})'
        : (item['conductor_nombre'] ?? 'Conductor').toString();

    final bool tieneCoordenadas = item['latitud'] != null && item['longitud'] != null;
    final String urlFoto = (item['url_evidencia_fotografica'] ?? '').toString().trim();
    final String localFoto = (item['local_path_evidencia'] ?? '').toString().trim();
    final bool tieneFoto = urlFoto.isNotEmpty || localFoto.isNotEmpty;

    Color badgeColor;
    Color cardBgColor;
    Color cardBorderColor;
    String badgeTexto;

    if (tipoNorm == 'accidente') {
      badgeColor = const Color(0xFFDC2626);
      cardBgColor = const Color(0xFFFEF2F2);
      cardBorderColor = const Color(0xFFFECACA);
      badgeTexto = 'ACCIDENTE EN RUTA';
    } else if (tipoNorm == 'falla_mecanica') {
      badgeColor = const Color(0xFFD97706);
      cardBgColor = const Color(0xFFFFFBEB);
      cardBorderColor = const Color(0xFFFDE68A);
      badgeTexto = 'FALLA MECÁNICA';
    } else {
      badgeColor = const Color(0xFFEA580C);
      cardBgColor = const Color(0xFFFFF7ED);
      cardBorderColor = const Color(0xFFFED7AA);
      badgeTexto = 'RETRASO OPERATIVO';
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cardBorderColor, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  badgeTexto,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '• $gravedad',
                style: TextStyle(
                  color: badgeColor,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
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

          const SizedBox(height: 10),

          Text(
            'Conductor: $conductorNombre',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.bold,
              color: _primaryColor,
            ),
          ),

          const SizedBox(height: 4),

          Text(
            descripcion,
            style: const TextStyle(
              fontSize: 12.5,
              color: Color(0xFF334155),
              height: 1.35,
            ),
          ),

          const SizedBox(height: 10),

          Row(
            children: [
              const Icon(Icons.access_time, size: 13, color: Color(0xFF64748B)),
              const SizedBox(width: 4),
              Text(
                fechaHora,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),

          if (tieneCoordenadas || tieneFoto) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Divider(height: 1, color: Colors.black12),
            ),
            Row(
              children: [
                if (tieneCoordenadas)
                  TextButton.icon(
                    onPressed: () => _abrirMapaIncidente(item),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.map_outlined, size: 16, color: Color(0xFF475569)),
                    label: const Text(
                      'Ver Mapa',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF475569),
                      ),
                    ),
                  ),
                if (tieneCoordenadas && tieneFoto) const SizedBox(width: 12),
                if (tieneFoto)
                  TextButton.icon(
                    onPressed: () => _verFotoIncidente(item),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: Icon(Icons.image_outlined, size: 16, color: badgeColor),
                    label: Text(
                      'Ver Foto',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: badgeColor,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}