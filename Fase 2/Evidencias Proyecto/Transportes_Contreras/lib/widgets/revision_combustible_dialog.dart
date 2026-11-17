import 'package:flutter/material.dart';

import '../models/registro_combustible.dart';
import '../repositories/registros_combustible_repository.dart';
import '../repositories/repository_exception.dart';
import '../theme/app_colors.dart';
import '../utils/formato.dart';
import 'confirm_dialog.dart';

/// Pop up para gestionar un registro de combustible: muestra todos sus datos y
/// las dos fotos (voucher y tablero) y permite aprobarlo o rechazarlo (con una
/// nota opcional). Sirve también para corregir un registro ya revisado:
/// uno aprobado se puede rechazar y uno rechazado se puede aprobar.
///
/// Devuelve `'aprobado'` o `'rechazado'` si el registro se actualizó en la base
/// de datos, o `null` si el usuario cerró el pop up sin hacer nada.
Future<String?> mostrarDialogoRevisionCombustible(
  BuildContext context, {
  required RegistroCombustible registro,
  required RegistrosCombustibleRepository repo,
}) {
  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Revisar registro de combustible',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (_, __, ___) => _DialogoRevisionCombustible(registro: registro, repo: repo),
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

/// Azul oscuro del encabezado del pop up.
const _azulOscuro = Color(0xFF1B2A41);

class _DialogoRevisionCombustible extends StatefulWidget {
  const _DialogoRevisionCombustible({required this.registro, required this.repo});

  final RegistroCombustible registro;
  final RegistrosCombustibleRepository repo;

  @override
  State<_DialogoRevisionCombustible> createState() => _DialogoRevisionCombustibleState();
}

class _DialogoRevisionCombustibleState extends State<_DialogoRevisionCombustible> {
  final _notaCtrl = TextEditingController();

  bool _rechazando = false; // true = se está escribiendo la nota del rechazo
  bool _guardando = false;
  String? _error;

  // Se piden una sola vez (si no, cada setState volvería a pedir las URLs).
  late final Future<String?> _urlVoucher;
  late final Future<String?> _urlTablero;

  @override
  void initState() {
    super.initState();
    _urlVoucher = widget.repo.urlEvidencia(widget.registro.urlFotoVoucher);
    _urlTablero = widget.repo.urlEvidencia(widget.registro.urlFotoTablero);
  }

  @override
  void dispose() {
    _notaCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- estado

  String get _estadoActual => widget.registro.estadoRevision.trim().toLowerCase();

  bool get _estaAprobado => _estadoActual == RegistrosCombustibleRepository.estadoAprobado;

  bool get _estaRechazado => _estadoActual == RegistrosCombustibleRepository.estadoRechazado;

  String get _etiquetaEstado {
    switch (_estadoActual) {
      case RegistrosCombustibleRepository.estadoPendiente:
        return 'Pendiente';
      case RegistrosCombustibleRepository.estadoAprobado:
        return 'Aprobado';
      case RegistrosCombustibleRepository.estadoRechazado:
        return 'Rechazado';
      default:
        return widget.registro.estadoRevision;
    }
  }

  // -------------------------------------------------------------- acciones

  Future<void> _aprobar() async {
    final r = widget.registro;
    final confirmado = await mostrarDialogoConfirmacion(
      context,
      titulo: 'Aprobar registro',
      mensaje: _estaRechazado
          ? 'El registro pasará de Rechazado a Aprobado y se incluirá en las cartolas. '
              'La nota del rechazo se eliminará.'
          : 'El registro pasará de $_etiquetaEstado a Aprobado.',
      resumen: {
        'Conductor': r.conductorEtiqueta,
        'Litros': '${_litros(r.litros)} L',
        'Costo total': formatearClp(r.costoTotal),
      },
      textoConfirmar: 'APROBAR',
      textoCancelar: 'VOLVER',
      icono: Icons.check_circle_outline,
    );
    if (!confirmado || !mounted) return;
    await _guardar(aprobar: true);
  }

  Future<void> _guardar({required bool aprobar}) async {
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await widget.repo.actualizarRevision(
        id: widget.registro.id,
        estadoActual: widget.registro.estadoRevision,
        aprobar: aprobar,
        observaciones: aprobar ? null : _notaCtrl.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(aprobar ? 'aprobado' : 'rechazado');
    } on RepositoryException catch (e) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _error = e.mensaje;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _error = 'No se pudo guardar la revisión. Revisa tu conexión e inténtalo de nuevo.';
      });
    }
  }

  // ----------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final r = widget.registro;
    final compacto = MediaQuery.sizeOf(context).width < 600;
    final margen = compacto ? 16.0 : 24.0;

    return Dialog(
      backgroundColor: AppColors.surface,
      clipBehavior: Clip.antiAlias,
      insetPadding: EdgeInsets.symmetric(horizontal: compacto ? 12 : 24, vertical: compacto ? 16 : 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildEncabezado(compacto),
            // Datos y fotos se desplazan; el encabezado y los botones quedan fijos.
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(margen, margen, margen, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDatos(r),
                    if (_tieneNota(r) && !_rechazando) ...[
                      const SizedBox(height: 16),
                      _buildNotaPrevia(r),
                    ],
                    const SizedBox(height: 16),
                    _buildFotos(),
                    if (_rechazando) ...[
                      const SizedBox(height: 16),
                      _buildCampoNota(),
                    ],
                  ],
                ),
              ),
            ),
            _buildPie(margen),
          ],
        ),
      ),
    );
  }

  /// Barra superior azul oscura: ícono, separador naranja, título y X.
  Widget _buildEncabezado(bool compacto) {
    return Container(
      color: _azulOscuro,
      padding: EdgeInsets.symmetric(horizontal: compacto ? 16 : 24, vertical: compacto ? 12 : 14),
      child: Row(
        children: [
          const Icon(Icons.local_gas_station, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          Container(width: 2, height: 28, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Revisar registro de combustible',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compacto ? 16 : 18,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Tooltip(
            message: 'Cerrar',
            child: InkWell(
              onTap: _guardando ? null : () => Navigator.of(context).pop(),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.close, size: 22, color: _guardando ? Colors.white38 : Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDatos(RegistroCombustible r) {
    final items = <_ItemDato>[
      _ItemDato(Icons.person, 'Conductor', r.conductorEtiqueta),
      _ItemDato(Icons.local_shipping, 'Patente del camión', _o(r.camionPatente)),
      _ItemDato(Icons.speed, 'Odómetro', '${_miles(r.odometro)} km'),
      _ItemDato(Icons.local_gas_station, 'Tipo de combustible', _o(r.tipoCombustible)),
      _ItemDato(Icons.water_drop, 'Litros', '${_litros(r.litros)} L'),
      _ItemDato(Icons.attach_money, 'Costo total', formatearClp(r.costoTotal)),
      _ItemDato(Icons.calendar_month, 'Fecha de registro', _fechaHora(r.registradoEn)),
      _ItemDato(Icons.place, 'Estación', _o(r.estacion)),
      _ItemDato(Icons.check_circle, 'Estado actual', _etiquetaEstado, chip: true),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          // Dos columnas si hay espacio; una sola en pantallas muy angostas.
          final dosColumnas = c.maxWidth >= 420;
          if (!dosColumnas) {
            return Column(
              children: [
                for (final it in items)
                  Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: _dato(it)),
              ],
            );
          }
          return Column(
            children: [
              for (var i = 0; i < items.length; i += 2)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _dato(items[i])),
                      const SizedBox(width: 16),
                      Expanded(child: i + 1 < items.length ? _dato(items[i + 1]) : const SizedBox.shrink()),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _dato(_ItemDato it) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(color: AppColors.surfaceMuted, shape: BoxShape.circle),
          child: Icon(it.icono, size: 20, color: _azulOscuro.withOpacity(0.85)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(it.etiqueta.toUpperCase(), style: _estiloEtiqueta),
              const SizedBox(height: 3),
              if (it.chip)
                _chipEstado()
              else
                Text(
                  it.valor,
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Etiqueta de color según el estado: pendiente (naranja), aprobado (verde)
  /// o rechazado (rojo).
  Widget _chipEstado() {
    final Color color = _estaAprobado
        ? AppColors.success
        : _estaRechazado
            ? Colors.red.shade700
            : AppColors.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _etiquetaEstado,
        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }

  Widget _buildFotos() {
    final voucher = _FotoEvidencia(titulo: 'Foto del Voucher', futuroUrl: _urlVoucher);
    final tablero = _FotoEvidencia(titulo: 'Foto del Tablero', futuroUrl: _urlTablero);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 480) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: voucher),
              const SizedBox(width: 16),
              Expanded(child: tablero),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [voucher, const SizedBox(height: 16), tablero],
        );
      },
    );
  }

  bool _tieneNota(RegistroCombustible r) => (r.observacionesAdmin ?? '').trim().isNotEmpty;

  /// Nota que la administración dejó antes (por ejemplo, el motivo de un rechazo).
  Widget _buildNotaPrevia(RegistroCombustible r) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_estaRechazado ? 'NOTA DEL RECHAZO' : 'NOTA DE LA ADMINISTRACIÓN', style: _estiloEtiqueta),
          const SizedBox(height: 4),
          Text(
            r.observacionesAdmin!.trim(),
            style: const TextStyle(fontSize: 13.5, height: 1.4, color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }

  Widget _buildCampoNota() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_estaAprobado) ...[
          Text(
            'Este registro estaba aprobado. Al rechazarlo dejará de contar en las cartolas.',
            style: TextStyle(fontSize: 12.5, height: 1.4, color: Colors.red.shade700),
          ),
          const SizedBox(height: 12),
        ],
        const Text('NOTA DEL RECHAZO (OPCIONAL)', style: _estiloEtiqueta),
        const SizedBox(height: 6),
        TextField(
          controller: _notaCtrl,
          enabled: !_guardando,
          autofocus: true,
          minLines: 3,
          maxLines: 4,
          maxLength: 300,
          style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Explica por qué se rechaza este registro...',
            hintStyle: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.primary),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildError() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade700, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  /// Zona fija de abajo: separador, error (si hay) y botones.
  Widget _buildPie(double margen) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: EdgeInsets.fromLTRB(margen, 16, margen, margen - 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_error != null) ...[
            _buildError(),
            const SizedBox(height: 12),
          ],
          if (_guardando) ...[
            const LinearProgressIndicator(minHeight: 3),
            const SizedBox(height: 12),
          ],
          _buildBotones(),
        ],
      ),
    );
  }

  Widget _buildBotones() {
    const textoBoton = TextStyle(fontWeight: FontWeight.w700, fontSize: 14);
    const relleno = EdgeInsets.symmetric(horizontal: 24, vertical: 14);
    final forma = RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));

    if (_rechazando) {
      return Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          OutlinedButton(
            onPressed: _guardando
                ? null
                : () => setState(() {
                      _rechazando = false;
                      _error = null;
                    }),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              backgroundColor: Colors.white,
              side: const BorderSide(color: AppColors.border),
              padding: relleno,
              textStyle: textoBoton,
              shape: forma,
            ),
            child: const Text('Volver'),
          ),
          ElevatedButton(
            onPressed: _guardando ? null : () => _guardar(aprobar: false),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: relleno,
              textStyle: textoBoton,
              shape: forma,
            ),
            child: const Text('Confirmar rechazo'),
          ),
        ],
      );
    }

    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        if (!_estaRechazado)
          OutlinedButton(
            onPressed: _guardando ? null : () => setState(() => _rechazando = true),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red.shade700,
              backgroundColor: Colors.white,
              side: BorderSide(color: Colors.red.shade400),
              padding: relleno,
              textStyle: textoBoton,
              shape: forma,
            ),
            child: const Text('Rechazar'),
          ),
        if (!_estaAprobado)
          ElevatedButton(
            onPressed: _guardando ? null : _aprobar,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.primary.withOpacity(0.35),
              disabledForegroundColor: Colors.white,
              elevation: 0,
              padding: relleno,
              textStyle: textoBoton,
              shape: forma,
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check, size: 18),
                SizedBox(width: 8),
                Text('Aprobar'),
              ],
            ),
          ),
      ],
    );
  }
}

