import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/planilla_mensual.dart';
import '../repositories/planillas_repository.dart';
import '../repositories/repository_exception.dart';
import '../theme/app_colors.dart';
import '../utils/cartola_rendiciones_pdf.dart';
import 'month_picker_dialog.dart';
import 'paginacion_tabla.dart';

/// Pestaña "Cartola histórica" de Rendiciones: una cartola por conductor y por
/// ciclo (del 21 de un mes al 20 del siguiente), descargable en PDF.
///
/// Usa las planillas que ya cargó la pantalla; los viajes del detalle se
/// piden solo al descargar. Solo se pueden descargar las planillas
/// **aprobadas**. El n° de cartola es correlativo por conductor (1 = su
/// primer ciclo).
class CartolaRendicionesTab extends StatefulWidget {
  const CartolaRendicionesTab({
    super.key,
    required this.planillas,
    required this.repo,
    required this.cargando,
    this.error,
  });

  final List<PlanillaMensual> planillas;
  final PlanillasRepository repo;
  final bool cargando;
  final String? error;

  @override
  State<CartolaRendicionesTab> createState() => _CartolaRendicionesTabState();
}

class _CartolaRendicionesTabState extends State<CartolaRendicionesTab> {
  static const _cartolasPorPagina = 10;

  /// Ancho relativo: n° de cartola, conductor, RUT, período, viajes, estado, acción.
  static const _flex = [2, 4, 3, 4, 2, 3, 3];

  static const _estiloDato = TextStyle(fontSize: 13, color: AppColors.textPrimary);

  static const _diaCierre = 20;
  static const _descargandoAnual = '__anual__';

  late DateTime _mesInicio;
  late DateTime _mesFin;
  late int _anioAnual;

  String _busqueda = '';
  int _pagina = 0;

  /// Conductor elegido para la cartola anual.
  _Conductor? _conductorAnual;

  /// Clave de la cartola que se está generando (o [_descargandoAnual]).
  String? _descargando;

  @override
  void initState() {
    super.initState();
    final finActual = _finDeCiclo(DateTime.now());
    _mesFin = DateTime(finActual.year, finActual.month);
    _mesInicio = DateTime(finActual.year, finActual.month - 11); // últimos 12 ciclos
    _anioAnual = finActual.year;
  }

  // ---------------------------------------------------------------- datos

  static DateTime _finDeCiclo(DateTime d) =>
      d.day > _diaCierre ? DateTime(d.year, d.month + 1, _diaCierre) : DateTime(d.year, d.month, _diaCierre);

  static String _normalizar(String s) => s
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ñ', 'n');

  static String _rutLimpio(String s) => s.toLowerCase().replaceAll('.', '').replaceAll('-', '').trim();

  bool _coincide(String nombre, String rut, String busqueda) {
    final texto = _normalizar(busqueda.trim());
    if (texto.isEmpty) return true;
    final textoRut = _rutLimpio(texto);
    return _normalizar(nombre).contains(texto) || (textoRut.isNotEmpty && _rutLimpio(rut).contains(textoRut));
  }

  /// Una cartola por planilla (conductor + ciclo), del ciclo más reciente al
  /// más antiguo. El n° es correlativo dentro de cada conductor.
  List<_Cartola> _calcularCartolas() {
    final porRut = <String, List<PlanillaMensual>>{};
    for (final p in widget.planillas) {
      (porRut[p.conductorRut] ??= []).add(p);
    }

    final ahora = DateTime.now();
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);

