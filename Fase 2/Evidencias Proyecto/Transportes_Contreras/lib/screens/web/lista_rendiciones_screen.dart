import 'package:flutter/material.dart';

import '../../models/planilla_mensual.dart';
import '../../repositories/planillas_repository.dart';
import '../../repositories/repository_exception.dart';
import '../../theme/app_colors.dart';
import '../../widgets/admin_shell.dart';
import '../../widgets/cartola_rendiciones_tab.dart';
import '../../widgets/detalle_planilla_dialog.dart';
import '../../widgets/paginacion_tabla.dart';
import '../../widgets/stat_card.dart';

/// Rendiciones: una fila por conductor y ciclo (del 21 al 20) con sus vueltas
/// y pallets. El admin abre el detalle con GESTIONAR, revisa los viajes y
/// aprueba la planilla (en_revision → aprobada).
///
/// Se traen todas las planillas de una vez; la búsqueda, el filtro de ciclo,
/// el filtro de estado y la paginación (10 por página) se aplican en pantalla.
class ListaRendicionesScreen extends StatefulWidget {
  const ListaRendicionesScreen({super.key});

  @override
  State<ListaRendicionesScreen> createState() => _ListaRendicionesScreenState();
}

class _ListaRendicionesScreenState extends State<ListaRendicionesScreen> {
  /// 17 = Rendiciones > Planillas de Conductores (ver AdminShell/AppSidebar).
  static const _indiceSidebar = 17;

  static const _planillasPorPagina = 10;