/// Un dato del recuadro de información (ícono + etiqueta + valor).
class _ItemDato {
  const _ItemDato(this.icono, this.etiqueta, this.valor, {this.chip = false});

  final IconData icono;
  final String etiqueta;
  final String valor;

  /// true = en vez del texto se muestra una etiqueta de color con el estado.
  final bool chip;
}

// --------------------------------------------------------------------- foto

/// Una foto de evidencia (voucher o tablero) dentro de su tarjeta.
/// Toca para verla en grande.
class _FotoEvidencia extends StatelessWidget {
  const _FotoEvidencia({required this.titulo, required this.futuroUrl});

  final String titulo;
  final Future<String?> futuroUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.image_outlined, size: 20, color: _azulOscuro.withOpacity(0.85)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  titulo,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            height: 190,
            width: double.infinity,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(8),
            ),
            child: FutureBuilder<String?>(
              future: futuroUrl,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
                }
                final url = snap.data;
                if (snap.hasError || url == null) {
                  return _mensaje(
                    Icons.image_not_supported_outlined,
                    snap.hasError ? 'No se pudo cargar la foto' : 'Sin foto',
                  );
                }
                return InkWell(
                  onTap: () => _ampliar(context, url),
                  child: Image.network(
                    url,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, progreso) {
                      if (progreso == null) return child;
                      return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
                    },
                    errorBuilder: (_, __, ___) => _mensaje(Icons.broken_image_outlined, 'No se pudo cargar la foto'),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _mensaje(IconData icono, String texto) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 28, color: AppColors.textSecondary),
          const SizedBox(height: 6),
          Text(texto, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  void _ampliar(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.surface,
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      titulo,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    icon: const Icon(Icons.close, size: 20, color: AppColors.textSecondary),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: InteractiveViewer(
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('No se pudo cargar la foto', style: TextStyle(color: AppColors.textSecondary)),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ formatos

const _estiloEtiqueta = TextStyle(
  fontSize: 10.5,
  fontWeight: FontWeight.w800,
  letterSpacing: 0.6,
  color: AppColors.textSecondary,
);

const _meses = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];

/// Texto o "—" si viene vacío.
String _o(String? s) => (s == null || s.trim().isEmpty) ? '—' : s;

String _miles(num n) => n.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => '.');

String _litros(double l) => l == l.roundToDouble() ? _miles(l) : l.toStringAsFixed(1).replaceAll('.', ',');

String _fechaHora(DateTime utc) {
  final d = utc.toLocal();
  final fecha = '${d.day.toString().padLeft(2, '0')} ${_meses[d.month - 1]} ${d.year}';
  return '$fecha, ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}