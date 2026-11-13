import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/planilla_mensual.dart';
import '../repositories/planillas_repository.dart';
import '../repositories/repository_exception.dart';
import '../theme/app_colors.dart';
import 'confirm_dialog.dart';

/// Pop up con todos los viajes completados de una planilla (conductor + ciclo).
/// Devuelve el nuevo estado (`'aprobado'` o `'rechazado'`) si el admin la
/// revisó, o `null` si solo lo cerró.
Future<String?> mostrarDialogoDetallePlanilla(
  BuildContext context, {
  required PlanillaMensual planilla,
  required PlanillasRepository repo,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _DetallePlanillaDialog(planilla: planilla, repo: repo),
  );
}

const _meses = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];

String _fechaCorta(DateTime d) => '${d.day.toString().padLeft(2, '0')} ${_meses[d.month - 1]} ${d.year}';

String _horas(double h) => '${h == h.roundToDouble() ? h.toStringAsFixed(1) : h.toString()} hrs'.replaceAll('.', ',');

class _DetallePlanillaDialog extends StatefulWidget {
  const _DetallePlanillaDialog({required this.planilla, required this.repo});

  final PlanillaMensual planilla;
  final PlanillasRepository repo;

  @override
  State<_DetallePlanillaDialog> createState() => _DetallePlanillaDialogState();
}

class _DetallePlanillaDialogState extends State<_DetallePlanillaDialog> {
  /// Ancho relativo: fecha, guía, patente, origen → destino, pallets, hrs extra, guía petróleo.
  static const _flex = [3, 2, 2, 6, 2, 2, 3];
  static const _anchoMinimoTabla = 780.0;

