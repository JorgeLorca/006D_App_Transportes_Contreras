import 'dart:typed_data';

import 'package:flutter/material.dart' show Color;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/registro_combustible.dart';
import 'formato.dart';

/// Un ciclo (del 21 al 20) con sus registros, para armar la cartola anual.
class CicloPdf {
  const CicloPdf({
    required this.numero,
    required this.desde,
    required this.hasta,
    required this.registros,
  });

  final int numero;
  final DateTime desde;
  final DateTime hasta;
  final List<RegistroCombustible> registros;
}

/// Genera la cartola de un ciclo y la descarga como PDF.
///
/// En web el navegador descarga el archivo directamente.
Future<void> descargarCartolaCombustible({
  required int numero,
  required DateTime desde,
  required DateTime hasta,
  required DateTime emision,
  required List<RegistroCombustible> registros,
  required Color colorMarca,
}) async {
  final bytes = await generarCartolaCombustiblePdf(
    numero: numero,
    desde: desde,
    hasta: hasta,
    emision: emision,
    registros: registros,
    colorMarca: colorMarca,
  );
  await Printing.sharePdf(
    bytes: bytes,
    filename: 'cartola_combustible_n${numero}_${_iso(hasta)}.pdf',
  );
}

/// Genera la cartola anual (todos los ciclos de [ciclos]) y la descarga como PDF.
Future<void> descargarCartolaAnualCombustible({
  required int anio,
  required DateTime desde,
  required DateTime hasta,
  required DateTime emision,
  required List<CicloPdf> ciclos,
  required Color colorMarca,
}) async {
  final bytes = await generarCartolaAnualCombustiblePdf(
    anio: anio,
    desde: desde,
    hasta: hasta,
    emision: emision,
    ciclos: ciclos,
    colorMarca: colorMarca,
  );
  await Printing.sharePdf(bytes: bytes, filename: 'cartola_combustible_anual_$anio.pdf');
}

/// PDF de la cartola de un ciclo: encabezado con los datos del ciclo, tabla con
/// fecha, conductor, litros y precio, y un resumen con los totales.
Future<Uint8List> generarCartolaCombustiblePdf({
  required int numero,
  required DateTime desde,
  required DateTime hasta,
  required DateTime emision,
  required List<RegistroCombustible> registros,
  required Color colorMarca,
}) {
  return _generarPdf(
    titulo: 'Cartola de combustible N° $numero',
    subtitulo: 'Cartola de combustible',
    etiquetaCaja: 'CARTOLA N°',
    valorCaja: '$numero',
    desde: desde,
    hasta: hasta,
    emision: emision,
    registros: registros,
    colorMarca: colorMarca,
  );
}

/// PDF de la cartola anual: igual que la de un ciclo, pero antes del detalle
/// trae un resumen con los registros, litros y precio de cada ciclo.
Future<Uint8List> generarCartolaAnualCombustiblePdf({
  required int anio,
  required DateTime desde,
  required DateTime hasta,
  required DateTime emision,
  required List<CicloPdf> ciclos,
  required Color colorMarca,
}) {
  return _generarPdf(
    titulo: 'Cartola anual de combustible $anio',
    subtitulo: 'Cartola anual de combustible',
    etiquetaCaja: 'AÑO',
    valorCaja: '$anio',
    desde: desde,
    hasta: hasta,
    emision: emision,
    registros: [for (final c in ciclos) ...c.registros],
    porCiclo: ciclos,
    colorMarca: colorMarca,
  );
}

