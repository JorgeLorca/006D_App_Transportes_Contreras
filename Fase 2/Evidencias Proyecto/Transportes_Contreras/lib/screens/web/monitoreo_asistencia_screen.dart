import 'package:flutter/material.dart';

import '../../models/registro_asistencia.dart';
import '../../repositories/asistencia_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/admin_shell.dart';
import '../../widgets/paginacion_tabla.dart';
import '../../widgets/stat_card.dart';

/// Monitoreo de asistencia: lista de los eventos que marcan los conductores
/// (conductor, tipo, fecha y hora). La tabla guarda períodos de 45 días y
/// luego se limpia, por eso la lista muestra todo lo que haya en ella.
class MonitoreoAsistenciaScreen extends StatefulWidget {
  const MonitoreoAsistenciaScreen({super.key});

  @override
  State<MonitoreoAsistenciaScreen> createState() => _MonitoreoAsistenciaScreenState();
}

class _MonitoreoAsistenciaScreenState extends State<MonitoreoAsistenciaScreen> {
  static const _registrosPorPagina = 10;

  /// Ancho relativo de las columnas: conductor, tipo, fecha, hora.
  static const _flex = [5, 2, 3, 2];

  final _repo = AsistenciaRepository();
  final ScrollController _tablaScrollController = ScrollController();

