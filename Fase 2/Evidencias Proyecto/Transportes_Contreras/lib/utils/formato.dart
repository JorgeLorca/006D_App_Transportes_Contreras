/// Formatea un monto en pesos chilenos: 1500000 -> `$1.500.000`.
String formatearClp(double valor) {
  final entero = valor.round().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < entero.length; i++) {
    final restantes = entero.length - i;
    buffer.write(entero[i]);
    if (restantes > 1 && restantes % 3 == 1) buffer.write('.');
  }
  return '\$$buffer';
}

/// Capitaliza un texto palabra por palabra.
/// - Respeta siglas con puntos como 'S.A.' o 'S.A'
/// - Convierte 'transporte spa' en 'Transporte SpA'
/// - Convierte 'juan pérez' en 'Juan Pérez'
String capitalizarTexto(String? texto) {
  if (texto == null || texto.trim().isEmpty) return '';

  final palabras = texto.trim().split(RegExp(r'\s+'));
  final buffer = <String>[];

  for (final palabra in palabras) {
    if (palabra.isEmpty) continue;

    final limpiaLower = palabra.toLowerCase();

    // Excepciones empresariales comunes en Chile
    if (limpiaLower == 'spa' || limpiaLower == 'spa.') {
      buffer.add('SpA');
    } else if (palabra.contains('.')) {
      // Si contiene puntos (ej. S.A., S.A, Ltda.) se pasa a mayúsculas si son siglas
      if (palabra.length <= 5) {
        buffer.add(palabra.toUpperCase());
      } else {
        buffer.add('${palabra[0].toUpperCase()}${palabra.substring(1).toLowerCase()}');
      }
    } else if (palabra.length == 1) {
      buffer.add(palabra.toUpperCase());
    } else {
      buffer.add('${palabra[0].toUpperCase()}${palabra.substring(1).toLowerCase()}');
    }
  }

  return buffer.join(' ');
}