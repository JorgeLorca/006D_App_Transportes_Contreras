import 'package:flutter/material.dart';

import '../../models/registro_combustible.dart';
import '../../repositories/registros_combustible_repository.dart';
import '../../repositories/repository_exception.dart';
import '../../theme/app_colors.dart';
import '../../utils/formato.dart';
import '../../widgets/admin_shell.dart';
import '../../widgets/cartola_historica_tab.dart';
import '../../widgets/revision_combustible_dialog.dart';
import '../../widgets/stat_card.dart';

/// Lista de registros de combustible que llenan los conductores en terreno
/// (desde la app móvil), para que la administración los revise.
///
/// Los datos salen de [RegistrosCombustibleRepository]. Se traen todos de una
/// vez y la búsqueda por conductor, el filtro por período, el filtro por
/// estado y la paginación (10 por página) se aplican en pantalla, por eso las
/// tarjetas de arriba reflejan todos los resultados filtrados y no solo la
/// página visible.
class ListaRegistrosCombustibleScreen extends StatefulWidget {
  const ListaRegistrosCombustibleScreen({super.key});

  @override
  State<ListaRegistrosCombustibleScreen> createState() => _ListaRegistrosCombustibleScreenState();
}

class _ListaRegistrosCombustibleScreenState extends State<ListaRegistrosCombustibleScreen> {
  static const _estadoPendiente = 'pendiente';

  /// Cuántos registros se muestran por página.
  static const _registrosPorPagina = 10;

