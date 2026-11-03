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
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _DialogoRevisionCombustible(registro: registro, repo: repo),
  );
}

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

    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildEncabezado(),
                const SizedBox(height: 16),
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
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  _buildError(),
                ],
                const SizedBox(height: 24),
                if (_guardando) ...[
                  const LinearProgressIndicator(minHeight: 3),
                  const SizedBox(height: 16),
                ],
                _buildBotones(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEncabezado() {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.fact_check_outlined, color: AppColors.primary),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            'Revisar registro de combustible',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
          ),
        ),
      ],
    );
  }

  Widget _buildDatos(RegistroCombustible r) {
    final items = <MapEntry<String, String>>[
      MapEntry('Conductor', r.conductorEtiqueta),
      MapEntry('Patente del camión', _o(r.camionPatente)),
      MapEntry('Odómetro', '${_miles(r.odometro)} km'),
      MapEntry('Tipo de combustible', _o(r.tipoCombustible)),
      MapEntry('Litros', '${_litros(r.litros)} L'),
      MapEntry('Costo total', formatearClp(r.costoTotal)),
      MapEntry('Fecha de registro', _fechaHora(r.registradoEn)),
      MapEntry('Estación', _o(r.estacion)),
      MapEntry('Estado actual', _etiquetaEstado),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i += 2)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
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
      ),
    );
  }

  Widget _dato(MapEntry<String, String> dato) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(dato.key.toUpperCase(), style: _estiloEtiqueta),
        const SizedBox(height: 3),
        Text(
          dato.value,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
        ),
      ],
    );
  }

  Widget _buildFotos() {
    final voucher = _FotoEvidencia(titulo: 'Foto del voucher', futuroUrl: _urlVoucher);
    final tablero = _FotoEvidencia(titulo: 'Foto del tablero', futuroUrl: _urlTablero);

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
          crossAxisAlignment: CrossAxisAlignment.start,
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
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(8),
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
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
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
        borderRadius: BorderRadius.circular(8),
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

  Widget _buildBotones() {
    final estiloSecundario = OutlinedButton.styleFrom(
      foregroundColor: AppColors.textPrimary,
      side: const BorderSide(color: AppColors.border),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
    const textoBoton = TextStyle(fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 0.3);

    if (_rechazando) {
      return Wrap(
        alignment: WrapAlignment.end,
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
            style: estiloSecundario,
            child: const Text('VOLVER'),
          ),
          ElevatedButton(
            onPressed: _guardando ? null : () => _guardar(aprobar: false),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              textStyle: textoBoton,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('CONFIRMAR RECHAZO'),
          ),
        ],
      );
    }

    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 12,
      runSpacing: 8,
      children: [
        OutlinedButton(
          onPressed: _guardando ? null : () => Navigator.of(context).pop(),
          style: estiloSecundario,
          child: const Text('CANCELAR'),
        ),
        if (!_estaRechazado)
          OutlinedButton(
            onPressed: _guardando ? null : () => setState(() => _rechazando = true),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red.shade700,
              side: BorderSide(color: Colors.red.shade300),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              textStyle: textoBoton,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('RECHAZAR'),
          ),
        if (!_estaAprobado)
          ElevatedButton(
            onPressed: _guardando ? null : _aprobar,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              textStyle: textoBoton,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('APROBAR'),
          ),
      ],
    );
  }
}

// --------------------------------------------------------------------- foto

/// Una foto de evidencia (voucher o tablero). Toca para verla en grande.
class _FotoEvidencia extends StatelessWidget {
  const _FotoEvidencia({required this.titulo, required this.futuroUrl});

  final String titulo;
  final Future<String?> futuroUrl;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo.toUpperCase(), style: _estiloEtiqueta),
        const SizedBox(height: 6),
        Container(
          height: 180,
          width: double.infinity,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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