// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:convert';
import 'package:universal_html/html.dart' as html;

class CsvExporter {
  /// Recibe los encabezados y las filas con sus datos, y descarga el archivo .csv
  static void descargarCsv({
    required String nombreArchivo,
    required List<String> encabezados,
    required List<List<dynamic>> filas,
  }) {
    final StringBuffer buffer = StringBuffer();

    // 1. Agregar BOM para que Excel en Windows reconozca tildes y caracteres en español
    buffer.write('\uFEFF');

    // 2. Encabezados separados por coma (o punto y coma)
    buffer.writeln(encabezados.map(_escaparCampo).join(';'));

    // 3. Filas de datos
    for (final fila in filas) {
      buffer.writeln(fila.map(_escaparCampo).join(';'));
    }

    // 4. Crear Blob y forzar la descarga en el navegador
    final bytes = utf8.encode(buffer.toString());
    final blob = html.Blob([bytes], 'text/csv;charset=utf-8');
    final url = html.Url.createObjectUrlFromBlob(blob);

    final html.AnchorElement anchor = html.AnchorElement(href: url)
      ..setAttribute('download', '$nombreArchivo.csv')
      ..style.display = 'none';

    html.document.body?.children.add(anchor);
    anchor.click();
    anchor.remove();
    html.Url.revokeObjectUrl(url);
  }

  static String _escaparCampo(dynamic campo) {
    if (campo == null) return '""';
    final texto = campo.toString().replaceAll('"', '""');
    return '"$texto"';
  }
}