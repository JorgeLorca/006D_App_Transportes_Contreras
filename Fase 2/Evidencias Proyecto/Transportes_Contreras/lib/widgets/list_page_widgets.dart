import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'page_hero_banner.dart';

/// Barra superior: buscador + (filtros avanzados) + botón agregar.
class ListToolbar extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback? onFiltros;

  /// Texto que reemplaza a "Filtros Avanzados" cuando hay un filtro activo.
  final String? filtroActivoTexto;
  final String labelAgregar;
  final IconData iconoAgregar;
  final VoidCallback onAgregar;

  const ListToolbar({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    required this.labelAgregar,
    required this.onAgregar,
    this.onFiltros,
    this.filtroActivoTexto,
    this.iconoAgregar = Icons.add,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final bool pequeno = c.maxWidth < 640;
        final bool filtroActivo = filtroActivoTexto != null;

        final Widget campo = SizedBox(
          height: 50,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: sombraTarjeta,
            ),
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (_, valor, __) => TextField(
                controller: controller,
                onChanged: onChanged,
                style: const TextStyle(fontSize: 13.5),
                textAlignVertical: TextAlignVertical.center,
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: const TextStyle(fontSize: 13.5, color: Color(0xFF94A3B8)),
                  prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.textSecondary),
                  suffixIcon: valor.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16, color: AppColors.textSecondary),
                          onPressed: () {
                            controller.clear();
                            onChanged('');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
        );

        final Widget? filtros = onFiltros == null
            ? null
            : SizedBox(
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: onFiltros,
                  icon: Icon(Icons.filter_list, size: 18, color: filtroActivo ? AppColors.primary : AppColors.textPrimary),
                  label: pequeno
                      ? const SizedBox.shrink()
                      : Text(
                          filtroActivoTexto ?? 'Filtros Avanzados',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: filtroActivo ? AppColors.primary : AppColors.textPrimary,
                          ),
                        ),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: filtroActivo ? AppColors.primary.withOpacity(0.08) : Colors.white,
                    side: BorderSide(
                      color: filtroActivo ? AppColors.primary : const Color(0xFFE2E8F0),
                      width: filtroActivo ? 1.5 : 1,
                    ),
                    padding: EdgeInsets.symmetric(horizontal: pequeno ? 14 : 20),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              );

        final Widget agregar = SizedBox(
          height: 50,
          child: ElevatedButton.icon(
            onPressed: onAgregar,
            icon: Icon(iconoAgregar, size: 18, color: Colors.white),
            label: Text(
              labelAgregar,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        );

        if (!pequeno) {
          return Row(
            children: [
              Expanded(child: campo),
              if (filtros != null) ...[const SizedBox(width: 12), filtros],
              const SizedBox(width: 12),
              agregar,
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: campo),
                if (filtros != null) ...[const SizedBox(width: 8), filtros],
              ],
            ),
            const SizedBox(height: 12),
            agregar,
          ],
        );
      },
    );
  }
}

/// Cabecera de sección: título con barra naranja + contador, a la derecha
/// el selector de orden y botones de acción (refrescar, exportar...).
class ListSectionHeader extends StatelessWidget {
  final String titulo;
  final String? contador;
  final Widget? orden;
  final List<Widget> acciones;

  const ListSectionHeader({
    super.key,
    required this.titulo,
    this.contador,
    this.orden,
    this.acciones = const [],
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 10,
        children: [
          SeccionTitulo(
            titulo,
            trailing: contador == null
                ? null
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(12)),
                    child: Text(
                      contador!,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF475569)),
                    ),
                  ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (orden != null) orden!,
              for (final a in acciones) ...[const SizedBox(width: 8), a],
            ],
          ),
        ],
      ),
    );
  }
}

/// Selector "Ordenar por:" con menú desplegable.
class SortDropdown<T> extends StatelessWidget {
  final T valor;
  final Map<T, String> opciones;
  final ValueChanged<T> onChanged;
  final String etiqueta;

