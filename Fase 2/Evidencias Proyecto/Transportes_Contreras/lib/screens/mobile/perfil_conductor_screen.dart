import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../local_db/database_helper.dart';
import '../login_screen.dart';

class PerfilConductorScreen extends StatefulWidget {
  const PerfilConductorScreen({super.key});

  @override
  State<PerfilConductorScreen> createState() => _PerfilConductorScreenState();
}

class _PerfilConductorScreenState extends State<PerfilConductorScreen> {
  static const String _bucketDocumentos = 'documentos_identidad';

  String _nombre = 'Conductor';
  String _rut = '--';
  String _camionPatente = 'Sin asignar';
  int _viajesCompletados = 0;
  String? _urlCarnet;
  String? _urlLicencia;
  bool _isLoading = true;

  final Color _primaryColor = const Color(0xFF0F172A);
  final Color _orangeColor = const Color(0xFFE67E22);

  @override
  void initState() {
    super.initState();
    _cargarPerfil();
  }

  Future<void> _cargarPerfil() async {
    final sesion = await DatabaseHelper.instance.obtenerSesionConductor();
    if (sesion != null) {
      final rut = sesion['rut']?.toString() ?? '';
      final nombre = sesion['nombre_completo']?.toString() ?? 'Conductor';
      final camion = await DatabaseHelper.instance.obtenerCamionActualConductor(rut);
      final completados = await DatabaseHelper.instance.obtenerViajesPorEstado(rut, 'completado');

      String? urlCarnet;
      String? urlLicencia;
      try {
        final dataConductor = await Supabase.instance.client
            .from('conductores')
            .select('url_cedula_identidad, url_licencia_conducir')
            .eq('rut', rut)
            .maybeSingle();

        if (dataConductor != null) {
          urlCarnet = dataConductor['url_cedula_identidad']?.toString();
          urlLicencia = dataConductor['url_licencia_conducir']?.toString();
        }
      } catch (_) {
        // Si está sin conexión, se mantienen nulos sin bloquear la pantalla
      }

      if (mounted) {
        setState(() {
          _rut = rut;
          _nombre = nombre;
          _camionPatente = camion['patente'] ?? 'Sin asignar';
          _viajesCompletados = completados.length;
          _urlCarnet = urlCarnet;
          _urlLicencia = urlLicencia;
          _isLoading = false;
        });
      }
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<String?> _resolverUrlDocumento(String? rawPath) async {
    final limpia = (rawPath ?? '').trim();
    if (limpia.isEmpty || limpia.toLowerCase() == 'null') return null;
    if (limpia.startsWith('http://') || limpia.startsWith('https://')) {
      return limpia;
    }

    final storage = Supabase.instance.client.storage;
    try {
      return await storage.from(_bucketDocumentos).createSignedUrl(limpia, 3600);
    } catch (_) {
      return storage.from(_bucketDocumentos).getPublicUrl(limpia);
    }
  }

  Future<void> _abrirDocumento({
    required String titulo,
    required String? rutaArchivo,
  }) async {
    final rutaLimpia = (rutaArchivo ?? '').trim();

    if (rutaLimpia.isEmpty || rutaLimpia.toLowerCase() == 'null') {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.image_not_supported_outlined, color: _orangeColor, size: 22),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Documento no disponible',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Text(
            'Aún no se encuentra cargada la fotografía de: $titulo.',
            style: const TextStyle(fontSize: 13.5, color: Color(0xFF475569)),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(backgroundColor: _primaryColor),
              child: const Text('Entendido', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      return;
    }

    final urlResuelta = await _resolverUrlDocumento(rutaLimpia);
    if (!mounted) return;

    if (urlResuelta == null || urlResuelta.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo obtener el documento. Verifica tu conexión a internet.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (imgCtx) => Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(imgCtx).size.height * 0.8,
          ),
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.badge_outlined, color: _primaryColor, size: 20),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                titulo,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: _primaryColor,
                                ),
                              ),
                              Text(
                                'RUT: $_rut',
                                style: const TextStyle(fontSize: 11.5, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20, color: Colors.grey),
                    onPressed: () => Navigator.of(imgCtx).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(minHeight: 220),
                    color: _primaryColor,
                    child: InteractiveViewer(
                      minScale: 0.8,
                      maxScale: 4.0,
                      child: Image.network(
                        urlResuelta,
                        fit: BoxFit.contain,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return const SizedBox(
                            height: 260,
                            child: Center(
                              child: CircularProgressIndicator(color: Colors.white),
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return const SizedBox(
                            height: 220,
                            child: Center(
                              child: Padding(
                                padding: EdgeInsets.all(20),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.broken_image_outlined, color: Colors.white54, size: 40),
                                    SizedBox(height: 8),
                                    Text(
                                      'No se pudo cargar la imagen. Revisa tu conexión a internet.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: Colors.white70, fontSize: 12.5),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Pellizca la pantalla para hacer zoom en el documento',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _cerrarSesion() async {
    final confirmar = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar Sesión'),
        content: const Text('¿Está seguro que desea cerrar su sesión en este dispositivo?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cerrar Sesión', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    await DatabaseHelper.instance.cerrarSesionLocal();
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}

    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: _primaryColor,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Mi Perfil', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: _orangeColor))
          : SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                      child: Column(
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: _primaryColor,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Column(
                              children: [
                                CircleAvatar(
                                  radius: 38,
                                  backgroundColor: _orangeColor,
                                  child: Text(
                                    _nombre.isNotEmpty ? _nombre[0].toUpperCase() : 'C',
                                    style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  _nombre,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Conductor Profesional • Transportes Contreras',
                                  style: TextStyle(fontSize: 12, color: Colors.white70),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          _itemFicha(Icons.badge_outlined, 'RUT Trabajador', _rut),
                          _itemFicha(Icons.local_shipping_outlined, 'Camión Habitual / Asignado', _camionPatente),
                          _itemFicha(Icons.check_circle_outline, 'Viajes Completados (Histórico Local)', '$_viajesCompletados viajes'),

                          // Botones de Carnet y Licencia en la misma fila
                          Row(
                            children: [
                              Expanded(
                                child: _botonDocumento(
                                  icono: Icons.badge_outlined,
                                  titulo: 'Ver Carnet',
                                  subtitulo: 'Cédula identidad',
                                  onTap: () => _abrirDocumento(
                                    titulo: 'Cédula de Identidad',
                                    rutaArchivo: _urlCarnet,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _botonDocumento(
                                  icono: Icons.drive_eta_outlined,
                                  titulo: 'Ver Licencia',
                                  subtitulo: 'Licencia conducir',
                                  onTap: () => _abrirDocumento(
                                    titulo: 'Licencia de Conducir',
                                    rutaArchivo: _urlLicencia,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Botón Cerrar Sesión anclado abajo respetando gestos/barra de navegación Android
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: _cerrarSesion,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFDC2626),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: const Icon(Icons.logout, color: Colors.white),
                        label: const Text(
                          'CERRAR SESIÓN',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _botonDocumento({
    required IconData icono,
    required String titulo,
    required String subtitulo,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFFF1F5F9),
                child: Icon(icono, color: _primaryColor, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: _primaryColor),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitulo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10.5, color: Colors.grey, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _itemFicha(IconData icon, String label, String valor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: const Color(0xFFF1F5F9),
            child: Icon(icon, color: _primaryColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(valor, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _primaryColor)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}