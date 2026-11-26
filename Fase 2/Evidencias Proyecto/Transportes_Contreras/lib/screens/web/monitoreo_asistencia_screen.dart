import 'package:flutter/material.dart';

import '../../models/registro_asistencia.dart';
import '../../repositories/asistencia_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/admin_shell.dart';
import '../../widgets/page_hero_banner.dart';
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
  int _pagina = 0;

  // Filtros aplicados (los que realmente filtran la tabla).
  String _busqueda = '';
  String _tipoAplicado = 'todos';
  DateTime _fechaSeleccionada = DateTime.now();

  // Valores del formulario (se aplican al presionar "Buscar").
  final TextEditingController _busquedaCtrl = TextEditingController();
  String _tipoForm = 'todos';
  DateTime _fechaForm = DateTime.now();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _tablaScrollController.dispose();
    _busquedaCtrl.dispose();
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
      if (_tipoAplicado != 'todos' && r.tipoEvento.toLowerCase() != _tipoAplicado) return false;
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
      initialDate: _fechaForm,
      firstDate: DateTime(2024),
      lastDate: DateTime(now.year + 2),
      helpText: 'Seleccionar día de asistencia',
      cancelText: 'CANCELAR',
      confirmText: 'ACEPTAR',
      locale: const Locale('es', 'CL'),
    );
    if (elegida != null) setState(() => _fechaForm = elegida);
  }

  void _aplicarFiltros() {
    setState(() {
      _fechaSeleccionada = _fechaForm;
      _busqueda = _busquedaCtrl.text;
      _tipoAplicado = _tipoForm;
      _pagina = 0;
    });
  }

  void _limpiarFiltros() {
    final hoy = DateTime.now();
    _busquedaCtrl.clear();
    setState(() {
      _fechaForm = hoy;
      _fechaSeleccionada = hoy;
      _tipoForm = 'todos';
      _tipoAplicado = 'todos';
      _busqueda = '';
      _pagina = 0;
    });
  }

  String _rotuloDe(DateTime fecha) {
    final fechaFmt = '${_dos(fecha.day)}/${_dos(fecha.month)}/${fecha.year}';
    return _mismoDia(fecha, DateTime.now()) ? 'Hoy ($fechaFmt)' : fechaFmt;
  }

  String get _rotuloFecha => _rotuloDe(_fechaSeleccionada);

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
        padding: EdgeInsets.symmetric(horizontal: esPantallaPequena ? 16 : 24, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PageHeroBanner(
              icon: Icons.calendar_month_rounded,
              watermarkIcon: Icons.calendar_month_rounded,
              title: 'Monitoreo de Asistencia',
              subtitle: 'Revise las marcas de asistencia de los conductores.',
            ),
            const SizedBox(height: 24),
            _buildMetricas(filtrados.length, conductores),
            const SizedBox(height: 24),
            const SeccionTitulo('Filtros de Búsqueda'),
            const SizedBox(height: 12),
            _buildFiltros(),
            const SizedBox(height: 16),
            _buildTabla(visibles, filtrados.length, pagina),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------- filtros

  static const _campoFondo = Color(0xFFF4F6FA);

  Widget _etiqueta(String texto, Widget campo) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(texto, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        campo,
      ],
    );
  }

  BoxDecoration get _campoDeco => BoxDecoration(
        color: _campoFondo,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      );

  Widget _buildFiltros() {
    final fecha = _etiqueta(
      'Fecha',
      InkWell(
        onTap: _seleccionarFecha,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: _campoDeco,
          child: Row(
            children: [
              const Icon(Icons.calendar_today_outlined, size: 18, color: AppColors.textPrimary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _rotuloDe(_fechaForm),
                  style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                ),
              ),
              const Icon(Icons.keyboard_arrow_down, size: 20, color: AppColors.textPrimary),
            ],
          ),
        ),
      ),
    );

    final busqueda = _etiqueta(
      'Rut o Nombre',
      Container(
        height: 44,
        decoration: _campoDeco,
        child: TextField(
          controller: _busquedaCtrl,
          onSubmitted: (_) => _aplicarFiltros(),
          textAlignVertical: TextAlignVertical.center,
          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
          decoration: const InputDecoration(
            hintText: 'Buscar por rut o nombre...',
            hintStyle: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            prefixIcon: Icon(Icons.person_outline, size: 20, color: AppColors.textPrimary),
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
    );

    final tipo = _etiqueta(
      'Tipo de marca',
      Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: _campoDeco,
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _tipoForm,
            isExpanded: true,
            icon: const Icon(Icons.keyboard_arrow_down, size: 20, color: AppColors.textPrimary),
            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
            borderRadius: BorderRadius.circular(10),
            items: const [
              DropdownMenuItem(value: 'todos', child: _ItemTipo(Icons.check_circle_outline, 'Todos')),
              DropdownMenuItem(value: 'entrada', child: _ItemTipo(Icons.login, 'Entrada')),
              DropdownMenuItem(value: 'salida', child: _ItemTipo(Icons.logout, 'Salida')),
            ],
            onChanged: (v) => setState(() => _tipoForm = v ?? 'todos'),
          ),
        ),
      ),
    );

    final botonBuscar = ElevatedButton.icon(
      onPressed: _cargando ? null : _aplicarFiltros,
      icon: const Icon(Icons.search, size: 18, color: Colors.white),
      label: const Text('Buscar', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        elevation: 0,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
    );

    final botonLimpiar = OutlinedButton.icon(
      onPressed: _limpiarFiltros,
      icon: const Icon(Icons.refresh, size: 18, color: AppColors.textPrimary),
      label: const Text('Limpiar', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        side: const BorderSide(color: Color(0xFF94A3B8)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: sombraTarjeta,
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth > 900) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(flex: 4, child: fecha),
              const SizedBox(width: 20),
              Expanded(flex: 5, child: busqueda),
              const SizedBox(width: 20),
              Expanded(flex: 4, child: tipo),
              const SizedBox(width: 20),
              botonBuscar,
              const SizedBox(width: 12),
              botonLimpiar,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            fecha,
            const SizedBox(height: 16),
            busqueda,
            const SizedBox(height: 16),
            tipo,
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(child: botonBuscar),
                const SizedBox(width: 12),
                Expanded(child: botonLimpiar),
              ],
            ),
          ],
        );
      }),
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
        borderRadius: BorderRadius.circular(14),
        boxShadow: sombraTarjeta,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            child: SeccionTitulo('Registros recientes'),
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
class _ItemTipo extends StatelessWidget {
  final IconData icono;
  final String texto;
  const _ItemTipo(this.icono, this.texto);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icono, size: 18, color: AppColors.textPrimary),
        const SizedBox(width: 12),
        Text(texto),
      ],
    );
  }
}