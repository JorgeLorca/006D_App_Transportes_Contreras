import 'dart:typed_data';

import 'package:flutter/material.dart' show Color;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/planilla_mensual.dart';

/// Un ciclo (del 21 al 20) de un conductor con sus viajes, para la cartola anual.
class CicloRendicionPdf {
  const CicloRendicionPdf({
    required this.numero,
    required this.desde,
    required this.hasta,
    required this.viajes,
  });

  final int numero;
  final DateTime desde;
  final DateTime hasta;
  final List<ViajePlanilla> viajes;
}

/// Genera la cartola de rendiciones de un conductor para un ciclo y la descarga.
Future<void> descargarCartolaRendicion({
  required int numero,
  required String conductorNombre,
  required String conductorRut,
  required DateTime desde,
  required DateTime hasta,
  required DateTime emision,
  required List<ViajePlanilla> viajes,
  required Color colorMarca,
}) async {
  final bytes = await generarCartolaRendicionPdf(
    numero: numero,
    conductorNombre: conductorNombre,
    conductorRut: conductorRut,
    desde: desde,
    hasta: hasta,
    emision: emision,
    viajes: viajes,
    colorMarca: colorMarca,
  );
  await Printing.sharePdf(
    bytes: bytes,
    filename: 'cartola_rendicion_n${numero}_${_rutArchivo(conductorRut)}_${_iso(hasta)}.pdf',
  );
}

/// Genera la cartola anual de un conductor (todos los ciclos de [ciclos]).
Future<void> descargarCartolaAnualRendicion({
  required int anio,
  required String conductorNombre,
  required String conductorRut,
  required DateTime desde,
  required DateTime hasta,
  required DateTime emision,
  required List<CicloRendicionPdf> ciclos,
  required Color colorMarca,
}) async {
  final bytes = await generarCartolaAnualRendicionPdf(
    anio: anio,
    conductorNombre: conductorNombre,
    conductorRut: conductorRut,
    desde: desde,
    hasta: hasta,
    emision: emision,
    ciclos: ciclos,
    colorMarca: colorMarca,
  );
  await Printing.sharePdf(
    bytes: bytes,
    filename: 'cartola_rendicion_anual_${_rutArchivo(conductorRut)}_$anio.pdf',
  );
}

Future<Uint8List> generarCartolaRendicionPdf({
  required int numero,
  required String conductorNombre,
  required String conductorRut,
  required DateTime desde,
  required DateTime hasta,
  required DateTime emision,
  required List<ViajePlanilla> viajes,
  required Color colorMarca,
}) {
  return _generarPdf(
    titulo: 'Cartola de rendición N° $numero',
    subtitulo: 'Cartola de rendición',
    etiquetaCaja: 'CARTOLA N°',
    valorCaja: '$numero',
    conductorNombre: conductorNombre,
    conductorRut: conductorRut,
    desde: desde,
    hasta: hasta,
    emision: emision,
    viajes: viajes,
    colorMarca: colorMarca,
  );
}

Future<Uint8List> generarCartolaAnualRendicionPdf({
  required int anio,
  required String conductorNombre,
  required String conductorRut,
  required DateTime desde,
  required DateTime hasta,
  required DateTime emision,
  required List<CicloRendicionPdf> ciclos,
  required Color colorMarca,
}) {
  return _generarPdf(
    titulo: 'Cartola anual de rendiciones $anio',
    subtitulo: 'Cartola anual de rendiciones',
    etiquetaCaja: 'AÑO',
    valorCaja: '$anio',
    conductorNombre: conductorNombre,
    conductorRut: conductorRut,
    desde: desde,
    hasta: hasta,
    emision: emision,
    viajes: [for (final c in ciclos) ...c.viajes],
    porCiclo: ciclos,
    colorMarca: colorMarca,
  );
}