  List<ViajePlanilla> _viajes = [];
  bool _cargando = true;
  String? _error;
  bool _procesando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final viajes = await widget.repo.obtenerViajes(widget.planilla);
      if (!mounted) return;
      setState(() {
        _viajes = viajes;
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
        _error = 'No se pudieron cargar los viajes. Revisa tu conexión e inténtalo de nuevo.';
      });
    }
  }

  Future<void> _cambiarEstado(String nuevoEstado) async {
    final p = widget.planilla;
    final aprobando = nuevoEstado == PlanillaMensual.estadoAprobada;
    final totalPallets = _viajes.fold<int>(0, (s, v) => s + v.pallets);

    final confirmado = await mostrarDialogoConfirmacion(
      context,
      titulo: aprobando ? 'Aprobar planilla' : 'Rechazar planilla',
      mensaje: aprobando
          ? 'Vas a marcar esta planilla como aprobada. Revisa el resumen antes de continuar.'
          : 'Vas a marcar esta planilla como rechazada. Revisa el resumen antes de continuar.',
      resumen: {
        'Trabajador': p.conductorNombre,
        'Período': '${_fechaCorta(p.inicioCiclo)} – ${_fechaCorta(p.finCiclo)}',
        'Viajes': '${_viajes.length}',
        'Pallets': '$totalPallets',
      },
      textoConfirmar: aprobando ? 'APROBAR' : 'RECHAZAR',
      textoCancelar: 'VOLVER',
      icono: aprobando ? Icons.fact_check_outlined : Icons.highlight_off,
    );
    if (!confirmado || !mounted) return;

    setState(() => _procesando = true);
    try {
      await widget.repo.cambiarEstado(p.id, nuevoEstado);
      if (!mounted) return;
      Navigator.of(context).pop(nuevoEstado);
    } on RepositoryException catch (e) {
      _avisarError(e.mensaje);
    } catch (_) {
      _avisarError('No se pudo guardar el cambio. Inténtalo de nuevo.');
    }
  }

  void _avisarError(String mensaje) {
    if (!mounted) return;
    setState(() => _procesando = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.planilla;
    final totalPallets = _viajes.fold<int>(0, (s, v) => s + v.pallets);
    final totalExtra = _viajes.fold<double>(0, (s, v) => s + v.horasExtra);

    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      'Planilla Detallada en Pantalla - ${p.conductorNombre}',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _buildBotonCerrar(),
                ],
              ),
              const SizedBox(height: 16),
              _buildDatosPlanilla(p),
              const SizedBox(height: 18),
              _buildResumen(_viajes.length, totalPallets, totalExtra),
              const SizedBox(height: 18),
              Flexible(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _buildCuerpo(),
                ),
              ),
              const SizedBox(height: 20),
              _buildBotones(p),
            ],
          ),
        ),
      ),
    );
  }

  /// X de la esquina superior derecha, alineada con el título.
  Widget _buildBotonCerrar() {
    return Tooltip(
      message: 'Cerrar',
      child: InkWell(
        onTap: _procesando ? null : () => Navigator.of(context).pop(),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Icon(
            Icons.close,
            size: 22,
            color: _procesando ? AppColors.textSecondary.withOpacity(0.4) : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }

  /// RUT y período del ciclo bien visibles, para que el admin sepa
  /// exactamente qué planilla está revisando.
  Widget _buildDatosPlanilla(PlanillaMensual p) {
    final rut = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'RUT',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            p.conductorRut,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
          ),
        ],
      ),
    );

    final periodo = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withOpacity(0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.calendar_month_outlined, size: 26, color: AppColors.primary),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'PERÍODO DE LA PLANILLA (CICLO 21 AL 20)',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${_fechaCorta(p.inicioCiclo)}  →  ${_fechaCorta(p.finCiclo)}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              ),
            ],
          ),
        ],
      ),
    );

    return Wrap(spacing: 12, runSpacing: 12, children: [rut, periodo]);
  }

  Widget _buildResumen(int viajes, int pallets, double extra) {
    return LayoutBuilder(
      builder: (context, c) {
        final ancho = c.maxWidth >= 600 ? (c.maxWidth - 24) / 3 : c.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _cardResumen(ancho, 'TOTAL VUELTAS', '$viajes'),
            _cardResumen(ancho, 'PALLETS TRANSPORTADOS', '$pallets'),
            _cardResumen(ancho, 'HORAS EXTRA (NOCT/SÁB)', _horas(extra)),
          ],
        );
      },
    );
  }

  Widget _cardResumen(double ancho, String etiqueta, String valor) {
    return Container(
      width: ancho,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            etiqueta,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            valor,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }

  Widget _buildCuerpo() {
    if (_cargando) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator(strokeWidth: 3)),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 13))),
            TextButton(onPressed: _cargar, child: const Text('REINTENTAR')),
          ],
        ),
      );
    }
    if (_viajes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Text(
            'No hay viajes completados en este ciclo.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        final ancho = math.max(c.maxWidth, _anchoMinimoTabla);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: ancho,
            child: SingleChildScrollView(child: _buildTabla()),
          ),
        );
      },
    );
  }

  Widget _celda(int i, Widget hijo) => Expanded(flex: _flex[i], child: hijo);

  Widget _buildTabla() {
    const cabecera = TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.5,
      color: AppColors.textSecondary,
    );
    const dato = TextStyle(fontSize: 13, color: AppColors.textPrimary);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              _celda(0, const Text('FECHA VIAJE', style: cabecera)),
              _celda(1, const Text('N° GUÍA', style: cabecera)),
              _celda(2, const Text('CAMIÓN / PATENTE', style: cabecera)),
              _celda(3, const Text('ORIGEN → DESTINO', style: cabecera)),
              _celda(4, const Text('PALLETS', style: cabecera)),
              _celda(5, const Text('HRS EXTRA', style: cabecera)),
              _celda(6, const Text('GUÍA PETRÓLEO', style: cabecera)),
            ],
          ),
        ),
        for (final v in _viajes)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
            child: Row(
              children: [
                _celda(0, Text(_fechaCorta(v.fecha), style: dato)),
                _celda(1, Text(v.numeroGuia, style: dato)),
                _celda(2, Text(v.patente, style: dato)),
                _celda(3, Text('${v.origen} → ${v.destino}', style: dato, overflow: TextOverflow.ellipsis)),
                _celda(4, Text('${v.pallets}', style: dato)),
                _celda(5, Text(_horas(v.horasExtra), style: dato)),
                _celda(6, Text(v.guiaPetroleo ?? '—', style: dato)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildBotones(PlanillaMensual p) {
    final puedeActuar = !_cargando && _error == null && _viajes.isNotEmpty && !_procesando;

    ButtonStyle estilo(Color color) => ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          disabledBackgroundColor: color.withOpacity(0.35),
          disabledForegroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 0.3),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        );

    Widget cargando() => const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
        );

    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 10,
      children: [
        if (p.aprobada)
          const _EtiquetaEstado(icono: Icons.check_circle, texto: 'Planilla aprobada', color: AppColors.success),
        if (p.rechazada)
          _EtiquetaEstado(icono: Icons.cancel, texto: 'Planilla rechazada', color: Colors.red.shade700),
        // Una planilla ya revisada se puede corregir con el botón contrario.
        if (!p.rechazada)
          ElevatedButton(
            onPressed: puedeActuar ? () => _cambiarEstado(PlanillaMensual.estadoRechazada) : null,
            style: estilo(Colors.red.shade600),
            child: const Text('RECHAZAR'),
          ),
        if (!p.aprobada)
          ElevatedButton(
            onPressed: puedeActuar ? () => _cambiarEstado(PlanillaMensual.estadoAprobada) : null,
            style: estilo(AppColors.success),
            child: _procesando ? cargando() : const Text('APROBAR'),
          ),
      ],
    );
  }
}

class _EtiquetaEstado extends StatelessWidget {
  const _EtiquetaEstado({required this.icono, required this.texto, required this.color});

  final IconData icono;
  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 18, color: color),
          const SizedBox(width: 6),
          Text(texto, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}