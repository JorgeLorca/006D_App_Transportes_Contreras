import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Muestra un pop up de confirmación y devuelve `true` si el usuario confirma
/// (o `false` si cancela). Reutilizable en todos los formularios.
///
/// [resumen] es opcional: pares "etiqueta → valor" para que el usuario revise
/// lo que va a guardar.
Future<bool> mostrarDialogoConfirmacion(
  BuildContext context, {
  required String titulo,
  required String mensaje,
  Map<String, String> resumen = const {},
  String textoConfirmar = 'CONFIRMAR Y GUARDAR',
  String textoCancelar = 'REVISAR',
  IconData icono = Icons.help_outline,
}) async {
  final confirmado = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _DialogoConfirmacion(
      titulo: titulo,
      mensaje: mensaje,
      resumen: resumen,
      textoConfirmar: textoConfirmar,
      textoCancelar: textoCancelar,
      icono: icono,
    ),
  );
  return confirmado ?? false;
}

class _DialogoConfirmacion extends StatelessWidget {
  const _DialogoConfirmacion({
    required this.titulo,
    required this.mensaje,
    required this.resumen,
    required this.textoConfirmar,
    required this.textoCancelar,
    required this.icono,
  });

  final String titulo;
  final String mensaje;
  final Map<String, String> resumen;
  final String textoConfirmar;
  final String textoCancelar;
  final IconData icono;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceMuted,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Icon(icono, color: AppColors.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        titulo,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  mensaje,
                  style: const TextStyle(fontSize: 14, height: 1.4, color: AppColors.textSecondary),
                ),
                if (resumen.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      children: [
                        for (final fila in resumen.entries)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 140,
                                  child: Text(
                                    fila.key,
                                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    fila.value,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        side: const BorderSide(color: AppColors.border),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: Text(textoCancelar),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 0.3),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: Text(textoConfirmar),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}