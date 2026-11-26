import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Banner oscuro de cabecera de página (ícono naranja, título, subtítulo,
/// decoración diagonal y acciones opcionales a la derecha).
class PageHeroBanner extends StatelessWidget {
  final IconData icon;
  final IconData? watermarkIcon;
  final String title;
  final String subtitle;
  final List<Widget> actions;

  const PageHeroBanner({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.watermarkIcon,
    this.actions = const [],
  });

  static const Color navy = Color(0xFF0F1B33);
  static const Color navyClaro = Color(0xFF1B2A4A);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        constraints: const BoxConstraints(minHeight: 132),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [navy, navyClaro],
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bool ancho = constraints.maxWidth > 800;

            final Widget textos = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12.5, color: Color(0xFFCBD5E1)),
                ),
              ],
            );

            final Widget cabecera = Row(
              children: [
                Icon(icon, size: 52, color: AppColors.primary),
                const SizedBox(width: 18),
                Container(width: 1, height: 64, color: Colors.white.withOpacity(0.15)),
                const SizedBox(width: 18),
                Expanded(child: textos),
              ],
            );

            final Widget contenido;
            if (actions.isEmpty) {
              contenido = cabecera;
            } else if (ancho) {
              contenido = Row(
                children: [
                  Expanded(child: cabecera),
                  const SizedBox(width: 16),
                  for (int i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    actions[i],
                  ],
                ],
              );
            } else {
              contenido = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  cabecera,
                  const SizedBox(height: 16),
                  for (int i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(height: 10),
                    actions[i],
                  ],
                ],
              );
            }

            return Stack(
              children: [
                Positioned.fill(child: CustomPaint(painter: _BannerPainter())),
                if (watermarkIcon != null && ancho)
                  Positioned(
                    right: actions.isEmpty ? 56 : 330,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: Icon(watermarkIcon, size: 120, color: Colors.white.withOpacity(0.06)),
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: ancho ? 32 : 20, vertical: 36),
                  child: contenido,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BannerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final franja = Paint()..color = Colors.white.withOpacity(0.04);
    final desplazamiento = h * 0.8;

    // Franjas diagonales translúcidas.
    for (final par in [
      [w * 0.58, w * 0.70],
      [w * 0.74, w * 0.78],
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(par[0], 0)
          ..lineTo(par[1], 0)
          ..lineTo(par[1] - desplazamiento, h)
          ..lineTo(par[0] - desplazamiento, h),
        franja,
      );
    }

    // Franja naranja en la esquina inferior derecha.
    canvas.drawPath(
      Path()
        ..moveTo(w - 80, h)
        ..lineTo(w - 52, h)
        ..lineTo(w, h - 57)
        ..lineTo(w, h - 88),
      Paint()..color = AppColors.primary,
    );

    // Detalle blanco en la esquina inferior izquierda.
    canvas.drawPath(
      Path()
        ..moveTo(0, h - 36)
        ..lineTo(0, h - 16)
        ..lineTo(20, h)
        ..lineTo(44, h),
      Paint()..color = Colors.white.withOpacity(0.9),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Título de sección con barra naranja a la izquierda.
class SeccionTitulo extends StatelessWidget {
  final String texto;
  final Widget? trailing;

  const SeccionTitulo(this.texto, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 10),
        Text(
          texto,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        ),
        if (trailing != null) ...[const SizedBox(width: 10), trailing!],
      ],
    );
  }
}

/// Sombra suave reutilizable para tarjetas blancas.
const List<BoxShadow> sombraTarjeta = [
  BoxShadow(color: Color(0x120F1B33), blurRadius: 14, offset: Offset(0, 4)),
];