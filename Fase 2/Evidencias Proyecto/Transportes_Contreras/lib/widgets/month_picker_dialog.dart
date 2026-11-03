import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Pop up para elegir un mes y un año. Devuelve el primer día del mes elegido
/// o `null` si el usuario cierra el pop up sin elegir.
Future<DateTime?> mostrarSelectorMes(
  BuildContext context, {
  required DateTime inicial,
  required int anioMin,
  required int anioMax,
  String titulo = 'Seleccionar mes',
}) {
  return showDialog<DateTime>(
    context: context,
    builder: (_) => _SelectorMes(
      inicial: inicial,
      anioMin: anioMin,
      anioMax: anioMax,
      titulo: titulo,
    ),
  );
}

class _SelectorMes extends StatefulWidget {
  const _SelectorMes({
    required this.inicial,
    required this.anioMin,
    required this.anioMax,
    required this.titulo,
  });

  final DateTime inicial;
  final int anioMin;
  final int anioMax;
  final String titulo;

  @override
  State<_SelectorMes> createState() => _SelectorMesState();
}

class _SelectorMesState extends State<_SelectorMes> {
  static const _meses = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];

  late int _anio;

  @override
  void initState() {
    super.initState();
    _anio = widget.inicial.year.clamp(widget.anioMin, widget.anioMax).toInt();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.titulo,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    tooltip: 'Año anterior',
                    icon: const Icon(Icons.chevron_left),
                    onPressed: _anio > widget.anioMin ? () => setState(() => _anio--) : null,
                  ),
                  Text(
                    '$_anio',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                  IconButton(
                    tooltip: 'Año siguiente',
                    icon: const Icon(Icons.chevron_right),
                    onPressed: _anio < widget.anioMax ? () => setState(() => _anio++) : null,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (var i = 0; i < 12; i++) _botonMes(i)],
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('CANCELAR'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _botonMes(int indice) {
    final seleccionado = _anio == widget.inicial.year && indice == widget.inicial.month - 1;
    return InkWell(
      onTap: () => Navigator.of(context).pop(DateTime(_anio, indice + 1)),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 90,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: seleccionado ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: seleccionado ? AppColors.primary : AppColors.border),
        ),
        child: Text(
          _meses[indice],
          style: TextStyle(
            fontSize: 13,
            fontWeight: seleccionado ? FontWeight.w800 : FontWeight.w600,
            color: seleccionado ? Colors.white : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}