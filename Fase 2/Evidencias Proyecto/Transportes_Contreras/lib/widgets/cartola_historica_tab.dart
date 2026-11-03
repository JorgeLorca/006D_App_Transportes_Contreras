import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/registro_combustible.dart';
import '../theme/app_colors.dart';
import '../utils/cartola_combustible_pdf.dart';
import 'month_picker_dialog.dart';

/// Pestaña "Cartola histórica": una cartola por ciclo de Transportes Contreras
/// (del 21 de un mes al 20 del siguiente), descargable en PDF.
///
/// Usa los registros que ya cargó la pantalla, así que no hace consultas
/// propias. Cada cartola incluye solo los registros **aprobados** del ciclo.
class CartolaHistoricaTab extends StatefulWidget {
  const CartolaHistoricaTab({
    super.key,
    required this.registros,
    required this.cargando,
    this.error,
  });

  final List<RegistroCombustible> registros;
  final bool cargando;
  final String? error;

  @override
  State<CartolaHistoricaTab> createState() => _CartolaHistoricaTabState();
}

class _CartolaHistoricaTabState extends State<CartolaHistoricaTab> {
  /// Solo los registros con este estado entran en las cartolas.
  static const _estadoAprobado = 'aprobado';

  /// El ciclo termina el día 20 (y el siguiente empieza el 21).
  static const _diaCierre = 20;

  /// Ancho relativo de las columnas de la tabla:
  /// n° de cartola, período, fecha de emisión, registros, acción.
  static const _flex = [2, 4, 3, 2, 3];

  static const _estiloDato = TextStyle(fontSize: 13, color: AppColors.textPrimary);

  /// Primer día del mes en que termina el ciclo (rango del filtro).
  late DateTime _mesInicio;
  late DateTime _mesFin;

  /// Año de la cartola anual (los ciclos que terminan en ese año).
  late int _anioAnual;

  /// n° de la cartola que se está generando (-1 = la anual).
  int? _descargando;

  static const _descargandoAnual = -1;

  @override
  void initState() {
    super.initState();
    final finActual = _finDeCiclo(DateTime.now());
    _mesFin = DateTime(finActual.year, finActual.month);
    _mesInicio = DateTime(finActual.year, finActual.month - 11); // últimos 12 ciclos
    _anioAnual = finActual.year;
  }

  // ---------------------------------------------------------------- ciclos

  /// Día 20 en que termina el ciclo al que pertenece la fecha [d].
  static DateTime _finDeCiclo(DateTime d) =>
      d.day > _diaCierre ? DateTime(d.year, d.month + 1, _diaCierre) : DateTime(d.year, d.month, _diaCierre);

  /// Todos los ciclos desde el primer registro hasta el actual, del más
  /// reciente al más antiguo. El n° 1 es el ciclo del registro más antiguo.
  List<_Ciclo> _calcularCiclos() {
    final todos = widget.registros;
    if (todos.isEmpty) return const [];

    final aprobadosPorCiclo = <DateTime, List<RegistroCombustible>>{};
    DateTime? primera;
    for (final r in todos) {
      final fecha = r.registradoEn.toLocal();
      if (primera == null || fecha.isBefore(primera)) primera = fecha;
      if (r.estadoRevision.trim().toLowerCase() == _estadoAprobado) {
        (aprobadosPorCiclo[_finDeCiclo(fecha)] ??= []).add(r);
      }
    }

    final ahora = DateTime.now();
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);
    final finActual = _finDeCiclo(ahora);

