import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/planilla_mensual.dart';
import '../repositories/planillas_repository.dart';
import '../repositories/repository_exception.dart';
import '../theme/app_colors.dart';
import 'confirm_dialog.dart';

/// Pop up con todos los viajes completados de una planilla (conductor + ciclo).
/// Devuelve `'aprobado'` si el admin aprobó la planilla, o `null` si solo lo
/// cerró.
Future<String?> mostrarDialogoDetallePlanilla(
  BuildContext context, {
  required PlanillaMensual planilla,
  required PlanillasRepository repo,
}) {
  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Detalle de planilla',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (_, __, ___) => _DetallePlanillaDialog(planilla: planilla, repo: repo),
    transitionBuilder: (context, animation, _, child) {
      // Al abrir: "pop" con un leve rebote. Al cerrar: se encoge suave.
      final escala = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInCubic,
      );
      final opacidad = CurvedAnimation(
        parent: animation,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
        reverseCurve: Curves.easeIn,
      );
      return FadeTransition(
        opacity: opacidad,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.85, end: 1.0).animate(escala),
          child: child,
        ),
      );
    },
  );
}

/// Azul oscuro del encabezado del pop up y de la tabla.
const _azulOscuro = Color(0xFF1B2A41);

const _meses = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];

String _fechaCorta(DateTime d) => '${d.day.toString().padLeft(2, '0')} ${_meses[d.month - 1]} ${d.year}';

String _horas(double h) => '${h == h.roundToDouble() ? h.toStringAsFixed(1) : h.toString()} hrs'.replaceAll('.', ',');

/// $12.500 — o "—" si no hay monto.
String _clp(int? monto) {
  if (monto == null || monto == 0) return '—';
  final miles = monto.abs().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
  return '${monto < 0 ? '-' : ''}\$$miles';
}

class _DetallePlanillaDialog extends StatefulWidget {
  const _DetallePlanillaDialog({required this.planilla, required this.repo});

  final PlanillaMensual planilla;
  final PlanillasRepository repo;

  @override
  State<_DetallePlanillaDialog> createState() => _DetallePlanillaDialogState();
}

class _DetallePlanillaDialogState extends State<_DetallePlanillaDialog> {
  /// Ancho relativo de las columnas: fecha, guía, patente, región, cliente,
  /// consignatario, pallets, carga/descarga nocturna, horas sábado, tag,
  /// peonetas, guía petróleo, observación.
  static const _flex = [3, 2, 2, 3, 4, 4, 2, 3, 2, 2, 2, 2, 5];
  static const _anchoMinimoTabla = 1180.0;

  final _scrollHorizontal = ScrollController();

  List<ViajePlanilla> _viajes = [];
  bool _cargando = true;
  String? _error;
  bool _procesando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _scrollHorizontal.dispose();
    super.dispose();
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

