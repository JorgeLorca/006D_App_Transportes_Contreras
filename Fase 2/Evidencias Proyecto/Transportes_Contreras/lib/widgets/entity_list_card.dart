import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'page_hero_banner.dart' show sombraTarjeta;

/// Tipo de estado para [EstadoBadge].
enum EstadoTipo { ok, peligro, alerta, neutro }

/// Pastilla de estado con punto de color (Disponible, Activo, En Ruta, etc.).
class EstadoBadge extends StatelessWidget {
  final String texto;
  final EstadoTipo tipo;

  const EstadoBadge({super.key, required this.texto, required this.tipo});

  Color get _fg {
    switch (tipo) {
      case EstadoTipo.ok:
        return AppColors.success;
      case EstadoTipo.peligro:
        return const Color(0xFFDC2626);
      case EstadoTipo.alerta:
        return const Color(0xFFD97706);
      case EstadoTipo.neutro:
        return const Color(0xFF64748B);
    }
  }

  Color get _bg {
    switch (tipo) {
      case EstadoTipo.ok:
        return AppColors.successBg;
      case EstadoTipo.peligro:
        return const Color(0xFFFEE2E2);
      case EstadoTipo.alerta:
        return const Color(0xFFFEF3C7);
      case EstadoTipo.neutro:
        return const Color(0xFFF1F5F9);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: _fg, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(texto, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _fg)),
        ],
      ),
    );
  }
}

/// Avatar circular de la tarjeta: iniciales o un ícono.
class CardAvatar extends StatelessWidget {
  final String? iniciales;
  final IconData? icono;
  final double size;

  const CardAvatar.iniciales(this.iniciales, {super.key, this.size = 60}) : icono = null;
  const CardAvatar.icono(this.icono, {super.key, this.size = 60}) : iniciales = null;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE2E8F0), Color(0xFFF1F5F9)],
        ),
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: iniciales != null
          ? Text(
              iniciales!,
              style: TextStyle(fontSize: size * 0.3, fontWeight: FontWeight.w800, color: const Color(0xFF334155)),
            )
          : Icon(icono, size: size * 0.46, color: const Color(0xFF475569)),
    );
  }
}

/// Línea de información dentro de la tarjeta (con ícono opcional).
class CardInfoLine extends StatelessWidget {
  final String texto;
  final IconData? icono;
  final bool destacado;

  const CardInfoLine({super.key, required this.texto, this.icono, this.destacado = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icono != null) ...[
            Icon(icono, size: 14, color: AppColors.primary),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              texto,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: destacado ? FontWeight.w600 : FontWeight.w500,
                color: destacado ? const Color(0xFF334155) : AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Acción del menú de tres puntos.
class EntityCardAction {
  final String label;
  final IconData icono;
  final VoidCallback onTap;
  final bool destructiva;

  const EntityCardAction({
    required this.label,
    required this.icono,
    required this.onTap,
    this.destructiva = false,
  });
}

/// Tarjeta reutilizable para listados (camiones, trabajadores, etc.):
/// avatar, título, estado, líneas de detalle, botón "ver" y menú de acciones.
class EntityListCard extends StatelessWidget {
  final Widget leading;
  final String titulo;
  final Widget? estado;
  final List<Widget> detalles;
  final VoidCallback? onVer;
  final String tooltipVer;
  final List<EntityCardAction> acciones;

  const EntityListCard({
    super.key,
    required this.leading,
    required this.titulo,
    this.estado,
    this.detalles = const [],
    this.onVer,
    this.tooltipVer = 'Ver detalle',
    this.acciones = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: sombraTarjeta,
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          // En tarjetas angostas el estado baja debajo del título.
          final bool compacto = c.maxWidth < 430;

          final Widget tituloTexto = Text(
            titulo,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
          );

          return Row(
            children: [
              leading,
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(child: tituloTexto),
                        if (estado != null && !compacto) ...[const SizedBox(width: 8), estado!],
                      ],
                    ),
                    if (estado != null && compacto)
                      Padding(padding: const EdgeInsets.only(top: 4, bottom: 1), child: estado!),
                    ...detalles,
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(width: 1, height: 52, color: const Color(0xFFE2E8F0)),
              const SizedBox(width: 10),
              if (onVer != null) ...[
                _BotonCuadrado(
                  tooltip: tooltipVer,
                  onTap: onVer!,
                  child: const Icon(Icons.visibility_outlined, size: 18, color: AppColors.textPrimary),
                ),
                const SizedBox(width: 6),
              ],
              if (acciones.isNotEmpty) _menu(),
            ],
          );
        },
      ),
    );
  }

  Widget _menu() {
    return PopupMenuButton<int>(
      tooltip: 'Más acciones',
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onSelected: (i) => acciones[i].onTap(),
      itemBuilder: (_) => [
        for (int i = 0; i < acciones.length; i++)
          PopupMenuItem<int>(
            value: i,
            child: Row(
              children: [
                Icon(
                  acciones[i].icono,
                  size: 16,
                  color: acciones[i].destructiva ? Colors.red : AppColors.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  acciones[i].label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: acciones[i].destructiva ? Colors.red : AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: _decoBoton,
        child: const Icon(Icons.more_vert, size: 18, color: AppColors.textPrimary),
      ),
    );
  }
}

final BoxDecoration _decoBoton = BoxDecoration(
  color: const Color(0xFFF8FAFC),
  borderRadius: BorderRadius.circular(10),
  border: Border.all(color: const Color(0xFFE2E8F0)),
);

class _BotonCuadrado extends StatelessWidget {
  final String tooltip;
  final VoidCallback onTap;
  final Widget child;

  const _BotonCuadrado({required this.tooltip, required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(width: 36, height: 36, alignment: Alignment.center, decoration: _decoBoton, child: child),
      ),
    );
  }
}

/// Cuadrícula responsiva para [EntityListCard].
/// El número de columnas se calcula según el ancho disponible.
class EntityGrid extends StatelessWidget {
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double anchoMinimo;
  final int maxColumnas;
  final double altoItem;

  const EntityGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.anchoMinimo = 360,
    this.maxColumnas = 3,
    this.altoItem = 104,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final int columnas = (c.maxWidth / anchoMinimo).floor().clamp(1, maxColumnas);
        return GridView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          clipBehavior: Clip.none,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: itemCount,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columnas,
            crossAxisSpacing: 16,
            mainAxisSpacing: 14,
            mainAxisExtent: altoItem,
          ),
          itemBuilder: itemBuilder,
        );
      },
    );
  }
}