Future<Uint8List> _generarPdf({
  required String titulo,
  required String subtitulo,
  required String etiquetaCaja,
  required String valorCaja,
  required DateTime desde,
  required DateTime hasta,
  required DateTime emision,
  required List<RegistroCombustible> registros,
  List<CicloPdf>? porCiclo,
  required Color colorMarca,
}) async {
  final marca = PdfColor.fromInt(colorMarca.value);
  final texto = PdfColor.fromInt(0xFF111827);
  final gris = PdfColor.fromInt(0xFF6B7280);
  final lineaSuave = PdfColor.fromInt(0xFFE5E7EB);
  final zebra = PdfColor.fromInt(0xFFF9FAFB);

  // Cronológico, como una cartola bancaria.
  final filas = [...registros]..sort((a, b) => a.registradoEn.compareTo(b.registradoEn));
  final totalLitros = filas.fold<double>(0, (suma, r) => suma + r.litros);
  final totalCosto = filas.fold<double>(0, (suma, r) => suma + r.costoTotal);

  // ------------------------------------------------------------ componentes

  pw.Widget campo(String etiqueta, String valor) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(etiqueta, style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: gris)),
        pw.SizedBox(height: 3),
        pw.Text(valor, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: texto)),
      ],
    );
  }

  pw.Widget encabezado() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(height: 4, color: marca),
        pw.SizedBox(height: 16),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'TRANSPORTES CONTRERAS',
                  style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: marca),
                ),
                pw.SizedBox(height: 3),
                pw.Text(subtitulo, style: pw.TextStyle(fontSize: 11, color: gris)),
              ],
            ),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: marca, width: 1),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Column(
                children: [
                  pw.Text(etiquetaCaja, style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: gris)),
                  pw.SizedBox(height: 2),
                  pw.Text(valorCaja, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: marca)),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 16),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 10),
          decoration: pw.BoxDecoration(
            border: pw.Border(
              top: pw.BorderSide(color: lineaSuave, width: 0.8),
              bottom: pw.BorderSide(color: lineaSuave, width: 0.8),
            ),
          ),
          child: pw.Row(
            children: [
              pw.Expanded(child: campo('DESDE', _dmy(desde))),
              pw.Expanded(child: campo('HASTA', _dmy(hasta))),
              pw.Expanded(child: campo('FECHA DE EMISIÓN', _dmy(emision))),
              pw.Expanded(child: campo('REGISTROS', '${filas.length}')),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget celda(String valor, {bool derecha = false, bool cabecera = false}) {
    return pw.Container(
      padding: pw.EdgeInsets.symmetric(horizontal: 8, vertical: cabecera ? 7 : 5),
      alignment: derecha ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
      child: pw.Text(
        valor,
        style: pw.TextStyle(
          fontSize: cabecera ? 8.5 : 9.5,
          fontWeight: cabecera ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: cabecera ? PdfColors.white : texto,
        ),
      ),
    );
  }

  /// Tabla con cabecera de color, filas alternadas y líneas suaves.
  /// [derecha] son los índices de las columnas alineadas a la derecha.
  pw.Widget tabla({
    required List<String> cabeceras,
    required List<List<String>> datos,
    required Map<int, pw.TableColumnWidth> anchos,
    required Set<int> derecha,
    required String textoVacio,
  }) {
    final borde = pw.BorderSide(color: marca, width: 0.8);
    final bordeInterno = pw.BorderSide(color: lineaSuave, width: 0.5);

    return pw.Table(
      border: pw.TableBorder(
        left: borde,
        right: borde,
        top: borde,
        bottom: borde,
        horizontalInside: bordeInterno,
        verticalInside: bordeInterno,
      ),
      columnWidths: anchos,
      children: [
        pw.TableRow(
          repeat: true, // la cabecera se repite en cada página
          decoration: pw.BoxDecoration(color: marca),
          children: [
            for (var c = 0; c < cabeceras.length; c++)
              celda(cabeceras[c], cabecera: true, derecha: derecha.contains(c)),
          ],
        ),
        if (datos.isEmpty)
          pw.TableRow(
            children: [
              for (var c = 0; c < cabeceras.length; c++) celda(c == 1 ? textoVacio : ''),
            ],
          ),
        for (var i = 0; i < datos.length; i++)
          pw.TableRow(
            decoration: i.isOdd ? pw.BoxDecoration(color: zebra) : null,
            children: [
              for (var c = 0; c < cabeceras.length; c++) celda(datos[i][c], derecha: derecha.contains(c)),
            ],
          ),
      ],
    );
  }

  pw.Widget tituloSeccion(String t) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Text(t, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: marca)),
    );
  }

  pw.Widget tablaDetalle() {
    return tabla(
      cabeceras: ['FECHA', 'CONDUCTOR', 'LITROS', 'PRECIO'],
      datos: [
        for (final r in filas)
          [
            _dmy(r.registradoEn.toLocal()),
            r.conductorEtiqueta,
            _litros(r.litros),
            formatearClp(r.costoTotal),
          ],
      ],
      anchos: {
        0: const pw.FixedColumnWidth(70),
        1: const pw.FlexColumnWidth(),
        2: const pw.FixedColumnWidth(70),
        3: const pw.FixedColumnWidth(95),
      },
      derecha: {2, 3},
      textoVacio: 'Sin registros en este ciclo',
    );
  }

  /// Solo en la cartola anual: una fila por ciclo.
  pw.Widget tablaPorCiclo(List<CicloPdf> ciclos) {
    return tabla(
      cabeceras: ['CICLO', 'PERÍODO', 'REGISTROS', 'LITROS', 'PRECIO'],
      datos: [
        for (final c in ciclos)
          [
            '${c.numero}',
            '${_dmy(c.desde)} al ${_dmy(c.hasta)}',
            '${c.registros.length}',
            _litros(c.registros.fold<double>(0, (s, r) => s + r.litros)),
            formatearClp(c.registros.fold<double>(0, (s, r) => s + r.costoTotal)),
          ],
      ],
      anchos: {
        0: const pw.FixedColumnWidth(50),
        1: const pw.FlexColumnWidth(),
        2: const pw.FixedColumnWidth(70),
        3: const pw.FixedColumnWidth(70),
        4: const pw.FixedColumnWidth(95),
      },
      derecha: {2, 3, 4},
      textoVacio: 'Sin ciclos',
    );
  }

  pw.Widget cajaResumen(String etiqueta, String valor) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 12),
        alignment: pw.Alignment.center,
        child: pw.Column(
          children: [
            pw.Text(etiqueta, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: gris)),
            pw.SizedBox(height: 4),
            pw.Text(valor, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: marca)),
          ],
        ),
      ),
    );
  }

  pw.Widget separador() => pw.Container(width: 0.5, height: 44, color: lineaSuave);

  pw.Widget resumen() {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: marca, width: 1),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Row(
        children: [
          cajaResumen('TOTAL LITROS', '${_litros(totalLitros)} L'),
          separador(),
          cajaResumen('TOTAL PRECIO', formatearClp(totalCosto)),
          separador(),
          cajaResumen('N° DE REGISTROS', '${filas.length}'),
        ],
      ),
    );
  }

  // -------------------------------------------------------------- documento

  final doc = pw.Document(title: titulo, author: 'Transportes Contreras');

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 44),
      footer: (ctx) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 10),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Transportes Contreras - $titulo', style: pw.TextStyle(fontSize: 8, color: gris)),
            pw.Text(
              'Página ${ctx.pageNumber} de ${ctx.pagesCount}',
              style: pw.TextStyle(fontSize: 8, color: gris),
            ),
          ],
        ),
      ),
      build: (ctx) => [
        encabezado(),
        pw.SizedBox(height: 18),
        if (porCiclo != null) ...[
          tituloSeccion('RESUMEN POR CICLO'),
          tablaPorCiclo(porCiclo),
          pw.SizedBox(height: 18),
          tituloSeccion('DETALLE DE REGISTROS'),
        ],
        tablaDetalle(),
        pw.SizedBox(height: 18),
        resumen(),
      ],
    ),
  );

  return doc.save();
}

// ------------------------------------------------------------------ formatos

String _dos(int n) => n.toString().padLeft(2, '0');

/// 20/10/2026
String _dmy(DateTime d) => '${_dos(d.day)}/${_dos(d.month)}/${d.year}';

/// 2026-10-20 (para el nombre del archivo)
String _iso(DateTime d) => '${d.year}-${_dos(d.month)}-${_dos(d.day)}';

String _miles(num n) => n.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => '.');

String _litros(double l) => l == l.roundToDouble() ? _miles(l) : l.toStringAsFixed(1).replaceAll('.', ',');