  const SortDropdown({
    super.key,
    required this.valor,
    required this.opciones,
    required this.onChanged,
    this.etiqueta = 'Ordenar por:',
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(etiqueta, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
        const SizedBox(width: 8),
        Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            boxShadow: sombraTarjeta,
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: valor,
              isDense: true,
              borderRadius: BorderRadius.circular(10),
              icon: const Icon(Icons.keyboard_arrow_down, size: 18, color: AppColors.textPrimary),
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              items: [
                for (final e in opciones.entries) DropdownMenuItem<T>(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Botón de ícono blanco con sombra (refrescar, exportar...).
class ListIconButton extends StatelessWidget {
  final IconData icono;
  final String tooltip;
  final VoidCallback onPressed;

  const ListIconButton({super.key, required this.icono, required this.tooltip, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            boxShadow: sombraTarjeta,
          ),
          child: Icon(icono, size: 18, color: AppColors.textPrimary),
        ),
      ),
    );
  }
}

/// Paginador: ‹ 1 2 3 … 12 ›
class ListPaginator extends StatelessWidget {
  final int pagina;
  final int total;
  final ValueChanged<int> onChanged;

  const ListPaginator({super.key, required this.pagina, required this.total, required this.onChanged});

  List<int?> _paginas() {
    final visibles = <int>{1, 2, 3, total, pagina - 1, pagina, pagina + 1}
        .where((p) => p >= 1 && p <= total)
        .toList()
      ..sort();
    final resultado = <int?>[];
    int? anterior;
    for (final p in visibles) {
      if (anterior != null) {
        final salto = p - anterior;
        if (salto == 2) {
          resultado.add(anterior + 1);
        } else if (salto > 2) {
          resultado.add(null);
        }
      }
      resultado.add(p);
      anterior = p;
    }
    return resultado;
  }

  @override
  Widget build(BuildContext context) {
    if (total <= 1) return const SizedBox.shrink();

    return Center(
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        children: [
          _boton(
            child: const Icon(Icons.chevron_left, size: 18),
            habilitado: pagina > 1,
            onTap: () => onChanged(pagina - 1),
          ),
          for (final p in _paginas())
            if (p == null)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text('...', style: TextStyle(color: Color(0xFF94A3B8))),
              )
            else
              _boton(
                child: Text('$p', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
                activo: p == pagina,
                onTap: () => onChanged(p),
              ),
          _boton(
            child: const Icon(Icons.chevron_right, size: 18),
            habilitado: pagina < total,
            onTap: () => onChanged(pagina + 1),
          ),
        ],
      ),
    );
  }

  Widget _boton({
    required Widget child,
    required VoidCallback onTap,
    bool activo = false,
    bool habilitado = true,
  }) {
    final Color fg = activo
        ? Colors.white
        : (habilitado ? AppColors.textPrimary : const Color(0xFFCBD5E1));
    return InkWell(
      onTap: habilitado ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: activo ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: activo ? null : sombraTarjeta,
        ),
        child: IconTheme(
          data: IconThemeData(color: fg),
          child: DefaultTextStyle.merge(style: TextStyle(color: fg), child: child),
        ),
      ),
    );
  }
}

/// Mensaje cuando no hay registros.
class ListEmptyState extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String mensaje;

  const ListEmptyState({super.key, required this.icono, required this.titulo, required this.mensaje});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: sombraTarjeta,
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(color: AppColors.surfaceMuted, shape: BoxShape.circle),
            child: Icon(icono, size: 40, color: const Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 16),
          Text(
            titulo,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            mensaje,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── Diálogo de filtros ─────────────────────────

class OpcionFiltro<T> {
  final T valor;
  final String titulo;
  final String subtitulo;
  final Color? color;

  const OpcionFiltro({required this.valor, required this.titulo, required this.subtitulo, this.color});
}

/// Muestra el diálogo de filtros avanzados. Devuelve el valor elegido
/// (o [valorLimpiar] si se pulsa "Limpiar"), o null si se cierra sin aplicar.
Future<T?> mostrarFiltroDialog<T>(
  BuildContext context, {
  required String descripcion,
  required T actual,
  required T valorLimpiar,
  required List<OpcionFiltro<T>> opciones,
}) {
  T seleccion = actual;

  return showDialog<T>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setModalState) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: Colors.white,
        title: Row(
          children: [
            const Icon(Icons.filter_list, color: AppColors.primary, size: 22),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Filtros Avanzados',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18, color: AppColors.textSecondary),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(descripcion, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                const SizedBox(height: 16),
                for (final o in opciones) ...[
                  _OpcionTile<T>(
                    opcion: o,
                    seleccionado: o.valor == seleccion,
                    onTap: () => setModalState(() => seleccion = o.valor),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(valorLimpiar),
            child: const Text('Limpiar', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(seleccion),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Aplicar Filtro', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ),
  );
}

class _OpcionTile<T> extends StatelessWidget {
  final OpcionFiltro<T> opcion;
  final bool seleccionado;
  final VoidCallback onTap;

  const _OpcionTile({required this.opcion, required this.seleccionado, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: seleccionado ? AppColors.primary.withOpacity(0.06) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: seleccionado ? AppColors.primary : AppColors.border,
            width: seleccionado ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              seleccionado ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 20,
              color: seleccionado ? AppColors.primary : const Color(0xFF94A3B8),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    opcion.titulo,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: opcion.color ?? AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(opcion.subtitulo, style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── Diálogo de detalle ─────────────────────────

class DetalleFila {
  final String label;
  final String valor;

  const DetalleFila(this.label, this.valor);
}

/// Diálogo de detalle (botón del "ojo" en las tarjetas).
Future<void> mostrarDetalleDialog(
  BuildContext context, {
  required IconData icono,
  required String titulo,
  required List<DetalleFila> filas,
  Widget? estado,
  Widget? extra,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icono, color: AppColors.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          titulo,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                        ),
                        if (estado != null) ...[const SizedBox(height: 6), estado],
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20, color: AppColors.textSecondary),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(height: 1, color: Color(0xFFE2E8F0)),
              const SizedBox(height: 8),
              for (final f in filas)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 130,
                        child: Text(f.label, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                      ),
                      Expanded(
                        child: Text(
                          f.valor,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
              if (extra != null) ...[const SizedBox(height: 12), extra],
            ],
          ),
        ),
      ),
    ),
  );
}