    final ciclos = <_Ciclo>[];
    var fin = _finDeCiclo(primera!);
    var numero = 1;
    while (!fin.isAfter(finActual)) {
      ciclos.add(
        _Ciclo(
          numero: numero,
          inicio: DateTime(fin.year, fin.month - 1, _diaCierre + 1),
          fin: fin,
          registros: aprobadosPorCiclo[fin] ?? const <RegistroCombustible>[],
          enCurso: !fin.isBefore(hoy),
        ),
      );
      fin = DateTime(fin.year, fin.month + 1, _diaCierre);
      numero++;
    }
    return ciclos.reversed.toList();
  }

  // --------------------------------------------------------------- formatos

  static String _dos(int n) => n.toString().padLeft(2, '0');

  static String _dmy(DateTime d) => '${_dos(d.day)}/${_dos(d.month)}/${d.year}';

  static String _mmYyyy(DateTime d) => '${_dos(d.month)}/${d.year}';

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
      if (esInicio) {
        _mesInicio = elegido;
        if (_mesInicio.isAfter(_mesFin)) _mesFin = _mesInicio;
      } else {
        _mesFin = elegido;
        if (_mesFin.isBefore(_mesInicio)) _mesInicio = _mesFin;
      }
    });
  }

  Future<void> _descargar(_Ciclo c) async {
    setState(() => _descargando = c.numero);
    try {
      await descargarCartolaCombustible(
        numero: c.numero,
        desde: c.inicio,
        hasta: c.fin,
        emision: c.enCurso ? DateTime.now() : c.fin,
        registros: c.registros,
        colorMarca: AppColors.primary,
      );
    } catch (e) {
      debugPrint('No se pudo generar la cartola N° ${c.numero}: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo generar la cartola. Inténtalo de nuevo.')),
      );
    } finally {
      if (mounted) setState(() => _descargando = null);
    }
  }

  /// Cartola anual: todos los ciclos que terminan en [anio] (del 21 de
  /// diciembre del año anterior al 20 de diciembre de [anio]).
  Future<void> _descargarAnual(int anio, List<_Ciclo> todos) async {
    final delAnio = todos.where((c) => c.fin.year == anio).toList().reversed.toList(); // cronológico
    if (delAnio.isEmpty) return;

    setState(() => _descargando = _descargandoAnual);
    try {
      await descargarCartolaAnualCombustible(
        anio: anio,
        desde: delAnio.first.inicio,
        hasta: delAnio.last.fin,
        emision: delAnio.last.enCurso ? DateTime.now() : delAnio.last.fin,
        ciclos: [
          for (final c in delAnio)
            CicloPdf(numero: c.numero, desde: c.inicio, hasta: c.fin, registros: c.registros),
        ],
        colorMarca: AppColors.primary,
      );
    } catch (e) {
      debugPrint('No se pudo generar la cartola anual $anio: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo generar la cartola anual. Inténtalo de nuevo.')),
      );
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

    final ciclos = _calcularCiclos();
    final filtrados = ciclos.where((c) {
      final mes = DateTime(c.fin.year, c.fin.month);
      return !mes.isBefore(_mesInicio) && !mes.isAfter(_mesFin);
    }).toList();

    final anioMin = ciclos.isEmpty ? DateTime.now().year : ciclos.last.fin.year;
    final anioMax = ciclos.isEmpty ? DateTime.now().year : ciclos.first.fin.year;
    final anioAnual = _anioAnual.clamp(anioMin, anioMax).toInt();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildAviso(),
        const SizedBox(height: 20),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          children: [
            _buildSelectorMes('MES INICIO', _mesInicio, esInicio: true, anioMin: anioMin, anioMax: anioMax),
            _buildSelectorMes('MES FIN', _mesFin, esInicio: false, anioMin: anioMin, anioMax: anioMax),
            _buildCartolaAnual(ciclos, anioAnual, anioMin, anioMax),
          ],
        ),
        const SizedBox(height: 20),
        _buildTabla(filtrados, hayRegistros: widget.registros.isNotEmpty),
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
                  'Cartolas por ciclo',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary),
                ),
                SizedBox(height: 4),
                Text(
                  'Cada ciclo va del 21 de un mes al 20 del siguiente. La cartola incluye solo los '
                  'registros de combustible aprobados de ese período.',
                  style: TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
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
        Text(
          etiqueta,
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            color: AppColors.textSecondary,
          ),
        ),
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

  Widget _buildCartolaAnual(List<_Ciclo> todos, int anio, int anioMin, int anioMax) {
    final registrosDelAnio = todos.where((c) => c.fin.year == anio).fold<int>(0, (s, c) => s + c.registros.length);
    final generando = _descargando == _descargandoAnual;
    final puedeDescargar = _descargando == null && registrosDelAnio > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'CARTOLA ANUAL',
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
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
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: puedeDescargar ? () => _descargarAnual(anio, todos) : null,
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
        ),
      ],
    );
  }

  Widget _buildTabla(List<_Ciclo> ciclos, {required bool hayRegistros}) {
    final Widget cuerpo;
    if (ciclos.isEmpty) {
      cuerpo = _buildVacio(hayRegistros: hayRegistros);
    } else {
      cuerpo = LayoutBuilder(
        builder: (context, constraints) {
          return constraints.maxWidth >= 720 ? _buildTablaAncha(ciclos) : _buildListaAngosta(ciclos);
        },
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
                    '${ciclos.length} ${ciclos.length == 1 ? 'cartola' : 'cartolas'}',
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

  Widget _buildVacio({required bool hayRegistros}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Column(
          children: [
            Icon(
              hayRegistros ? Icons.search_off_outlined : Icons.description_outlined,
              size: 32,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 10),
            Text(
              hayRegistros
                  ? 'No hay cartolas en el rango seleccionado.'
                  : 'Aún no hay registros de combustible, por eso no hay cartolas.',
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _celda(int columna, Widget hijo) => Expanded(flex: _flex[columna], child: hijo);

  Widget _buildTablaAncha(List<_Ciclo> ciclos) {
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
              _celda(0, const Text('N° DE CARTOLA', style: estiloCabecera)),
              _celda(1, const Text('PERÍODO', style: estiloCabecera)),
              _celda(2, const Text('FECHA DE EMISIÓN', style: estiloCabecera)),
              _celda(3, const Text('REGISTROS', style: estiloCabecera)),
              _celda(4, const SizedBox.shrink()),
            ],
          ),
        ),
        for (final c in ciclos)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            constraints: const BoxConstraints(minHeight: 52),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
            child: Row(
              children: [
                _celda(0, Text('${c.numero}', style: _estiloDato)),
                _celda(1, Text('${_dmy(c.inicio)} al ${_dmy(c.fin)}', style: _estiloDato)),
                _celda(
                  2,
                  Row(
                    children: [
                      Text(_dmy(c.fin), style: _estiloDato),
                      if (c.enCurso) ...[const SizedBox(width: 8), _badgeEnCurso()],
                    ],
                  ),
                ),
                _celda(3, Text('${c.registros.length}', style: _estiloDato)),
                _celda(4, Align(alignment: Alignment.centerRight, child: _buildAccion(c))),
              ],
            ),
          ),
      ],
    );
  }

  /// Versión para pantallas angostas: cada cartola es un bloque.
  Widget _buildListaAngosta(List<_Ciclo> ciclos) {
    return Column(
      children: [
        for (final c in ciclos)
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
                      Row(
                        children: [
                          Text(
                            'Cartola N° ${c.numero}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          if (c.enCurso) ...[const SizedBox(width: 8), _badgeEnCurso()],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_dmy(c.inicio)} al ${_dmy(c.fin)}  ·  ${c.registros.length} '
                        '${c.registros.length == 1 ? 'registro' : 'registros'}',
                        style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
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

  Widget _badgeEnCurso() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: AppColors.warning.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
      child: const Text(
        'EN CURSO',
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: AppColors.warning),
      ),
    );
  }

  Widget _buildAccion(_Ciclo c) {
    if (c.registros.isEmpty) {
      return const Text(
        'SIN REGISTROS',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: AppColors.textSecondary),
      );
    }
    if (_descargando == c.numero) {
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

/// Un ciclo de cartola (del 21 al 20) con sus registros aprobados.
class _Ciclo {
  const _Ciclo({
    required this.numero,
    required this.inicio,
    required this.fin,
    required this.registros,
    required this.enCurso,
  });

  final int numero;
  final DateTime inicio;
  final DateTime fin;
  final List<RegistroCombustible> registros;

  /// true si el ciclo todavía no termina (se puede descargar con lo que hay hasta hoy).
  final bool enCurso;
}