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