Future<Uint8List> _generarPdf({
  required String titulo,
  required String subtitulo,
  required String etiquetaCaja,
  required String valorCaja,
  required String conductorNombre,
  required String conductorRut,
  required DateTime desde,
  required DateTime hasta,
  required DateTime emision,
  required List<ViajePlanilla> viajes,
  List<CicloRendicionPdf>? porCiclo,
  required Color colorMarca,
}) async {
  final marca = PdfColor.fromInt(colorMarca.value);
  final texto = PdfColor.fromInt(0xFF111827);
  final gris = PdfColor.fromInt(0xFF6B7280);
  final lineaSuave = PdfColor.fromInt(0xFFE5E7EB);
  final zebra = PdfColor.fromInt(0xFFF9FAFB);

  // Cronológico, como una cartola bancaria.
  final filas = [...viajes]..sort((a, b) {
      final c = a.fecha.compareTo(b.fecha);
      return c != 0 ? c : a.numeroGuia.compareTo(b.numeroGuia);
    });
  final tot = _Totales.de(filas);

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
              pw.Expanded(flex: 4, child: campo('CONDUCTOR', conductorNombre)),
              pw.Expanded(flex: 3, child: campo('RUT', conductorRut)),
              pw.Expanded(flex: 2, child: campo('DESDE', _dmy(desde))),
              pw.Expanded(flex: 2, child: campo('HASTA', _dmy(hasta))),
              pw.Expanded(flex: 3, child: campo('FECHA DE EMISIÓN', _dmy(emision))),
              pw.Expanded(flex: 2, child: campo('VIAJES', '${filas.length}')),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget celda(String valor, {bool derecha = false, bool cabecera = false}) {
    return pw.Container(
      padding: pw.EdgeInsets.symmetric(horizontal: 4, vertical: cabecera ? 7 : 5),
      alignment: derecha ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
      child: pw.Text(
        valor,
        style: pw.TextStyle(
          fontSize: cabecera ? 7.5 : 8.5,
          fontWeight: cabecera ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: cabecera ? PdfColors.white : texto,
        ),
      ),
    );
  }

  /// Tabla con cabecera de color, filas alternadas y líneas suaves.
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
    // Mismas columnas y mismo orden que la planilla de rendición mensual.
    return tabla(
      cabeceras: [
        'N°',
        'FECHA VIAJE',
        'REGIÓN',
        'PATENTE',
        'FOLIO / N° DOC O GUÍA',
        'CLIENTE',
        'CONSIGNATARIO',
        'N° PALLETS',
        'CARGA O DESC. NOCTURNA (H)',
        'SÁBADOS (H)',
        'N° GUÍA PETRÓLEO',
        'TAG',
        'PEONETAS',
        'OBSERVACIONES',
      ],
      datos: [
        for (var i = 0; i < filas.length; i++)
          [
            '${i + 1}',
            _dmy(filas[i].fecha),
            filas[i].region,
            filas[i].patente,
            filas[i].numeroGuia,
            filas[i].cliente,
            filas[i].consignatario,
            '${filas[i].pallets}',
            _horas(filas[i].horasNocturnas),
            _horas(filas[i].horasSabado),
            filas[i].guiaPetroleo ?? '-',
            _clp(filas[i].montoTag),
            _clp(filas[i].montoPeonetas),
            filas[i].observacion ?? '-',
          ],
      ],
      anchos: {
        0: const pw.FixedColumnWidth(20),
        1: const pw.FixedColumnWidth(50),
        2: const pw.FlexColumnWidth(1.0),
        3: const pw.FixedColumnWidth(46),
        4: const pw.FixedColumnWidth(50),
        5: const pw.FlexColumnWidth(1.2),
        6: const pw.FlexColumnWidth(1.3),
        7: const pw.FixedColumnWidth(38),
        8: const pw.FixedColumnWidth(54),
        9: const pw.FixedColumnWidth(40),
        10: const pw.FixedColumnWidth(46),
        11: const pw.FixedColumnWidth(48),
        12: const pw.FixedColumnWidth(50),
        13: const pw.FlexColumnWidth(2.0),
      },
      derecha: {7, 8, 9, 11, 12},
      textoVacio: 'Sin viajes en este ciclo',
    );
  }

  /// Solo en la cartola anual: una fila por ciclo.
  pw.Widget tablaPorCiclo(List<CicloRendicionPdf> ciclos) {
    return tabla(
      cabeceras: ['CICLO', 'PERÍODO', 'VIAJES', 'PALLETS', 'H. NOCT.', 'H. SÁB.', 'TAG', 'PEONETAS'],
      datos: [
        for (final c in ciclos)
          () {
            final t = _Totales.de(c.viajes);
            return [
              '${c.numero}',
              '${_dmy(c.desde)} al ${_dmy(c.hasta)}',
              '${t.viajes}',
              '${t.pallets}',
              _horas(t.horasNocturnas),
              _horas(t.horasSabado),
              _clp(t.tag),
              _clp(t.peonetas),
            ];
          }(),
      ],
      anchos: {
        0: const pw.FixedColumnWidth(45),
        1: const pw.FlexColumnWidth(),
        2: const pw.FixedColumnWidth(55),
        3: const pw.FixedColumnWidth(55),
        4: const pw.FixedColumnWidth(60),
        5: const pw.FixedColumnWidth(60),
        6: const pw.FixedColumnWidth(80),
        7: const pw.FixedColumnWidth(80),
      },
      derecha: {2, 3, 4, 5, 6, 7},
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
            pw.Text(etiqueta, style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: gris)),
            pw.SizedBox(height: 4),
            pw.Text(valor, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: marca)),
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
          cajaResumen('TOTAL VIAJES', '${tot.viajes}'),
          separador(),
          cajaResumen('TOTAL PALLETS', '${tot.pallets}'),
          separador(),
          cajaResumen('H. NOCTURNAS', _horas(tot.horasNocturnas)),
          separador(),
          cajaResumen('H. SÁBADO', _horas(tot.horasSabado)),
          separador(),
          cajaResumen('TOTAL TAG', _clp(tot.tag)),
          separador(),
          cajaResumen('TOTAL PEONETAS', _clp(tot.peonetas)),
        ],
      ),
    );
  }

  // -------------------------------------------------------------- documento

  final doc = pw.Document(title: titulo, author: 'Transportes Contreras');

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape, // muchas columnas: horizontal
      margin: const pw.EdgeInsets.fromLTRB(32, 32, 32, 40),
      footer: (ctx) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 10),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Transportes Contreras - $titulo - $conductorNombre',
              style: pw.TextStyle(fontSize: 8, color: gris),
            ),
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
          tituloSeccion('DETALLE DE VIAJES'),
        ],
        tablaDetalle(),
        pw.SizedBox(height: 18),
        resumen(),
      ],
    ),
  );

  return doc.save();
}