  static const _meses = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];

  /// Ancho relativo: trabajador, RUT, ciclo, vueltas, pallets, estado, acción.
  static const _flex = [4, 3, 3, 2, 2, 2, 3];

  static const _estiloDato = TextStyle(fontSize: 13, color: AppColors.textPrimary);

  final _repo = PlanillasRepository();

  List<PlanillaMensual> _planillas = [];

  /// Viajes completados (todos los conductores) del ciclo en curso.
  int _viajesCicloActual = 0;
  bool _cargando = true;
  String? _error;

  String _busqueda = '';
  String? _estadoFiltro; // null = todos
  DateTime? _cicloFiltro; // inicio del ciclo elegido; null = todos los ciclos (por defecto)

  /// Valor de "Todos los ciclos" en el menú (un PopupMenuItem con value null
  /// no dispara onSelected, por eso se usa un valor real).
  static const _todosLosCiclos = -1;
  int _pagina = 0;

  int _tabActual = 0; // 0 = Planillas de conductores, 1 = Cartola histórica

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
      final ciclo = _Ciclo.de(DateTime.now());
      final resultados = await Future.wait<Object>([
        _repo.obtenerTodas(),
        _repo.contarViajesCompletados(desde: ciclo.inicio, hasta: ciclo.fin),
      ]);
      if (!mounted) return;
      setState(() {
        _planillas = resultados[0] as List<PlanillaMensual>;
        _viajesCicloActual = resultados[1] as int;
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
        _error = 'No se pudieron cargar las planillas. Revisa tu conexión e inténtalo de nuevo.';
      });
    }
  }

  /// Ciclos distintos que existen en los datos, del más reciente al más antiguo.
  List<PlanillaMensual> get _ciclosDisponibles {
    final vistos = <DateTime>{};
    final lista = <PlanillaMensual>[];
    for (final p in _planillas) {
      if (vistos.add(p.inicioCiclo)) lista.add(p);
    }
    return lista;
  }

  List<PlanillaMensual> get _filtradas {
    final texto = _normalizar(_busqueda.trim());
    final textoRut = texto.replaceAll('.', '').replaceAll('-', '');
    return _planillas.where((p) {
      if (_cicloFiltro != null && p.inicioCiclo != _cicloFiltro) return false;
      if (_estadoFiltro != null && p.estado != _estadoFiltro) return false;
      if (texto.isNotEmpty) {
        final nombre = _normalizar(p.conductorNombre);
        final rut = p.conductorRut.toLowerCase().replaceAll('.', '').replaceAll('-', '');
        if (!nombre.contains(texto) && !(textoRut.isNotEmpty && rut.contains(textoRut))) return false;
      }
      return true;
    }).toList();
  }

  List<String> get _estadosDisponibles => (_planillas.map((p) => p.estado).toSet().toList()..sort());

  static String _normalizar(String s) => s
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ñ', 'n');

  // ------------------------------------------------------------- formatos

  static String _fechaCorta(DateTime d) => '${d.day.toString().padLeft(2, '0')} ${_meses[d.month - 1]}';

  /// "21 Oct – 20 Nov"
  static String _rangoCorto(DateTime inicio, DateTime fin) => '${_fechaCorta(inicio)} – ${_fechaCorta(fin)}';

  /// "21 Oct – 20 Nov 2026"
  static String _rotuloCiclo(DateTime inicio, DateTime fin) => '${_fechaCorta(inicio)} – ${_fechaCorta(fin)} ${fin.year}';

  String get _rotuloSelectorCiclo {
    final c = _cicloFiltro;
    if (c == null) return 'Todos los ciclos';
    final p = _planillas.firstWhere((p) => p.inicioCiclo == c, orElse: () => _planillas.first);
    return 'Ciclo: ${_rotuloCiclo(p.inicioCiclo, p.finCiclo)}';
  }

  // -------------------------------------------------------------- acciones

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
    if (seleccion == null) return;
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

  Future<void> _gestionar(PlanillaMensual p) async {
    final resultado = await mostrarDialogoDetallePlanilla(
      context,
      planilla: p,
      repo: _repo,
    );
    if (resultado == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Planilla aprobada correctamente.')),
    );
    await _cargar();
  }

  Widget _botonGestionar(PlanillaMensual p) {
    return ElevatedButton(
      onPressed: () => _gestionar(p),
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
    final filtradas = _filtradas;

    final totalPaginas = filtradas.isEmpty ? 1 : (filtradas.length / _planillasPorPagina).ceil();
    final pagina = _pagina >= totalPaginas ? totalPaginas - 1 : _pagina;
    final visibles = filtradas.skip(pagina * _planillasPorPagina).take(_planillasPorPagina).toList();

    return AdminShell(
      selectedIndex: _indiceSidebar,
      title: 'Planillas de Conductores',
      subtitle: 'Revise las planillas del ciclo (21 al 20) y apruebe los viajes reportados por los conductores.',
      eyebrow: 'RENDICIONES',
      eyebrowIcon: Icons.receipt_long_outlined,
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
              _buildMetricas(),
              const SizedBox(height: 24),
              _buildTabla(
                visibles: visibles,
                total: filtradas.length,
                pagina: pagina,
              ),
            ] else
              CartolaRendicionesTab(
                planillas: _planillas,
                repo: _repo,
                cargando: _cargando,
                error: _error,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabs() {
    const tabs = ['Planillas de conductores', 'Cartola histórica'];
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
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
          child: const Icon(Icons.receipt_long_outlined, color: AppColors.primary),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            'Planillas de Conductores',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
          ),
        ),
        IconButton(
          tooltip: 'Refrescar planillas',
          icon: const Icon(Icons.refresh, size: 20, color: AppColors.textSecondary),
          onPressed: _cargando ? null : _cargar,
        ),
      ],
    );
  }

  Widget _buildControles() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final ancho = constraints.maxWidth > 900;
        final periodo = _buildSelectorCiclo();
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
                hintText: 'Buscar trabajador por nombre o RUT...',
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

  /// Selector de ciclo (21 al 20): lista los ciclos que existen en los datos.
  Widget _buildSelectorCiclo() {
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
        PopupMenuButton<int>(
          tooltip: 'Elegir ciclo',
          enabled: _planillas.isNotEmpty,
          onSelected: (v) => setState(() {
            _cicloFiltro = v == _todosLosCiclos ? null : DateTime.fromMillisecondsSinceEpoch(v);
            _pagina = 0;
          }),
          itemBuilder: (_) => [
            PopupMenuItem<int>(
              value: _todosLosCiclos,
              child: _itemCiclo('Todos los ciclos', activo: _cicloFiltro == null),
            ),
            for (final c in _ciclosDisponibles)
              PopupMenuItem<int>(
                value: c.inicioCiclo.millisecondsSinceEpoch,
                child: _itemCiclo(
                  _rotuloCiclo(c.inicioCiclo, c.finCiclo),
                  activo: _cicloFiltro == c.inicioCiclo,
                ),
              ),
          ],
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
                  _cargando ? 'Cargando...' : _rotuloSelectorCiclo,
                  style: const TextStyle(fontSize: 13.5, color: AppColors.textPrimary),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.keyboard_arrow_down, size: 18, color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _itemCiclo(String texto, {required bool activo}) {
    return Row(
      children: [
        SizedBox(
          width: 20,
          child: activo ? const Icon(Icons.check, size: 16, color: AppColors.primary) : null,
        ),
        Text(
          texto,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: activo ? FontWeight.w700 : FontWeight.w500,
            color: AppColors.textPrimary,
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

  /// Indicadores del encabezado. El admin revisa un ciclo recién cuando
  /// termina (día 20), por eso el total de viajes es del ciclo en curso y las
  /// otras dos tarjetas miran las planillas del ciclo anterior.
  Widget _buildMetricas() {
    final actual = _Ciclo.de(DateTime.now());
    final anterior = actual.anterior;
    final delAnterior = _planillas.where((p) => anterior.coincide(p.inicioCiclo)).toList();
    final aprobadas = delAnterior.where((p) => p.aprobada).length;
    final porRevisar = delAnterior.length - aprobadas;

    final listo = !_cargando && _error == null;
    final rangoAnterior = _rangoCorto(anterior.inicio, anterior.fin);

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
                label: 'Total viajes del ciclo actual (${_rangoCorto(actual.inicio, actual.fin)})',
                value: listo ? '$_viajesCicloActual' : '—',
                icon: Icons.receipt_long_outlined,
                iconColor: AppColors.primary,
              ),
            ),
            SizedBox(
              width: anchoTarjeta,
              child: StatCard(
                label: 'Planillas por revisar (ciclo $rangoAnterior)',
                value: listo ? '$porRevisar' : '—',
                icon: Icons.error_outline,
                iconColor: AppColors.warning,
              ),
            ),
            SizedBox(
              width: anchoTarjeta,
              child: StatCard(
                label: 'Planillas aprobadas (ciclo $rangoAnterior)',
                value: listo ? (delAnterior.isEmpty ? '0' : '$aprobadas de ${delAnterior.length}') : '—',
                icon: Icons.check_circle_outline,
                iconColor: AppColors.success,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTabla({
    required List<PlanillaMensual> visibles,
    required int total,
    required int pagina,
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
      cuerpo = _buildVacio(hayPlanillas: _planillas.isNotEmpty);
    } else {
      cuerpo = Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 980) return _buildTablaAncha(visibles);
              return _buildListaAngosta(visibles);
            },
          ),
          PaginacionTabla(
            total: total,
            pagina: pagina,
            porPagina: _planillasPorPagina,
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
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 8,
              children: [
                const Text(
                  'Listado de Trabajadores y Planillas',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    '$total ${total == 1 ? 'planilla' : 'planillas'}',
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
            Expanded(child: Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 13))),
            TextButton(onPressed: _cargando ? null : _cargar, child: const Text('REINTENTAR')),
          ],
        ),
      ),
    );
  }

  Widget _buildVacio({required bool hayPlanillas}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Column(
          children: [
            Icon(
              hayPlanillas ? Icons.search_off_outlined : Icons.receipt_long_outlined,
              size: 32,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 10),
            Text(
              hayPlanillas ? 'No hay planillas con los filtros seleccionados.' : 'Aún no hay planillas.',
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _celda(int columna, Widget hijo) => Expanded(flex: _flex[columna], child: hijo);

  Widget _buildTablaAncha(List<PlanillaMensual> visibles) {
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
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
          child: Row(
            children: [
              _celda(0, const Text('TRABAJADOR', style: estiloCabecera)),
              _celda(1, const Text('RUT', style: estiloCabecera)),
              _celda(2, const Text('CICLO', style: estiloCabecera)),
              _celda(3, const Text('VUELTAS', style: estiloCabecera)),
              _celda(4, const Text('PALLETS', style: estiloCabecera)),
              _celda(5, const Text('ESTADO', style: estiloCabecera)),
              _celda(6, const Text('ACCIÓN', style: estiloCabecera)),
            ],
          ),
        ),
        for (final p in visibles)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
            child: Row(
              children: [
                _celda(0, _buildTrabajador(p.conductorNombre)),
                _celda(1, Text(p.conductorRut, style: _estiloDato)),
                _celda(
                  2,
                  Text(
                    _rotuloCiclo(p.inicioCiclo, p.finCiclo),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                ),
                _celda(3, Text('${p.viajesCompletados}', style: _estiloDato)),
                _celda(4, Text('${p.palletsMovidos}', style: _estiloDato)),
                _celda(5, Align(alignment: Alignment.centerLeft, child: _EstadoBadge(p.estado))),
                _celda(6, Align(alignment: Alignment.centerLeft, child: _botonGestionar(p))),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildListaAngosta(List<PlanillaMensual> visibles) {
    return Column(
      children: [
        for (final p in visibles)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: _buildTrabajador(p.conductorNombre)),
                    const SizedBox(width: 8),
                    _EstadoBadge(p.estado),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 16,
                  runSpacing: 6,
                  children: [
                    _datoCompacto(Icons.badge_outlined, p.conductorRut),
                    _datoCompacto(Icons.calendar_today_outlined, _rotuloCiclo(p.inicioCiclo, p.finCiclo)),
                    _datoCompacto(Icons.route_outlined, '${p.viajesCompletados} vueltas'),
                    _datoCompacto(Icons.inventory_2_outlined, '${p.palletsMovidos} pallets'),
                  ],
                ),
                const SizedBox(height: 12),
                _botonGestionar(p),
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

  Widget _buildTrabajador(String nombre) {
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
}

/// Ciclo de rendición: del 21 de un mes al 20 del siguiente.
class _Ciclo {
  const _Ciclo(this.inicio, this.fin);

  static const _diaCierre = 20;

  final DateTime inicio;
  final DateTime fin;

  /// Ciclo que contiene el día [d] (el 20 todavía pertenece al ciclo que cierra).
  factory _Ciclo.de(DateTime d) {
    final inicio = d.day > _diaCierre ? DateTime(d.year, d.month, _diaCierre + 1) : DateTime(d.year, d.month - 1, _diaCierre + 1);
    return _Ciclo(inicio, DateTime(inicio.year, inicio.month + 1, _diaCierre));
  }

  _Ciclo get anterior {
    final ini = DateTime(inicio.year, inicio.month - 1, _diaCierre + 1);
    return _Ciclo(ini, DateTime(inicio.year, inicio.month, _diaCierre));
  }

  /// true si [otroInicio] es el inicio de este ciclo (compara solo la fecha).
  bool coincide(DateTime otroInicio) =>
      otroInicio.year == inicio.year && otroInicio.month == inicio.month && otroInicio.day == inicio.day;
}

/// "en_revision" -> "En revisión", "aprobada" -> "Aprobada".
String _etiquetaEstado(String estado) {
  final e = estado.trim().toLowerCase();
  if (e.isEmpty) return 'Sin estado';
  if (e == PlanillaMensual.estadoEnRevision) return 'En revisión';
  final limpio = e.replaceAll('_', ' ');
  return limpio[0].toUpperCase() + limpio.substring(1);
}

String _iniciales(String nombre) {
  final partes = nombre.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (partes.isEmpty) return '?';
  if (partes.length == 1) return partes.first[0].toUpperCase();
  return (partes[0][0] + partes[1][0]).toUpperCase();
}

/// Pastilla de color con el estado de la planilla.
class _EstadoBadge extends StatelessWidget {
  const _EstadoBadge(this.estado);

  final String estado;

  @override
  Widget build(BuildContext context) {
    Color fondo;
    Color texto;
    switch (estado.trim().toLowerCase()) {
      case PlanillaMensual.estadoEnRevision:
        fondo = AppColors.warning.withOpacity(0.15);
        texto = AppColors.warning;
        break;
      case PlanillaMensual.estadoAprobada:
        fondo = AppColors.successBg;
        texto = AppColors.success;
        break;
      default:
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