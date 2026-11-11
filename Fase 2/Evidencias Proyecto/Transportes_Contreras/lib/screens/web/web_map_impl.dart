import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';

void registrarIFrameMapa(String viewType, double lat, double lng) {
  ui_web.platformViewRegistry.registerViewFactory(
    viewType,
    (int viewId) {
      final iframe = html.IFrameElement()
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.position = 'absolute'
        ..style.top = '0'
        ..style.left = '0'
        ..style.right = '0'
        ..style.bottom = '0'
        ..style.border = 'none'
        ..style.display = 'block'
        ..src = 'https://www.openstreetmap.org/export/embed.html?bbox=${lng - 0.015}%2C${lat - 0.010}%2C${lng + 0.015}%2C${lat + 0.010}&layer=mapnik&marker=$lat%2C$lng';
      return iframe;
    },
  );
}

Widget construirVistaMapaWeb(String viewType) {
  return HtmlElementView(viewType: viewType);
}