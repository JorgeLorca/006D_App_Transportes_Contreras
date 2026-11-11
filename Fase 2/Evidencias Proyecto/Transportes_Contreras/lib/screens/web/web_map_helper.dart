// Exporta la implementación web si está compilando para web, o el stub si compila para móvil/apk
export 'web_map_stub.dart'
    if (dart.library.html) 'web_map_impl.dart';