class _Totales {
  const _Totales(this.viajes, this.pallets, this.horasNocturnas, this.horasSabado, this.tag, this.peonetas);

  factory _Totales.de(List<ViajePlanilla> v) => _Totales(
        v.length,
        v.fold<int>(0, (s, x) => s + x.pallets),
        v.fold<double>(0, (s, x) => s + x.horasNocturnas),
        v.fold<double>(0, (s, x) => s + x.horasSabado),
        v.fold<int>(0, (s, x) => s + (x.montoTag ?? 0)),
        v.fold<int>(0, (s, x) => s + (x.montoPeonetas ?? 0)),
      );

  final int viajes;
  final int pallets;
  final double horasNocturnas;
  final double horasSabado;
  final int tag;
  final int peonetas;
}

// ------------------------------------------------------------------ formatos

String _dos(int n) => n.toString().padLeft(2, '0');

/// 20/10/2026
String _dmy(DateTime d) => '${_dos(d.day)}/${_dos(d.month)}/${d.year}';

/// 2026-10-20 (para el nombre del archivo)
String _iso(DateTime d) => '${d.year}-${_dos(d.month)}-${_dos(d.day)}';

/// RUT sin puntos ni guion, para el nombre del archivo.
String _rutArchivo(String rut) => rut.replaceAll(RegExp(r'[^0-9kK]'), '');

String _miles(num n) => n.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => '.');

/// Pesos chilenos: $12.500. Sin monto, un guion.
String _clp(int? n) => n == null ? '-' : '\$${_miles(n)}';

String _horas(double h) => h == h.roundToDouble() ? _miles(h) : h.toStringAsFixed(1).replaceAll('.', ',');