  Future<void> _aprobar() async {
    final p = widget.planilla;
    final totalPallets = _viajes.fold<int>(0, (s, v) => s + v.pallets);

    final confirmado = await mostrarDialogoConfirmacion(
      context,
      titulo: 'Aprobar planilla',
      mensaje: 'Vas a marcar esta planilla como aprobada. Revisa el resumen antes de continuar.',
      resumen: {
        'Trabajador': p.conductorNombre,
        'Período': '${_fechaCorta(p.inicioCiclo)} – ${_fechaCorta(p.finCiclo)}',
        'Viajes': '${_viajes.length}',
        'Pallets': '$totalPallets',
      },
      textoConfirmar: 'APROBAR',
      textoCancelar: 'VOLVER',
      icono: Icons.fact_check_outlined,
    );
    if (!confirmado || !mounted) return;

    setState(() => _procesando = true);
    try {
      await widget.repo.aprobar(p.id);
      if (!mounted) return;
      Navigator.of(context).pop(PlanillaMensual.estadoAprobada);
    } on RepositoryException catch (e) {
      _avisarError(e.mensaje);
    } catch (_) {
      _avisarError('No se pudo aprobar la planilla. Inténtalo de nuevo.');
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
    final compacto = MediaQuery.sizeOf(context).width < 600;
    final margen = compacto ? 16.0 : 24.0;
    final espacio = compacto ? 12.0 : 18.0;

    return Dialog(
      backgroundColor: AppColors.surface,
      clipBehavior: Clip.antiAlias,
      insetPadding: EdgeInsets.symmetric(horizontal: compacto ? 12 : 24, vertical: compacto ? 16 : 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox.expand(
        child: Column(
          children: [
            _buildEncabezado(p, compacto),
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(margen),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDatosPlanilla(p, compacto),
                    SizedBox(height: espacio),
                    _buildResumen(_viajes.length, totalPallets, compacto),
                    SizedBox(height: espacio),
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
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
          ],
        ),
      ),
    );
  }

  /// Barra superior azul oscura con el título y la X para cerrar.
  Widget _buildEncabezado(PlanillaMensual p, bool compacto) {
    return Container(
      width: double.infinity,
      color: _azulOscuro,
      padding: EdgeInsets.symmetric(horizontal: compacto ? 16 : 24, vertical: compacto ? 12 : 14),
      child: Row(
        children: [
          const Icon(Icons.calendar_month_outlined, color: Colors.white, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Planilla Detallada en Pantalla - ${p.conductorNombre}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compacto ? 15 : 18,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 12),
          _buildBotonCerrar(),
        ],
      ),
    );
  }

  /// X de la esquina superior derecha, sobre el encabezado oscuro.
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
            color: Colors.white.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            Icons.close,
            size: 22,
            color: _procesando ? Colors.white38 : Colors.white,
          ),
        ),
      ),
    );
  }

  /// Cuadrito redondeado con un ícono, usado en las tarjetas de arriba.
  Widget _iconoCaja(IconData icono, {required Color fondo, required Color color, double tamano = 40}) {
    return Container(
      width: tamano,
      height: tamano,
      decoration: BoxDecoration(color: fondo, shape: BoxShape.circle),
      child: Icon(icono, size: tamano * 0.5, color: color),
    );
  }

  /// RUT y período del ciclo bien visibles, para que el admin sepa
  /// exactamente qué planilla está revisando.
  Widget _buildDatosPlanilla(PlanillaMensual p, bool compacto) {
    const etiquetaRut = TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.6,
      color: AppColors.textSecondary,
    );

    final rut = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _iconoCaja(Icons.person, fondo: Colors.white, color: _azulOscuro.withOpacity(0.75), tamano: 38),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('RUT', style: etiquetaRut),
              const SizedBox(height: 2),
              Text(
                p.conductorRut,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              ),
            ],
          ),
        ],
      ),
    );

    final periodo = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _iconoCaja(Icons.calendar_month_outlined,
              fondo: AppColors.primary.withOpacity(0.15), color: AppColors.primary, tamano: 38),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'PERÍODO DE LA PLANILLA (CICLO 21 AL 20)',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_fechaCorta(p.inicioCiclo)}  –  ${_fechaCorta(p.finCiclo)}',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return Wrap(spacing: 12, runSpacing: 12, children: [rut, periodo]);
  }

  Widget _buildResumen(int viajes, int pallets, bool compacto) {
    return Row(
      children: [
        Expanded(
          child: _cardResumen(
            compacto: compacto,
            icono: Icons.sync,
            fondoIcono: AppColors.primary.withOpacity(0.15),
            colorIcono: AppColors.primary,
            etiqueta: 'TOTAL VUELTAS',
            valor: '$viajes',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _cardResumen(
            compacto: compacto,
            icono: Icons.local_shipping,
            fondoIcono: AppColors.surfaceMuted,
            colorIcono: _azulOscuro.withOpacity(0.8),
            etiqueta: 'PALLETS TRANSPORTADOS',
            valor: '$pallets',
          ),
        ),
      ],
    );
  }

  Widget _cardResumen({
    required bool compacto,
    required IconData icono,
    required Color fondoIcono,
    required Color colorIcono,
    required String etiqueta,
    required String valor,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compacto ? 12 : 16, vertical: compacto ? 12 : 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          _iconoCaja(icono, fondo: fondoIcono, color: colorIcono, tamano: compacto ? 34 : 46),
          SizedBox(width: compacto ? 10 : 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  etiqueta,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  valor,
                  style: TextStyle(
                    fontSize: compacto ? 20 : 24,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
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

    // La tabla tiene muchas columnas: si no caben, se desplaza horizontalmente.
    // La cabecera queda fija y solo las filas se desplazan hacia abajo.
    return LayoutBuilder(
      builder: (context, c) {
        final ancho = math.max(c.maxWidth, _anchoMinimoTabla);
        return Scrollbar(
          controller: _scrollHorizontal,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _scrollHorizontal,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: ancho,
              height: c.maxHeight,
              child: _buildTabla(),
            ),
          ),
        );
      },
    );
  }

  Widget _celda(int i, Widget hijo) => Expanded(
        flex: _flex[i],
        child: Padding(padding: const EdgeInsets.only(right: 12), child: hijo),
      );

  Widget _buildTabla() {
    const cabecera = TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.5,
      color: Colors.white,
    );
    const dato = TextStyle(fontSize: 13, color: AppColors.textPrimary);
    const datoNegrita = TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary);

    Widget titulo(int i, String texto) => _celda(i, Text(texto, style: cabecera));

    return Column(
      children: [
        Stack(
          children: [
            Container(
              color: _azulOscuro,
              padding: const EdgeInsets.fromLTRB(16, 16, 4, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  titulo(0, 'FECHA VIAJE'),
                  titulo(1, 'N° GUÍA'),
                  titulo(2, 'PATENTE'),
                  titulo(3, 'REGIÓN'),
                  titulo(4, 'CLIENTE'),
                  titulo(5, 'CONSIGNATARIO'),
                  titulo(6, 'PALLETS'),
                  titulo(7, 'CARGA / DESCARGA NOCTURNA'),
                  titulo(8, 'HORAS (SÁBADO)'),
                  titulo(9, 'TAG'),
                  titulo(10, 'PEONETAS'),
                  titulo(11, 'GUÍA PETRÓLEO'),
                  titulo(12, 'OBSERVACIÓN'),
                ],
              ),
            ),
            // Detalle naranja en la esquina de la cabecera.
            Positioned(
              left: 0,
              top: 0,
              child: Container(width: 56, height: 3, color: AppColors.primary),
            ),
          ],
        ),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (var i = 0; i < _viajes.length; i++)
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 14, 4, 14),
                    decoration: BoxDecoration(
                      color: i.isOdd ? const Color(0xFFFAFBFD) : Colors.white,
                      border: i == 0 ? null : const Border(top: BorderSide(color: AppColors.border)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _celda(0, Text(_fechaCorta(_viajes[i].fecha), style: datoNegrita)),
                        _celda(1, Text(_viajes[i].numeroGuia, style: dato)),
                        _celda(2, Text(_viajes[i].patente, style: dato)),
                        _celda(3, Text(_viajes[i].region, style: dato)),
                        _celda(4, Text(_viajes[i].cliente, style: dato)),
                        _celda(5, Text(_viajes[i].consignatario, style: dato)),
                        _celda(6, Text('${_viajes[i].pallets}', style: dato)),
                        _celda(7, Text(_horas(_viajes[i].horasNocturnas), style: dato)),
                        _celda(8, Text(_horas(_viajes[i].horasSabado), style: dato)),
                        _celda(9, Text(_clp(_viajes[i].montoTag), style: dato)),
                        _celda(10, Text(_clp(_viajes[i].montoPeonetas), style: dato)),
                        _celda(11, Text(_viajes[i].guiaPetroleo ?? '—', style: dato)),
                        _celda(12, Text(_viajes[i].observacion ?? '—', style: dato)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBotones(PlanillaMensual p) {
    final puedeAprobar = !p.aprobada && !_cargando && _error == null && _viajes.isNotEmpty && !_procesando;

    return Wrap(
      alignment: WrapAlignment.start,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 10,
      children: [
        if (p.aprobada)
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, size: 20, color: AppColors.success),
              SizedBox(width: 6),
              Text(
                'Planilla aprobada',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.success),
              ),
            ],
          )
        else
          ElevatedButton(
            onPressed: puedeAprobar ? _aprobar : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.success.withOpacity(0.35),
              disabledForegroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
              textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 0.3),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: _procesando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check, size: 18),
                      SizedBox(width: 8),
                      Text('APROBAR'),
                    ],
                  ),
          ),
      ],
    );
  }
}