  List<RegistroAsistencia> _registros = [];
  bool _cargando = true;
  String? _error;
  String _busqueda = '';
  int _pagina = 0;
  DateTime _fechaSeleccionada = DateTime.now();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _tablaScrollController.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final datos = await _repo.obtenerTodos();
      if (!mounted) return;
      setState(() {
        _registros = datos;
        _cargando = false;
        _pagina = 0;
      });
    } catch (e) {
      debugPrint('Error cargando asistencia: $e');
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar la asistencia: $e';
      });
    }
  }

  bool _mismoDia(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  List<RegistroAsistencia> get _filtrados {
    final texto = _normalizar(_busqueda.trim());
    return _registros.where((r) {
      if (!_mismoDia(r.horaEvento, _fechaSeleccionada)) return false;
      if (texto.isNotEmpty) {
        return _normalizar(r.conductorNombre).contains(texto) ||
            _normalizar(r.conductorRut).contains(texto);
      }
      return true;
    }).toList();
  }

  Future<void> _seleccionarFecha() async {
    final now = DateTime.now();
    final elegida = await showDatePicker(
      context: context,
      initialDate: _fechaSeleccionada,
      firstDate: DateTime(2024),
      lastDate: DateTime(now.year + 2),
      helpText: 'Seleccionar día de asistencia',
      cancelText: 'CANCELAR',
      confirmText: 'ACEPTAR',
      locale: const Locale('es', 'CL'),
    );
    if (elegida != null) {
      setState(() {
        _fechaSeleccionada = elegida;
        _pagina = 0;
      });
    }
  }

  String get _rotuloFecha {
    final hoy = DateTime.now();
    final fechaFmt = '${_dos(_fechaSeleccionada.day)}/${_dos(_fechaSeleccionada.month)}/${_fechaSeleccionada.year}';
    if (_mismoDia(_fechaSeleccionada, hoy)) {
      return 'Hoy ($fechaFmt)';
    }
    return fechaFmt;
  }

  static String _normalizar(String s) =>
      s.toLowerCase().replaceAll('á', 'a').replaceAll('é', 'e').replaceAll('í', 'i').replaceAll('ó', 'o').replaceAll('ú', 'u').replaceAll('ñ', 'n');

  static String _dos(int n) => n.toString().padLeft(2, '0');
  static String _fecha(DateTime d) => '${_dos(d.day)}-${_dos(d.month)}-${d.year}';
  static String _hora(DateTime d) => '${_dos(d.hour)}:${_dos(d.minute)}';

  @override
  Widget build(BuildContext context) {
    final filtrados = _filtrados;
    final conductores = filtrados.map((r) => r.conductorRut).toSet().length;
    final totalPaginas = filtrados.isEmpty ? 1 : (filtrados.length / _registrosPorPagina).ceil();
    final pagina = _pagina >= totalPaginas ? totalPaginas - 1 : _pagina;
    final visibles = filtrados.skip(pagina * _registrosPorPagina).take(_registrosPorPagina).toList();
    final bool esPantallaPequena = MediaQuery.of(context).size.width < 750;

    return AdminShell(
      selectedIndex: 16,
      title: 'Monitoreo de asistencia',
      subtitle: 'Revise las marcas de asistencia de los conductores.',
      eyebrowIcon: Icons.fact_check_outlined,
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: esPantallaPequena ? 16 : 32, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildControles(),
            const SizedBox(height: 24),
            _buildMetricas(filtrados.length, conductores),
            const SizedBox(height: 24),
            _buildTabla(visibles, filtrados.length, pagina),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- arriba

  Widget _buildControles() {
    return LayoutBuilder(builder: (context, constraints) {
      final ancho = constraints.maxWidth > 800;
      final ciclo = _buildCiclo();
      final busqueda = _buildBusqueda();
      if (ancho) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [ciclo, const SizedBox(width: 24), Expanded(child: busqueda)],
        );
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [ciclo, const SizedBox(height: 12), busqueda]);
    });
  }

  Widget _buildCiclo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'DÍA DE ASISTENCIA',
          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: _seleccionarFecha,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.calendar_today_outlined, size: 16, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  _rotuloFecha,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBusqueda() {
    OutlineInputBorder borde(Color c) => OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c));
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 42,
            child: TextField(
              onChanged: (v) => setState(() {
                _busqueda = v;
                _pagina = 0;
              }),
              textAlignVertical: TextAlignVertical.center,
              style: const TextStyle(fontSize: 13.5, color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Buscar conductor o RUT...',
                hintStyle: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary),
                prefixIcon: const Icon(Icons.search, size: 18, color: AppColors.textSecondary),
                filled: true,
                fillColor: Colors.white,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                border: borde(AppColors.border),
                enabledBorder: borde(AppColors.border),
                focusedBorder: borde(AppColors.primary),
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Refrescar',
          icon: const Icon(Icons.refresh, size: 20, color: AppColors.textSecondary),
          onPressed: _cargando ? null : _cargar,
        ),
      ],
    );
  }

  Widget _buildMetricas(int registros, int conductores) {
    return LayoutBuilder(builder: (context, constraints) {
      final ancho = constraints.maxWidth > 700 ? (constraints.maxWidth - 16) / 2 : double.infinity;
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          SizedBox(
            width: ancho,
            child: StatCard(
              label: 'Registros del día',
              value: '$registros',
              icon: Icons.history,
              iconColor: AppColors.primary,
            ),
          ),
          SizedBox(
            width: ancho,
            child: StatCard(
              label: 'Conductores con registro',
              value: '$conductores',
              icon: Icons.groups_outlined,
              iconColor: AppColors.success,
            ),
          ),
        ],
      );
    });
  }

  // ----------------------------------------------------------------- tabla

  Widget _buildTabla(List<RegistroAsistencia> visibles, int total, int pagina) {
    final Widget cuerpo;
    if (_cargando) {
      cuerpo = const Padding(
        padding: EdgeInsets.symmetric(vertical: 56),
        child: Center(child: CircularProgressIndicator(strokeWidth: 3)),
      );
    } else if (_error != null) {
      cuerpo = _buildError();
    } else if (total == 0) {
      cuerpo = Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
        child: Center(
          child: Column(
            children: [
              const Icon(Icons.event_busy_outlined, size: 32, color: AppColors.textSecondary),
              const SizedBox(height: 10),
              Text(
                _busqueda.trim().isNotEmpty
                    ? 'Ningún conductor coincide con la búsqueda para este día.'
                    : 'No hay registros de asistencia para $_rotuloFecha.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    } else {
      cuerpo = Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final bool usarScrollLateral = constraints.maxWidth < 720;
              final Widget contenidoTabla = Column(
                children: [
                  _buildCabecera(),
                  for (final r in visibles) _buildFila(r),
                ],
              );

              if (usarScrollLateral) {
                return Scrollbar(
                  controller: _tablaScrollController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _tablaScrollController,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: 680,
                      child: contenidoTabla,
                    ),
                  ),
                );
              }
              return contenidoTabla;
            },
          ),
          PaginacionTabla(
            total: total,
            pagina: pagina,
            porPagina: _registrosPorPagina,
            onCambiarPagina: (p) => setState(() => _pagina = p),
          ),
        ],
      );
    }

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            color: AppColors.surfaceMuted,
            child: const Text(
              'Registros recientes',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
          ),
          cuerpo,
        ],
      ),
    );
  }

  Widget _celda(int i, Widget hijo) => Expanded(flex: _flex[i], child: hijo);

  Widget _buildCabecera() {
    const estilo = TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: AppColors.textSecondary);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
      child: Row(
        children: [
          _celda(0, const Text('CONDUCTOR', style: estilo)),
          _celda(1, const Text('TIPO', style: estilo)),
          _celda(2, const Text('FECHA', style: estilo)),
          _celda(3, const Text('HORA', style: estilo)),
        ],
      ),
    );
  }

  Widget _buildFila(RegistroAsistencia r) {
    final fechaEvento = r.horaEvento;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
      child: Row(
        children: [
          _celda(0, _buildConductor(r.conductorNombre)),
          _celda(1, Align(alignment: Alignment.centerLeft, child: _buildTipo(r.tipoEvento))),
          _celda(2, _datoConIcono(Icons.calendar_today_outlined, _fecha(fechaEvento))),
          _celda(3, _datoConIcono(Icons.schedule, _hora(fechaEvento))),
        ],
      ),
    );
  }

  Widget _buildTipo(String tipo) {
    final esEntrada = tipo.toLowerCase() == 'entrada';
    final esSalida = tipo.toLowerCase() == 'salida';
    final color = esEntrada ? AppColors.success : (esSalida ? AppColors.primary : AppColors.textSecondary);
    final texto = esEntrada ? 'Entrada' : (esSalida ? 'Salida' : (tipo.isEmpty ? '—' : tipo));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(esEntrada ? Icons.login : (esSalida ? Icons.logout : Icons.circle), size: 12, color: color),
          const SizedBox(width: 5),
          Text(texto, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }

  Widget _datoConIcono(IconData icono, String texto) {
    return Row(
      children: [
        Icon(icono, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            texto,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          ),
        ),
      ],
    );
  }

  Widget _buildConductor(String nombre) {
    return Row(
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: AppColors.surfaceMuted,
          child: Text(
            _iniciales(nombre),
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textSecondary),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            nombre,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          ),
        ),
      ],
    );
  }

  static String _iniciales(String nombre) {
    final partes = nombre.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (partes.isEmpty) return '?';
    if (partes.length == 1) return partes.first[0].toUpperCase();
    return (partes[0][0] + partes[1][0]).toUpperCase();
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 13))),
            TextButton(onPressed: _cargando ? null : _cargar, child: const Text('REINTENTAR')),
          ],
        ),
      ),
    );
  }
}