  static const _meses = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];

  /// Ancho relativo de las columnas de la tabla:
  /// conductor, odómetro, litros, costo total, fecha, estado, acción.
  static const _flex = [4, 2, 2, 2, 3, 2, 2];

  static const _estiloDato = TextStyle(fontSize: 13, color: AppColors.textPrimary);

  final _repo = RegistrosCombustibleRepository();

  List<RegistroCombustible> _registros = [];
  bool _cargando = true;
  String? _error;

  String _busqueda = '';
  String? _estadoFiltro; // null = todos
  DateTimeRange? _rango; // null = todo el período
  int _pagina = 0; // página actual (empieza en 0)
  int _tabActual = 0; // 0 = Registros de combustible, 1 = Cartola histórica

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  // ---------------------------------------------------------------- datos

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final registros = await _repo.obtenerTodos();
      if (!mounted) return;
      setState(() {
        _registros = registros;
        _cargando = false;
      });
    } on RepositoryException catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = e.mensaje;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudieron cargar los registros. Revisa tu conexión e inténtalo de nuevo.';
      });
    }
  }

  List<RegistroCombustible> get _filtrados {
    final texto = _normalizar(_busqueda.trim());
    final rango = _rango;
    return _registros.where((r) {
      if (texto.isNotEmpty && !_normalizar(r.conductorEtiqueta).contains(texto)) return false;
      if (_estadoFiltro != null && r.estadoRevision != _estadoFiltro) return false;
      if (rango != null) {
        final fecha = r.registradoEn.toLocal();
        final fin = DateTime(rango.end.year, rango.end.month, rango.end.day, 23, 59, 59);
        if (fecha.isBefore(rango.start) || fecha.isAfter(fin)) return false;
      }
      return true;
    }).toList(); // ya vienen ordenados del más reciente al más antiguo
  }

  /// Estados que existen en los datos cargados (para el filtro).
  List<String> get _estadosDisponibles => (_registros.map((r) => r.estadoRevision).toSet().toList()..sort());

  static String _normalizar(String s) => s
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ñ', 'n');

  // ------------------------------------------------------------- formatos

  static String _miles(num n) =>
      n.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => '.');

  static String _litros(double l) => l == l.roundToDouble() ? _miles(l) : l.toStringAsFixed(1).replaceAll('.', ',');

  static String _fechaCorta(DateTime d) => '${d.day.toString().padLeft(2, '0')} ${_meses[d.month - 1]} ${d.year}';

  static String _fechaHora(DateTime utc) {
    final d = utc.toLocal();
    return '${_fechaCorta(d)}, ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String get _rotuloRango {
    final r = _rango;
    if (r == null) return 'Todo el período';
    return '${_fechaCorta(r.start)} – ${_fechaCorta(r.end)}';
  }

  // -------------------------------------------------------------- acciones

  Future<void> _seleccionarRango() async {
    final ahora = DateTime.now();
    final elegido = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime(ahora.year + 1, 12, 31),
      initialDateRange: _rango,
      helpText: 'Período de los registros',
      cancelText: 'CANCELAR',
      confirmText: 'ACEPTAR',
      saveText: 'ACEPTAR',
      locale: const Locale('es', 'CL'),
    );
    if (elegido != null) {
      setState(() {
        _rango = elegido;
        _pagina = 0;
      });
    }
  }

  Future<void> _abrirFiltroEstado() async {
    const todos = '__todos__';
    final seleccion = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text(
          'Filtrar por estado',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
        children: [
          _opcionFiltro(ctx, todos, 'Todos'),
          for (final estado in _estadosDisponibles) _opcionFiltro(ctx, estado, _etiquetaEstado(estado)),
        ],
      ),
    );
    if (seleccion == null) return; // cerró el diálogo sin elegir
    setState(() {
      _estadoFiltro = seleccion == todos ? null : seleccion;
      _pagina = 0;
    });
  }

  Widget _opcionFiltro(BuildContext ctx, String valor, String etiqueta) {
    final activo = (_estadoFiltro ?? '__todos__') == valor;
    return SimpleDialogOption(
      onPressed: () => Navigator.pop(ctx, valor),
      child: Row(
        children: [
          Icon(
            activo ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            size: 18,
            color: activo ? AppColors.primary : AppColors.textSecondary,
          ),
          const SizedBox(width: 10),
          Text(etiqueta, style: const TextStyle(fontSize: 14, color: AppColors.textPrimary)),
        ],
      ),
    );
  }

  /// Abre el pop up para aprobar o rechazar un registro (también uno ya
  /// revisado, para corregirlo) y, si se actualizó, vuelve a cargar la lista.
  Future<void> _gestionar(RegistroCombustible r) async {
    final resultado = await mostrarDialogoRevisionCombustible(context, registro: r, repo: _repo);
    if (resultado == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Registro ${resultado == 'aprobado' ? 'aprobado' : 'rechazado'} correctamente.')),
    );
    await _cargar();
  }

  Widget _botonGestionar(RegistroCombustible r) {
    return ElevatedButton(
      onPressed: () => _gestionar(r),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: const Text(
        'GESTIONAR',
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.3),
      ),
    );
  }

  // ----------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final filtrados = _filtrados;
    final totalLitros = filtrados.fold<double>(0, (suma, r) => suma + r.litros);
    final pendientes = filtrados.where((r) => r.estadoRevision.toLowerCase() == _estadoPendiente).length;

    final totalPaginas = filtrados.isEmpty ? 1 : (filtrados.length / _registrosPorPagina).ceil();
    // Si al filtrar o refrescar quedan menos páginas, se vuelve a la última.
    final pagina = _pagina >= totalPaginas ? totalPaginas - 1 : _pagina;
    final visibles = filtrados.skip(pagina * _registrosPorPagina).take(_registrosPorPagina).toList();

    return AdminShell(
      selectedIndex: 15, // "Gestión Administrativa > Registros de Combustible"
      title: 'Registros de Combustible',
      subtitle: 'Revise las cargas de combustible reportadas por los conductores.',
      eyebrowIcon: Icons.local_gas_station_outlined,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildEncabezado(),
            const SizedBox(height: 20),
            _buildTabs(),
            const SizedBox(height: 24),
            if (_tabActual == 0) ...[
              _buildControles(),
              if (_estadoFiltro != null) ...[
                const SizedBox(height: 12),
                _buildChipFiltroActivo(),
              ],
              const SizedBox(height: 24),
              _buildMetricas(filtrados.length, totalLitros, pendientes),
              const SizedBox(height: 24),
              _buildTabla(
                visibles: visibles,
                total: filtrados.length,
                pagina: pagina,
                totalPaginas: totalPaginas,
              ),
              const SizedBox(height: 24),
              _buildAvisoRevision(),
            ] else
              CartolaHistoricaTab(registros: _registros, cargando: _cargando, error: _error),
          ],
        ),
      ),
    );
  }

  Widget _buildEncabezado() {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: const Icon(Icons.local_gas_station_outlined, color: AppColors.primary),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            'Registros de Combustible',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
          ),
        ),
        IconButton(
          tooltip: 'Refrescar registros',
          icon: const Icon(Icons.refresh, size: 20, color: AppColors.textSecondary),
          onPressed: _cargando ? null : _cargar,
        ),
      ],
    );
  }

  Widget _buildTabs() {
    const tabs = ['Registros de combustible', 'Cartola histórica'];
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < tabs.length; i++)
            InkWell(
              onTap: () => setState(() => _tabActual = i),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: _tabActual == i ? AppColors.primary : Colors.transparent,
                      width: 3,
                    ),
                  ),
                ),
                child: Text(
                  tabs[i],
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: _tabActual == i ? FontWeight.w700 : FontWeight.w500,
                    color: _tabActual == i ? AppColors.primary : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildControles() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final ancho = constraints.maxWidth > 900;

        final periodo = _buildSelectorPeriodo();
        final busqueda = _buildBusquedaConFiltro();

        if (ancho) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              periodo,
              const SizedBox(width: 16),
              Expanded(child: busqueda),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            periodo,
            const SizedBox(height: 12),
            busqueda,
          ],
        );
      },
    );
  }

  /// Buscador de conductor + botón de filtros, ambos con el mismo alto (42).
  Widget _buildBusquedaConFiltro() {
    OutlineInputBorder borde(Color color) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: color),
        );

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
                hintText: 'Buscar conductor...',
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
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: _abrirFiltroEstado,
          icon: const Icon(Icons.tune, size: 16),
          label: const Text('Filtros Avanzados', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            backgroundColor: Colors.white,
            side: const BorderSide(color: AppColors.border),
            minimumSize: const Size(0, 42),
            maximumSize: const Size(double.infinity, 42),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ],
    );
  }

  Widget _buildSelectorPeriodo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'PERÍODO',
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: _seleccionarRango,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 12),
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
                  _rotuloRango,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                ),
                if (_rango != null) ...[
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => setState(() {
                      _rango = null;
                      _pagina = 0;
                    }),
                    borderRadius: BorderRadius.circular(10),
                    child: const Padding(
                      padding: EdgeInsets.all(2),
                      child: Icon(Icons.close, size: 14, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChipFiltroActivo() {
    return Row(
      children: [
        InputChip(
          label: Text(
            'Estado: ${_etiquetaEstado(_estadoFiltro!)}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          ),
          backgroundColor: Colors.white,
          side: const BorderSide(color: AppColors.border),
          onDeleted: () => setState(() {
            _estadoFiltro = null;
            _pagina = 0;
          }),
          deleteIconColor: AppColors.textSecondary,
        ),
      ],
    );
  }

  Widget _buildMetricas(int total, double litros, int pendientes) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final anchoTarjeta = constraints.maxWidth > 900 ? (constraints.maxWidth - 32) / 3 : double.infinity;

        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SizedBox(
              width: anchoTarjeta,
              child: StatCard(
                label: 'Total registros',
                value: '$total',
                icon: Icons.receipt_long_outlined,
                iconColor: AppColors.primary,
              ),
            ),
            SizedBox(
              width: anchoTarjeta,
              child: StatCard(
                label: 'Litros totales',
                value: '${_litros(litros)} L',
                icon: Icons.local_gas_station_outlined,
                iconColor: AppColors.success,
              ),
            ),
            SizedBox(
              width: anchoTarjeta,
              child: StatCard(
                label: 'Pendientes de revisión',
                value: '$pendientes',
                icon: Icons.error_outline,
                iconColor: AppColors.warning,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTabla({
    required List<RegistroCombustible> visibles,
    required int total,
    required int pagina,
    required int totalPaginas,
  }) {
    final Widget cuerpo;
    if (_cargando) {
      cuerpo = const Padding(
        padding: EdgeInsets.symmetric(vertical: 56),
        child: Center(child: CircularProgressIndicator(strokeWidth: 3)),
      );
    } else if (_error != null) {
      cuerpo = _buildError();
    } else if (total == 0) {
      cuerpo = _buildVacio(hayRegistros: _registros.isNotEmpty);
    } else {
      cuerpo = Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 820) return _buildTablaAncha(visibles);
              return _buildListaAngosta(visibles);
            },
          ),
          _buildPaginacion(total: total, pagina: pagina, totalPaginas: totalPaginas),
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
            child: Row(
              children: [
                const Text(
                  'Listado de Registros',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    '$total ${total == 1 ? 'registro' : 'registros'}',
                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
          cuerpo,
        ],
      ),
    );
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
            Expanded(
              child: Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
            ),
            TextButton(
              onPressed: _cargando ? null : _cargar,
              child: const Text('REINTENTAR'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVacio({required bool hayRegistros}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Column(
          children: [
            Icon(
              hayRegistros ? Icons.search_off_outlined : Icons.local_gas_station_outlined,
              size: 32,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 10),
            Text(
              hayRegistros
                  ? 'No hay registros con los filtros seleccionados.'
                  : 'Aún no hay registros de combustible.',
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _celda(int columna, Widget hijo) => Expanded(flex: _flex[columna], child: hijo);

  Widget _buildTablaAncha(List<RegistroCombustible> visibles) {
    const estiloCabecera = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.6,
      color: AppColors.textSecondary,
    );

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              _celda(0, const Text('CONDUCTOR', style: estiloCabecera)),
              _celda(1, const Text('ODÓMETRO', style: estiloCabecera)),
              _celda(2, const Text('LITROS', style: estiloCabecera)),
              _celda(3, const Text('COSTO TOTAL', style: estiloCabecera)),
              _celda(4, const Text('FECHA', style: estiloCabecera)),
              _celda(5, const Text('ESTADO', style: estiloCabecera)),
              _celda(6, const Text('ACCIÓN', style: estiloCabecera)),
            ],
          ),
        ),
        for (final r in visibles)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                _celda(0, _buildConductor(r.conductorEtiqueta)),
                _celda(1, Text('${_miles(r.odometro)} km', style: _estiloDato)),
                _celda(2, Text('${_litros(r.litros)} L', style: _estiloDato)),
                _celda(
                  3,
                  Text(
                    formatearClp(r.costoTotal),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                ),
                _celda(
                  4,
                  Row(
                    children: [
                      const Icon(Icons.schedule, size: 14, color: AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          _fechaHora(r.registradoEn),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
                _celda(5, Align(alignment: Alignment.centerLeft, child: _EstadoBadge(r.estadoRevision))),
                _celda(
                  6,
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _botonGestionar(r),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Versión para pantallas angostas: cada registro es un bloque apilado.
  Widget _buildListaAngosta(List<RegistroCombustible> visibles) {
    return Column(
      children: [
        for (final r in visibles)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: _buildConductor(r.conductorEtiqueta)),
                    const SizedBox(width: 8),
                    _EstadoBadge(r.estadoRevision),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 16,
                  runSpacing: 6,
                  children: [
                    _datoCompacto(Icons.speed_outlined, '${_miles(r.odometro)} km'),
                    _datoCompacto(Icons.local_gas_station_outlined, '${_litros(r.litros)} L'),
                    _datoCompacto(Icons.payments_outlined, formatearClp(r.costoTotal)),
                    _datoCompacto(Icons.schedule, _fechaHora(r.registradoEn)),
                  ],
                ),
                const SizedBox(height: 12),
                _botonGestionar(r),
              ],
            ),
          ),
      ],
    );
  }

  Widget _datoCompacto(IconData icono, String texto) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icono, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 5),
        Text(texto, style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary)),
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

  // ------------------------------------------------------------ paginación

  Widget _buildPaginacion({required int total, required int pagina, required int totalPaginas}) {
    final desde = pagina * _registrosPorPagina + 1;
    final hasta = (pagina + 1) * _registrosPorPagina > total ? total : (pagina + 1) * _registrosPorPagina;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 20,
        runSpacing: 10,
        children: [
          Text(
            'Mostrando $desde–$hasta de $total ${total == 1 ? 'resultado' : 'resultados'}',
            style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _botonFlecha(
                Icons.chevron_left,
                'Página anterior',
                pagina > 0 ? () => setState(() => _pagina = pagina - 1) : null,
              ),
              for (final p in _paginasVisibles(totalPaginas, pagina)) ...[
                const SizedBox(width: 6),
                if (p == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Text('…', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  )
                else
                  _botonNumero(p, p == pagina),
              ],
              const SizedBox(width: 6),
              _botonFlecha(
                Icons.chevron_right,
                'Página siguiente',
                pagina < totalPaginas - 1 ? () => setState(() => _pagina = pagina + 1) : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Páginas a mostrar (empiezan en 0). `null` representa los puntos
  /// suspensivos. Con pocas páginas se muestran todas; con muchas, la
  /// primera, la última y las vecinas de la actual.
  List<int?> _paginasVisibles(int total, int actual) {
    if (total <= 7) return List<int?>.generate(total, (i) => i);

    final conjunto = <int>{0, total - 1, actual - 1, actual, actual + 1}
      ..removeWhere((p) => p < 0 || p >= total);
    final orden = conjunto.toList()..sort();

    final resultado = <int?>[];
    for (var i = 0; i < orden.length; i++) {
      if (i > 0 && orden[i] - orden[i - 1] > 1) resultado.add(null);
      resultado.add(orden[i]);
    }
    return resultado;
  }

  Widget _botonFlecha(IconData icono, String tooltip, VoidCallback? onTap) {
    final activo = onTap != null;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Icon(
            icono,
            size: 18,
            color: activo ? AppColors.textPrimary : AppColors.textSecondary.withOpacity(0.35),
          ),
        ),
      ),
    );
  }

  Widget _botonNumero(int pagina, bool seleccionada) {
    return InkWell(
      onTap: seleccionada ? null : () => setState(() => _pagina = pagina),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: seleccionada ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: seleccionada ? AppColors.primary : AppColors.border),
        ),
        child: Text(
          '${pagina + 1}',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: seleccionada ? FontWeight.w800 : FontWeight.w600,
            color: seleccionada ? Colors.white : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildAvisoRevision() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.infoBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.infoBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(8)),
            alignment: Alignment.center,
            child: const Icon(Icons.fact_check_outlined, size: 18, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Revisión de registros',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary),
                ),
                SizedBox(height: 4),
                Text(
                  'Los registros en estado Pendiente aún no han sido revisados. Verifique la foto del '
                  'voucher y la del tablero antes de aprobarlos u observarlos.',
                  style: TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "pendiente" -> "Pendiente". Se muestra el valor real de la base, así que
/// cualquier estado nuevo aparece sin tocar el código.
String _etiquetaEstado(String estado) {
  final e = estado.trim();
  if (e.isEmpty) return 'Sin estado';
  return e[0].toUpperCase() + e.substring(1).toLowerCase();
}

String _iniciales(String nombre) {
  final partes = nombre.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (partes.isEmpty) return '?';
  if (partes.length == 1) return partes.first[0].toUpperCase();
  return (partes[0][0] + partes[1][0]).toUpperCase();
}

/// Pastilla de color con el estado de revisión del registro.
class _EstadoBadge extends StatelessWidget {
  const _EstadoBadge(this.estado);

  final String estado;

  @override
  Widget build(BuildContext context) {
    Color fondo;
    Color texto;
    switch (estado.trim().toLowerCase()) {
      case 'pendiente':
        fondo = AppColors.warning.withOpacity(0.15);
        texto = AppColors.warning;
        break;
      case 'aprobado':
      case 'aprobada':
        fondo = AppColors.successBg;
        texto = AppColors.success;
        break;
      case 'observado':
      case 'observada':
      case 'rechazado':
      case 'rechazada':
        fondo = const Color(0xFFFEE2E2);
        texto = Colors.red.shade700;
        break;
      default: // estado que todavía no tiene color propio
        fondo = AppColors.surfaceMuted;
        texto = AppColors.textSecondary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(12)),
      child: Text(
        _etiquetaEstado(estado).toUpperCase(),
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: texto),
      ),
    );
  }
}