    final lista = <_Cartola>[];
    for (final planillas in porRut.values) {
      planillas.sort((a, b) => a.inicioCiclo.compareTo(b.inicioCiclo));
      for (var i = 0; i < planillas.length; i++) {
        lista.add(_Cartola(numero: i + 1, planilla: planillas[i], enCurso: !planillas[i].finCiclo.isBefore(hoy)));
      }
    }
    lista.sort((a, b) {
      final c = b.planilla.finCiclo.compareTo(a.planilla.finCiclo);
      return c != 0 ? c : a.planilla.conductorNombre.compareTo(b.planilla.conductorNombre);
    });
    return lista;
  }

  List<_Conductor> _conductores() {
    final porRut = <String, _Conductor>{};
    for (final p in widget.planillas) {
      porRut[p.conductorRut] ??= _Conductor(rut: p.conductorRut, nombre: p.conductorNombre);
    }
    return porRut.values.toList()..sort((a, b) => a.nombre.compareTo(b.nombre));
  }

  static bool _enCiclo(ViajePlanilla v, PlanillaMensual p) => !v.fecha.isBefore(p.inicioCiclo) && !v.fecha.isAfter(p.finCiclo);

  // --------------------------------------------------------------- formatos

  static String _dos(int n) => n.toString().padLeft(2, '0');
  static String _dmy(DateTime d) => '${_dos(d.day)}/${_dos(d.month)}/${d.year}';
  static String _mmYyyy(DateTime d) => '${_dos(d.month)}/${d.year}';

  static String _clave(PlanillaMensual p) => '${p.conductorRut}|${p.inicioCiclo.millisecondsSinceEpoch}';

  // -------------------------------------------------------------- acciones

  Future<void> _elegirMes({required bool esInicio, required int anioMin, required int anioMax}) async {
    final elegido = await mostrarSelectorMes(
      context,
      inicial: esInicio ? _mesInicio : _mesFin,
      anioMin: anioMin,
      anioMax: anioMax,
      titulo: esInicio ? 'Mes de inicio' : 'Mes de fin',
    );
    if (elegido == null) return;
    setState(() {
      _pagina = 0;
      if (esInicio) {
        _mesInicio = elegido;
        if (_mesInicio.isAfter(_mesFin)) _mesFin = _mesInicio;
      } else {
        _mesFin = elegido;
        if (_mesFin.isBefore(_mesInicio)) _mesInicio = _mesFin;
      }
    });
  }

  void _avisar(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Future<void> _descargar(_Cartola c) async {
    final p = c.planilla;
    setState(() => _descargando = _clave(p));
    try {
      final viajes = await widget.repo.obtenerViajes(p);
      await descargarCartolaRendicion(
        numero: c.numero,
        conductorNombre: p.conductorNombre,
        conductorRut: p.conductorRut,
        desde: p.inicioCiclo,
        hasta: p.finCiclo,
        emision: c.enCurso ? DateTime.now() : p.finCiclo,
        viajes: viajes,
        colorMarca: AppColors.primary,
      );
    } on RepositoryException catch (e) {
      _avisar(e.mensaje);
    } catch (e) {
      debugPrint('No se pudo generar la cartola N° ${c.numero} de ${p.conductorRut}: $e');
      _avisar('No se pudo generar la cartola. Inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _descargando = null);
    }
  }

  /// Cartola anual del conductor: los ciclos aprobados que terminan en [anio].
  Future<void> _descargarAnual(int anio, _Conductor conductor, List<_Cartola> todas) async {
    final delAnio = todas
        .where((c) =>
            c.planilla.conductorRut == conductor.rut && c.planilla.aprobada && c.planilla.finCiclo.year == anio)
        .toList()
      ..sort((a, b) => a.planilla.inicioCiclo.compareTo(b.planilla.inicioCiclo)); // cronológico
    if (delAnio.isEmpty) return;

    setState(() => _descargando = _descargandoAnual);
    try {
      final desde = delAnio.first.planilla.inicioCiclo;
      final hasta = delAnio.last.planilla.finCiclo;
      final viajes = await widget.repo.obtenerViajesRango(
        conductorRut: conductor.rut,
        desde: desde,
        hasta: hasta,
      );
      await descargarCartolaAnualRendicion(
        anio: anio,
        conductorNombre: conductor.nombre,
        conductorRut: conductor.rut,
        desde: desde,
        hasta: hasta,
        emision: delAnio.last.enCurso ? DateTime.now() : hasta,
        ciclos: [
          for (final c in delAnio)
            CicloRendicionPdf(
              numero: c.numero,
              desde: c.planilla.inicioCiclo,
              hasta: c.planilla.finCiclo,
              viajes: viajes.where((v) => _enCiclo(v, c.planilla)).toList(),
            ),
        ],
        colorMarca: AppColors.primary,
      );
    } on RepositoryException catch (e) {
      _avisar(e.mensaje);
    } catch (e) {
      debugPrint('No se pudo generar la cartola anual $anio de ${conductor.rut}: $e');
      _avisar('No se pudo generar la cartola anual. Inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _descargando = null);
    }
  }

  // ----------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    if (widget.cargando) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 56),
        child: Center(child: CircularProgressIndicator(strokeWidth: 3)),
      );
    }
    if (widget.error != null) return _buildError(widget.error!);

    final todas = _calcularCartolas();
    final filtradas = todas.where((c) {
      final p = c.planilla;
      final mes = DateTime(p.finCiclo.year, p.finCiclo.month);
      if (mes.isBefore(_mesInicio) || mes.isAfter(_mesFin)) return false;
      return _coincide(p.conductorNombre, p.conductorRut, _busqueda);
    }).toList();

    final anioMin = todas.isEmpty ? DateTime.now().year : todas.last.planilla.finCiclo.year;
    final anioMax = todas.isEmpty ? DateTime.now().year : todas.first.planilla.finCiclo.year;
    final anioAnual = _anioAnual.clamp(anioMin, anioMax).toInt();

    final totalPaginas = filtradas.isEmpty ? 1 : (filtradas.length / _cartolasPorPagina).ceil();
    final pagina = _pagina >= totalPaginas ? totalPaginas - 1 : _pagina;
    final visibles = filtradas.skip(pagina * _cartolasPorPagina).take(_cartolasPorPagina).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildAviso(),
        const SizedBox(height: 20),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            _buildBuscador(),
            _buildSelectorMes('MES INICIO', _mesInicio, esInicio: true, anioMin: anioMin, anioMax: anioMax),
            _buildSelectorMes('MES FIN', _mesFin, esInicio: false, anioMin: anioMin, anioMax: anioMax),
          ],
        ),
        const SizedBox(height: 12),
        _buildCartolaAnual(todas, anioAnual, anioMin, anioMax),
        const SizedBox(height: 20),
        _buildTabla(visibles, total: filtradas.length, pagina: pagina, hayPlanillas: widget.planillas.isNotEmpty),
      ],
    );
  }

  Widget _buildError(String mensaje) {
    return Container(
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
          Expanded(child: Text(mensaje, style: TextStyle(color: Colors.red.shade700, fontSize: 13))),
        ],
      ),
    );
  }

  Widget _buildAviso() {
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
            child: const Icon(Icons.info_outline, size: 18, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cartolas por conductor y ciclo',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary),
                ),
                SizedBox(height: 4),
                Text(
                  'Cada ciclo va del 21 de un mes al 20 del siguiente y hay una cartola por conductor. '
                  'Solo se pueden descargar las planillas aprobadas, con sus viajes completados.',
                  style: TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const _estiloEtiqueta = TextStyle(
    fontSize: 10.5,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.6,
    color: AppColors.textSecondary,
  );

  OutlineInputBorder _borde(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: color),
      );

  InputDecoration _decoracionCampo(String hint, IconData icono) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary),
        prefixIcon: Icon(icono, size: 18, color: AppColors.textSecondary),
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        border: _borde(AppColors.border),
        enabledBorder: _borde(AppColors.border),
        focusedBorder: _borde(AppColors.primary),
      );

  Widget _buildBuscador() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('CONDUCTOR', style: _estiloEtiqueta),
        const SizedBox(height: 6),
        SizedBox(
          width: 320,
          height: 42,
          child: TextField(
            onChanged: (v) => setState(() {
              _busqueda = v;
              _pagina = 0;
            }),
            textAlignVertical: TextAlignVertical.center,
            style: const TextStyle(fontSize: 13.5, color: AppColors.textPrimary),
            decoration: _decoracionCampo('Buscar por nombre o RUT...', Icons.search),
          ),
        ),
      ],
    );
  }

  Widget _buildSelectorMes(
    String etiqueta,
    DateTime valor, {
    required bool esInicio,
    required int anioMin,
    required int anioMax,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(etiqueta, style: _estiloEtiqueta),
        const SizedBox(height: 6),
        InkWell(
          onTap: () => _elegirMes(esInicio: esInicio, anioMin: anioMin, anioMax: anioMax),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 42,
            width: 180,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _mmYyyy(valor),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                  ),
                ),
                const Icon(Icons.calendar_today_outlined, size: 16, color: AppColors.primary),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Cartola anual de UN conductor: se elige el conductor y el año.
  Widget _buildCartolaAnual(List<_Cartola> todas, int anio, int anioMin, int anioMax) {
    final conductores = _conductores();
    final conductor = _conductorAnual;
    final aprobadasDelAnio = conductor == null
        ? 0
        : todas
            .where((c) =>
                c.planilla.conductorRut == conductor.rut && c.planilla.aprobada && c.planilla.finCiclo.year == anio)
            .length;
    final generando = _descargando == _descargandoAnual;
    final puedeDescargar = _descargando == null && conductor != null && aprobadasDelAnio > 0;

    return Wrap(
      spacing: 8,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('CARTOLA ANUAL POR CONDUCTOR', style: _estiloEtiqueta),
            const SizedBox(height: 6),
            SizedBox(
              width: 320,
              height: 42,
              child: Autocomplete<_Conductor>(
                displayStringForOption: (c) => '${c.nombre} · ${c.rut}',
                optionsBuilder: (v) => conductores.where((c) => _coincide(c.nombre, c.rut, v.text)),
                onSelected: (c) => setState(() => _conductorAnual = c),
                fieldViewBuilder: (context, controller, focusNode, onSubmitted) => TextField(
                  controller: controller,
                  focusNode: focusNode,
                  onSubmitted: (_) => onSubmitted(),
                  onChanged: (v) {
                    final sel = _conductorAnual;
                    if (sel != null && v != '${sel.nombre} · ${sel.rut}') setState(() => _conductorAnual = null);
                  },
                  textAlignVertical: TextAlignVertical.center,
                  style: const TextStyle(fontSize: 13.5, color: AppColors.textPrimary),
                  decoration: _decoracionCampo('Elegir conductor...', Icons.person_search_outlined),
                ),
              ),
            ),
          ],
        ),
        PopupMenuButton<int>(
          tooltip: 'Elegir año',
          onSelected: (v) => setState(() => _anioAnual = v),
          itemBuilder: (_) => [
            for (var a = anioMax; a >= anioMin; a--) PopupMenuItem<int>(value: a, child: Text('$a')),
          ],
          child: Container(
            height: 42,
            width: 110,
            padding: const EdgeInsets.only(left: 12, right: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '$anio',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                  ),
                ),
                const Icon(Icons.arrow_drop_down, color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
        ElevatedButton.icon(
          onPressed: puedeDescargar ? () => _descargarAnual(anio, conductor, todas) : null,
          icon: generando
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.picture_as_pdf_outlined, size: 16),
          label: const Text(
            'DESCARGAR ANUAL',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.3),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            minimumSize: const Size(0, 42),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ],
    );
  }

  Widget _buildTabla(
    List<_Cartola> visibles, {
    required int total,
    required int pagina,
    required bool hayPlanillas,
  }) {
    final Widget cuerpo;
    if (total == 0) {
      cuerpo = _buildVacio(hayPlanillas: hayPlanillas);
    } else {
      cuerpo = Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) =>
                constraints.maxWidth >= 860 ? _buildTablaAncha(visibles) : _buildListaAngosta(visibles),
          ),
          PaginacionTabla(
            total: total,
            pagina: pagina,
            porPagina: _cartolasPorPagina,
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
            child: Row(
              children: [
                const Text(
                  'Cartolas históricas',
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
                    '$total ${total == 1 ? 'cartola' : 'cartolas'}',
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

  Widget _buildVacio({required bool hayPlanillas}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Column(
          children: [
            Icon(
              hayPlanillas ? Icons.search_off_outlined : Icons.description_outlined,
              size: 32,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 10),
            Text(
              hayPlanillas
                  ? 'No hay cartolas con los filtros seleccionados.'
                  : 'Aún no hay planillas, por eso no hay cartolas.',
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _celda(int columna, Widget hijo) => Expanded(flex: _flex[columna], child: hijo);

  Widget _buildTablaAncha(List<_Cartola> cartolas) {
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
              _celda(0, const Text('N° CARTOLA', style: estiloCabecera)),
              _celda(1, const Text('CONDUCTOR', style: estiloCabecera)),
              _celda(2, const Text('RUT', style: estiloCabecera)),
              _celda(3, const Text('PERÍODO', style: estiloCabecera)),
              _celda(4, const Text('VIAJES', style: estiloCabecera)),
              _celda(5, const Text('ESTADO', style: estiloCabecera)),
              _celda(6, const SizedBox.shrink()),
            ],
          ),
        ),
        for (final c in cartolas)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            constraints: const BoxConstraints(minHeight: 52),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
            child: Row(
              children: [
                _celda(0, Text('${c.numero}', style: _estiloDato)),
                _celda(
                  1,
                  Text(
                    c.planilla.conductorNombre,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                  ),
                ),
                _celda(2, Text(c.planilla.conductorRut, style: _estiloDato)),
                _celda(
                  3,
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '${_dmy(c.planilla.inicioCiclo)} al ${_dmy(c.planilla.finCiclo)}',
                          overflow: TextOverflow.ellipsis,
                          style: _estiloDato,
                        ),
                      ),
                      if (c.enCurso) ...[const SizedBox(width: 8), _badge('EN CURSO', AppColors.warning)],
                    ],
                  ),
                ),
                _celda(4, Text('${c.planilla.viajesCompletados}', style: _estiloDato)),
                _celda(5, Align(alignment: Alignment.centerLeft, child: _badgeEstado(c.planilla))),
                _celda(6, Align(alignment: Alignment.centerRight, child: _buildAccion(c))),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildListaAngosta(List<_Cartola> cartolas) {
    return Column(
      children: [
        for (final c in cartolas)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.planilla.conductorNombre,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Cartola N° ${c.numero}  ·  ${c.planilla.conductorRut}',
                        style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_dmy(c.planilla.inicioCiclo)} al ${_dmy(c.planilla.finCiclo)}  ·  '
                        '${c.planilla.viajesCompletados} ${c.planilla.viajesCompletados == 1 ? 'viaje' : 'viajes'}',
                        style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          _badgeEstado(c.planilla),
                          if (c.enCurso) _badge('EN CURSO', AppColors.warning),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _buildAccion(c),
              ],
            ),
          ),
      ],
    );
  }

  Widget _badge(String texto, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
      child: Text(
        texto,
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: color),
      ),
    );
  }

  Widget _badgeEstado(PlanillaMensual p) {
    if (p.aprobada) return _badge('APROBADA', AppColors.success);
    if (p.estado.trim().toLowerCase() == PlanillaMensual.estadoEnRevision) {
      return _badge('EN REVISIÓN', AppColors.warning);
    }
    return _badge(p.estado.trim().isEmpty ? 'SIN ESTADO' : p.estado.toUpperCase(), AppColors.textSecondary);
  }

  Widget _buildAccion(_Cartola c) {
    const estiloTexto = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.4,
      color: AppColors.textSecondary,
    );
    if (!c.planilla.aprobada) return const Text('SIN APROBAR', style: estiloTexto);
    if (c.planilla.viajesCompletados == 0) return const Text('SIN VIAJES', style: estiloTexto);
    if (_descargando == _clave(c.planilla)) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return TextButton.icon(
      onPressed: _descargando != null ? null : () => _descargar(c),
      icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
      label: const Text(
        'DESCARGAR',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          decoration: TextDecoration.underline,
        ),
      ),
      style: TextButton.styleFrom(foregroundColor: AppColors.primary),
    );
  }
}

/// La cartola de un conductor en un ciclo (del 21 al 20).
class _Cartola {
  const _Cartola({required this.numero, required this.planilla, required this.enCurso});

  /// Correlativo dentro del conductor (1 = su ciclo más antiguo).
  final int numero;
  final PlanillaMensual planilla;

  /// true si el ciclo todavía no termina.
  final bool enCurso;
}

class _Conductor {
  const _Conductor({required this.rut, required this.nombre});

  final String rut;
  final String nombre;
}