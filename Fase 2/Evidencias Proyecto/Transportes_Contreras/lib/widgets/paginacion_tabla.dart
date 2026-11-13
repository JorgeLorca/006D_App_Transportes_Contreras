import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Barra de paginación reutilizable para las tablas del panel admin:
/// "Mostrando 1–10 de 17 resultados" + flechas y números de página.
///
/// No guarda estado: la pantalla dueña de la lista mantiene la página actual
/// (empezando en 0) y se entera de los cambios con [onCambiarPagina].
class PaginacionTabla extends StatelessWidget {
  const PaginacionTabla({
    super.key,
    required this.total,
    required this.pagina,
    required this.porPagina,
    required this.onCambiarPagina,
  });

  /// Cantidad total de resultados (ya filtrados).
  final int total;

  /// Página actual, empieza en 0.
  final int pagina;

  /// Cuántos resultados se muestran por página.
  final int porPagina;

  final ValueChanged<int> onCambiarPagina;

  int get _totalPaginas => total == 0 ? 1 : (total / porPagina).ceil();

  @override
  Widget build(BuildContext context) {
    final totalPaginas = _totalPaginas;
    final actual = pagina.clamp(0, totalPaginas - 1);
    final desde = total == 0 ? 0 : actual * porPagina + 1;
    final hasta = (actual + 1) * porPagina > total ? total : (actual + 1) * porPagina;

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
              _BotonFlecha(
                icono: Icons.chevron_left,
                tooltip: 'Página anterior',
                onTap: actual > 0 ? () => onCambiarPagina(actual - 1) : null,
              ),
              for (final p in _paginasVisibles(totalPaginas, actual)) ...[
                const SizedBox(width: 6),
                if (p == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Text('…', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  )
                else
                  _BotonNumero(
                    pagina: p,
                    seleccionada: p == actual,
                    onTap: () => onCambiarPagina(p),
                  ),
              ],
              const SizedBox(width: 6),
              _BotonFlecha(
                icono: Icons.chevron_right,
                tooltip: 'Página siguiente',
                onTap: actual < totalPaginas - 1 ? () => onCambiarPagina(actual + 1) : null,
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
  static List<int?> _paginasVisibles(int total, int actual) {
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
}

class _BotonFlecha extends StatelessWidget {
  const _BotonFlecha({required this.icono, required this.tooltip, required this.onTap});

  final IconData icono;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
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
}

class _BotonNumero extends StatelessWidget {
  const _BotonNumero({required this.pagina, required this.seleccionada, required this.onTap});

  final int pagina;
  final bool seleccionada;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: seleccionada ? null : onTap,
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
}