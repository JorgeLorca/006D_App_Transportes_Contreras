// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
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
        ..allowFullscreen = true
        ..src = 'https://maps.google.com/maps?q=$lat,$lng&hl=es&z=16&output=embed';
      return iframe;
    },
  );
}

Widget construirVistaMapaWeb(String viewType) {
  return HtmlElementView(viewType: viewType);
}