import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_colors.dart';
import '../../widgets/admin_shell.dart';
import 'asignar_viaje_screen.dart';

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  bool _isLoading = true;

  // Contadores reales desde Supabase
  int _conductoresCount = 0;
  int _viajesActivosCount = 0;
  int _cargasPendientesCount = 0;
  int _alertasCount = 0;

  // Último incidente reportado
  Map<String, dynamic>? _ultimoIncidente;

  // Lista de viajes para la tabla inferior
  List<dynamic> _viajesRecientes = [];

  // Colores corporativos de incidentes sincronizados con la app móvil
  final Color _redAccidentColor = const Color(0xFFDC2626);
  final Color _yellowMechColor = const Color(0xFFD97706);
  final Color _orangeDelayColor = const Color(0xFFEA580C);

  // Control de expansión de descripción para el último incidente en el dashboard
  bool _descripcionExpandida = false;

  bool _recargandoIncidentes = false;

  @override
  void initState() {
    super.initState();
    _cargarMetricas();
  }

  Future<void> _cargarMetricas() async {
    try {
      final supabase = Supabase.instance.client;

      // 1. Contar total de conductores
      final int conductoresCount = await supabase
          .from('conductores')
          .count(CountOption.exact);

      // 2. Contar viajes en curso
      final int activosCount = await supabase
          .from('viajes')
          .count(CountOption.exact)
          .eq('estado', 'en_curso');

      // 3. Contar viajes pendientes
      final int pendientesCount = await supabase
          .from('viajes')
          .count(CountOption.exact)
          .eq('estado', 'pendiente');

      // 4. Contar total de incidentes reportados
      final int totalIncidentes = await supabase
          .from('incidentes')
          .count(CountOption.exact)
          .catchError((_) => 0);

      // 5. Obtener el último incidente reportado trayendo el nombre desde la tabla conductores
      final List<dynamic> incidentesData = await supabase
          .from('incidentes')
          .select('id, conductor_rut, tipo_incidente, gravedad, descripcion, latitud, longitud, reportado_en, conductores(nombre_completo, telefono)')
          .order('reportado_en', ascending: false)
          .limit(1)
          .catchError((_) => []);

      Map<String, dynamic>? ultimoIncidente;
      if (incidentesData.isNotEmpty) {
        ultimoIncidente = incidentesData.first as Map<String, dynamic>;
      }

      // 6. Obtener últimos 5 viajes para la tabla
      final viajesData = await supabase
          .from('viajes')
          .select('id, estado, fecha_viaje, conductor_rut, clientes(nombre_empresa)')
          .order('fecha_viaje', ascending: false)
          .limit(5)
          .catchError((_) => []);

      if (mounted) {
        setState(() {
          _conductoresCount = conductoresCount;
          _viajesActivosCount = activosCount;
          _cargasPendientesCount = pendientesCount;
          _alertasCount = totalIncidentes;
          _ultimoIncidente = ultimoIncidente;
          _viajesRecientes = viajesData as List<dynamic>;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error cargando métricas del admin: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<dynamic> get _filasAMostrar {
    if (_viajesRecientes.isNotEmpty) {
      return _viajesRecientes;
    }
    return [
      {'id': 'V-2845', 'conductor_rut': 'Marco Soto', 'ruta': 'Santiago → Valparaíso', 'estado': 'en_curso'},
      {'id': 'V-2846', 'conductor_rut': 'Luis Rivas', 'ruta': 'Santiago → Concepción', 'estado': 'retrasado'},
      {'id': 'V-2847', 'conductor_rut': 'Elena Paz', 'ruta': 'Rancagua → Santiago', 'estado': 'completado'},
    ];
  }

  /// Formatea UUIDs largos a un código legible y elegante (ej. #D458F846)
  String _formatearId(String rawId) {
    if (rawId.length > 8) {
      return '#${rawId.substring(0, 8).toUpperCase()}';
    }
    return rawId.startsWith('#') ? rawId : '#$rawId';
  }

  /// Formatea tiempo transcurrido (hace X min, hace X h, etc.)
  String _formatearTiempoRelativo(String? timestampStr) {
    if (timestampStr == null || timestampStr.isEmpty) return 'reciente';
    final dt = DateTime.tryParse(timestampStr);
    if (dt == null) return 'reciente';

    final diferencia = DateTime.now().toUtc().difference(dt.toUtc());

    if (diferencia.inSeconds < 60) return 'hace un momento';
    if (diferencia.inMinutes < 60) return 'hace ${diferencia.inMinutes} min';
    if (diferencia.inHours < 24) return 'hace ${diferencia.inHours} h';
    if (diferencia.inDays < 7) return 'hace ${diferencia.inDays} d';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  /// Gestiona el contacto con el conductor según si el dispositivo es un teléfono real o un PC
  Future<void> _contactarConductor(String rutConductor, [String? nombreInicial]) async {
    String telefono = '';
    String nombre = nombreInicial ?? 'Conductor';

    try {
      final res = await Supabase.instance.client
          .from('conductores')
          .select('nombre_completo, telefono')
          .eq('rut', rutConductor)
          .maybeSingle();

      if (res != null) {
        telefono = (res['telefono'] ?? '').toString().trim();
        final String nombreDb = (res['nombre_completo'] ?? '').toString().trim();
        if (nombreDb.isNotEmpty) nombre = nombreDb;
      }
    } catch (e) {
      debugPrint('Error obteniendo teléfono del conductor: $e');
    }

    if (telefono.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('El conductor no registra un número telefónico en su ficha.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final String soloNumeros = telefono.replaceAll(RegExp(r'[^0-9+]'), '');
    final String numeroLimpio = soloNumeros.startsWith('+') ? soloNumeros : '+56$soloNumeros';

    // Detección de dispositivo físico real mediante User-Agent
    final String userAgent = html.window.navigator.userAgent.toLowerCase();
    final bool esTelefonoReal = userAgent.contains('android') ||
        userAgent.contains('iphone') ||
        userAgent.contains('ipad') ||
        userAgent.contains('mobile');

    if (esTelefonoReal) {
      // Abre el marcador nativo del teléfono sin realizar la llamada automáticamente
      html.window.location.href = 'tel:$numeroLimpio';
    } else {
      // En PC: Muestra el modal con el nombre y RUT, número para copiar y opción de WhatsApp Web
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: const [
                Icon(Icons.phone_in_talk, color: AppColors.primary, size: 22),
                SizedBox(width: 10),
                Text('Contacto del Conductor', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nombre, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                Text('RUT: $rutConductor', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.phone, size: 18, color: Colors.green),
                          const SizedBox(width: 8),
                          SelectableText(
                            telefono,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 18, color: AppColors.textSecondary),
                        tooltip: 'Copiar número',
                        onPressed: () {
                          html.window.navigator.clipboard?.writeText(telefono);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Número copiado al portapapeles'), duration: Duration(seconds: 2)),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Desde PC no es posible realizar llamadas directas. Puede copiar el número o abrir una conversación directa en WhatsApp Web.',
                  style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                ),
              ],
            ),
            actions: [
              OutlinedButton.icon(
                onPressed: () {
                  final wsUrl =
                      'https://web.whatsapp.com/send?phone=${numeroLimpio.replaceAll('+', '')}&text=${Uri.encodeComponent('Hola $nombre, nos comunicamos desde la administración de Transportes Contreras respecto a su reporte en ruta.')}';
                  html.window.open(wsUrl, '_blank');
                  Navigator.of(ctx).pop();
                },
                icon: const Icon(Icons.chat, size: 16, color: Colors.green),
                label: const Text('Abrir WhatsApp Web', style: TextStyle(color: Colors.green, fontSize: 12)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                child: const Text('Cerrar', style: TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ],
          );
        },
      );
    }
  }

  /// Abre un modal independiente sobre cualquier vista para mostrar el mapa interactivo
  void _abrirModalMapa({
    required double lat,
    required double lng,
    required String titulo,
    required String conductor,
    required String descripcion,
    required Color colorAlerta,
  }) {
    final String viewType = 'map-view-${lat.toStringAsFixed(4)}-${lng.toStringAsFixed(4)}-${DateTime.now().millisecondsSinceEpoch}';

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

    showDialog(
      context: context,
      builder: (mapCtx) {
        final screenWidth = MediaQuery.of(mapCtx).size.width;
        final isMobileModal = screenWidth < 600;

        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: Colors.white,
          insetPadding: EdgeInsets.symmetric(
            horizontal: isMobileModal ? 12 : 24,
            vertical: 24,
          ),
          child: Container(
            width: 750,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(mapCtx).size.height * 0.88,
            ),
            padding: EdgeInsets.all(isMobileModal ? 16 : 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Cabecera del modal
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: colorAlerta.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.location_on, color: colorAlerta, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  titulo,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Conductor: $conductor',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppColors.textSecondary, size: 20),
                      tooltip: 'Cerrar Mapa',
                      onPressed: () => Navigator.of(mapCtx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Contenedor del Mapa Interactivo
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: HtmlElementView(viewType: viewType),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                // Pie Responsivo
                LayoutBuilder(
                  builder: (context, constraints) {
                    final bool estrecho = constraints.maxWidth < 480;

                    if (estrecho) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.my_location, size: 14, color: AppColors.textSecondary),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Coords: ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 38,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                html.window.open('https://www.google.com/maps/search/?api=1&query=$lat,$lng', '_blank');
                              },
                              icon: const Icon(Icons.open_in_new, size: 14),
                              label: const Text('Abrir en Google Maps', style: TextStyle(fontSize: 12)),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: AppColors.border),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                        ],
                      );
                    }

                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.my_location, size: 14, color: AppColors.textSecondary),
                            const SizedBox(width: 6),
                            Text(
                              'Coordenadas: ${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        OutlinedButton.icon(
                          onPressed: () {
                            html.window.open('https://www.google.com/maps/search/?api=1&query=$lat,$lng', '_blank');
                          },
                          icon: const Icon(Icons.open_in_new, size: 14),
                          label: const Text('Abrir en Google Maps', style: TextStyle(fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            side: const BorderSide(color: AppColors.border),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 900;
    final bool isSmallMobile = screenWidth < 750;

    return AdminShell(
      selectedIndex: 0,
      title: 'Panel de Control',
      subtitle: 'Resumen de Operaciones',
      showBackButton: false,
      actions: [
        if (!isSmallMobile)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: const Row(
              children: [
                Icon(Icons.search, size: 16, color: AppColors.textSecondary),
                SizedBox(width: 8),
                Text('Buscar viajes, rutas...', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              ],
            ),
          )
        else
          IconButton(
            icon: const Icon(Icons.search, color: AppColors.textSecondary),
            tooltip: 'Buscar',
            onPressed: () {},
          ),
      ],
      child: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : SingleChildScrollView(
              padding: EdgeInsets.all(isSmallMobile ? 16.0 : 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeroBanner(isSmallMobile),
                  const SizedBox(height: 24),

                  // 1. KPIs Superiores Responsivos
                  _buildKpisSection(isMobile),
                  const SizedBox(height: 24),

                  // 2. Resumen Diario y Alertas Críticas
                  if (!isMobile)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 2, child: _buildResumenDiario(isSmallMobile)),
                        const SizedBox(width: 24),
                        Expanded(flex: 1, child: _buildAlertasCriticas()),
                      ],
                    )
                  else ...[
                    _buildResumenDiario(isSmallMobile),
                    const SizedBox(height: 24),
                    _buildAlertasCriticas(),
                  ],

                  const SizedBox(height: 24),

                  // 3. Acciones Rápidas Responsivas
                  const Text('Acciones Rápidas', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  _buildAccionesRapidas(isSmallMobile),
                  const SizedBox(height: 32),

                  // 4. Tabla de Actividad Reciente
                  const Text('Actividad Reciente de Flota', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  _buildTablaActividadOriginal(isSmallMobile),
                ],
              ),
            ),
    );
  }

  Widget _buildHeroBanner(bool isSmallMobile) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isSmallMobile ? 20 : 32),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Flota Operativa ACTUALIZADO: EN TIEMPO REAL',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('ESTADO DE OPERACIONES', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 11)),
          Text(
            'Transportes Contreras',
            style: TextStyle(color: Colors.white, fontSize: isSmallMobile ? 24 : 32, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
            child: const Text('Sincronizado con Central', style: TextStyle(color: Colors.white70, fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Widget _buildKpisSection(bool isMobile) {
    final kpis = [
      _KpiData('VIAJES ACTIVOS', _viajesActivosCount.toString(), Icons.local_shipping, Colors.blue),
      _KpiData('CARGAS PENDIENTES', _cargasPendientesCount.toString(), Icons.inventory_2, AppColors.warning),
      _KpiData('CONDUCTORES', _conductoresCount.toString(), Icons.person, AppColors.success),
      _KpiData('INCIDENTES', _alertasCount.toString(), Icons.warning_amber_rounded, Colors.red),
    ];

    if (!isMobile) {
      return Row(
        children: kpis
            .map((kpi) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6.0),
                    child: _buildKpiCard(kpi.title, kpi.value, kpi.icon, kpi.color),
                  ),
                ))
            .toList(),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: kpis.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.8,
      ),
      itemBuilder: (context, index) {
        final kpi = kpis[index];
        return _buildKpiCard(kpi.title, kpi.value, kpi.icon, kpi.color);
      },
    );
  }

  Widget _buildKpiCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildResumenDiario(bool isSmallMobile) {
    return Container(
      padding: EdgeInsets.all(isSmallMobile ? 16 : 24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Resumen Diario', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              TextButton(onPressed: () {}, child: const Text('Ver Detalles >', style: TextStyle(color: AppColors.primary)))
            ],
          ),
          const Text('Monitoreo de cumplimiento en tiempo real', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 24),
          if (!isSmallMobile)
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _buildProgresoRutas(),
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 3,
                  child: _buildEstadisticasConteo(),
                )
              ],
            )
          else ...[
            _buildProgresoRutas(),
            const SizedBox(height: 20),
            const Divider(color: AppColors.border),
            const SizedBox(height: 12),
            _buildEstadisticasConteo(),
          ],
        ],
      ),
    );
  }

  Widget _buildProgresoRutas() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Cumplimiento de Rutas', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const Text('Progreso Global de Despachos', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: LinearProgressIndicator(
                value: 0.85,
                backgroundColor: Colors.grey[200],
                color: AppColors.primary,
                minHeight: 8,
              ),
            ),
            const SizedBox(width: 12),
            const Text('85%', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ],
        )
      ],
    );
  }

  Widget _buildEstadisticasConteo() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildStatBox('A TIEMPO', '18', AppColors.success),
        _buildStatBox('RETRASADOS', '4', Colors.red),
        _buildStatBox('PENDIENTES', '2', Colors.grey),
      ],
    );
  }

  Widget _buildStatBox(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  Widget _buildAlertasCriticas() {
    // 1. Caso: No hay incidentes en la base de datos
    if (_ultimoIncidente == null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.grey, size: 20),
                    SizedBox(width: 8),
                    Text('Registro de Incidentes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                _recargandoIncidentes
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                      )
                    : IconButton(
                        icon: const Icon(Icons.refresh, color: AppColors.textSecondary, size: 20),
                        tooltip: 'Recargar incidentes',
                        onPressed: _recargarIncidentes,
                      ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: const Text(
                'Sin incidentes reportados recientemente.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed: _abrirModalHistorialAlertas,
                child: const Text('Ver historial de alertas', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ),
            ),
          ],
        ),
      );
    }

    // 2. Mapeo de datos del último incidente
    final String tipoRaw = (_ultimoIncidente!['tipo_incidente'] ?? 'retraso').toString().toLowerCase();
    final String gravedadRaw = (_ultimoIncidente!['gravedad'] ?? 'leve').toString().toLowerCase();
    final String conductorRut = (_ultimoIncidente!['conductor_rut'] ?? '').toString();
    final String conductorNombre = (_ultimoIncidente!['conductores']?['nombre_completo'] ?? conductorRut).toString();
    final String descripcion = (_ultimoIncidente!['descripcion'] ?? 'Sin detalle reportado').toString();
    final String tiempoRelativo = _formatearTiempoRelativo(_ultimoIncidente!['reportado_en']?.toString());
    final double lat = double.tryParse(_ultimoIncidente!['latitud']?.toString() ?? '') ?? -33.437514;
    final double lng = double.tryParse(_ultimoIncidente!['longitud']?.toString() ?? '') ?? -70.782836;

    Color colorBase = _orangeDelayColor;
    String tituloTipo = 'Retraso Operativo';

    if (tipoRaw == 'accidente') {
      colorBase = _redAccidentColor;
      tituloTipo = 'Accidente en Ruta';
    } else if (tipoRaw == 'falla_mecanica') {
      colorBase = _yellowMechColor;
      tituloTipo = 'Falla Mecánica';
    }

    String textoGravedad = 'Leve';
    if (gravedadRaw == 'moderada') {
      textoGravedad = 'Moderada';
    } else if (gravedadRaw == 'grave') {
      textoGravedad = 'Grave';
    }

    final bool esTextoLargo = descripcion.split('\n').length > 5 || descripcion.length > 200;

    // 3. Render con la tarjeta de alerta coloreada
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: colorBase, size: 20),
                  const SizedBox(width: 8),
                  const Text('Registro de Incidentes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              _recargandoIncidentes
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                    )
                  : IconButton(
                      icon: const Icon(Icons.refresh, color: AppColors.textSecondary, size: 20),
                      tooltip: 'Recargar incidentes',
                      onPressed: _recargarIncidentes,
                    ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colorBase.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colorBase.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: colorBase,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              tituloTipo.toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            '•',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            textoGravedad,
                            style: TextStyle(
                              color: colorBase,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      tiempoRelativo,
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Conductor: $conductorNombre',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 4),

                Text(
                  descripcion,
                  maxLines: _descripcionExpandida ? null : 5,
                  overflow: _descripcionExpandida ? TextOverflow.visible : TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),

                if (esTextoLargo) ...[
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () {
                      setState(() {
                        _descripcionExpandida = !_descripcionExpandida;
                      });
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2.0),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _descripcionExpandida ? 'Mostrar menos' : 'Mostrar más',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: colorBase,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(
                            _descripcionExpandida ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                            size: 16,
                            color: colorBase,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: () => _contactarConductor(conductorRut, conductorNombre),
                      icon: const Icon(Icons.phone, size: 14),
                      label: const Text('Contactar Conductor', style: TextStyle(fontSize: 12)),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        _abrirModalMapa(
                          lat: lat,
                          lng: lng,
                          titulo: tituloTipo,
                          conductor: conductorNombre,
                          descripcion: descripcion,
                          colorAlerta: colorBase,
                        );
                      },
                      icon: const Icon(Icons.map, size: 14, color: AppColors.textSecondary),
                      label: const Text('Ver Mapa', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ),
                  ],
                )
              ],
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: _abrirModalHistorialAlertas,
              child: const Text('Ver historial de alertas', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccionesRapidas(bool isSmallMobile) {
    final botones = [
      ElevatedButton.icon(
        onPressed: () => Navigator.of(context).push(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const AsignarViajeScreen(),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          ),
        ),
        icon: const Icon(Icons.add, size: 16, color: Colors.white),
        label: const Text('NUEVA CARGA', style: TextStyle(color: Colors.white, fontSize: 12)),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      OutlinedButton.icon(
        onPressed: () {},
        icon: const Icon(Icons.picture_as_pdf, size: 16),
        label: const Text('REPORTES PDF', style: TextStyle(fontSize: 12)),
        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
      ),
      OutlinedButton.icon(
        onPressed: () {},
        icon: const Icon(Icons.map, size: 16),
        label: const Text('PLANIFICAR RUTA', style: TextStyle(fontSize: 12)),
        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
      ),
    ];

    if (!isSmallMobile) {
      return Row(
        children: [
          ...botones.map((b) => Padding(padding: const EdgeInsets.only(right: 12.0), child: b)),
          const Spacer(),
          const Row(
            children: [
              Icon(Icons.check_circle, color: AppColors.success, size: 16),
              SizedBox(width: 6),
              Text('SISTEMA EN LÍNEA', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          )
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: botones,
        ),
        const SizedBox(height: 12),
        const Row(
          children: [
            Icon(Icons.check_circle, color: AppColors.success, size: 14),
            SizedBox(width: 6),
            Text('SISTEMA EN LÍNEA', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.bold, fontSize: 11)),
          ],
        )
      ],
    );
  }

  // Tabla con separación definida y sin colisión entre ID y Chofer
  Widget _buildTablaActividadOriginal(bool isSmallMobile) {
    final filas = _filasAMostrar;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: isSmallMobile
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: 720,
                child: Column(
                  children: [
                    _buildEncabezadoActividadMovil(),
                    ...filas.map((item) => Column(
                          children: [
                            _buildFilaActividadMovil(item),
                            const Divider(height: 1, color: Color(0xFFF1F5F9)),
                          ],
                        )),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                _buildEncabezadoActividadPC(),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filas.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                  itemBuilder: (context, index) {
                    return _buildFilaActividadPC(filas[index]);
                  },
                ),
              ],
            ),
    );
  }

  // --- MÓVIL ---
  Widget _buildEncabezadoActividadMovil() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: const [
          SizedBox(width: 140, child: Text('ID VIAJE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
          SizedBox(width: 20),
          SizedBox(width: 160, child: Text('CAMIÓN / CHOFER', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
          SizedBox(width: 20),
          SizedBox(width: 200, child: Text('RUTA', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
          SizedBox(width: 20),
          SizedBox(width: 120, child: Text('ESTADO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
        ],
      ),
    );
  }

  Widget _buildFilaActividadMovil(dynamic item) {
    final String rawId = item['id'].toString();
    final String idCorto = _formatearId(rawId);
    final String chofer = (item['conductor_rut'] ?? 'Sin asignar').toString();
    final String ruta = (item['clientes']?['nombre_empresa'] ?? item['ruta'] ?? 'Destino Pendiente').toString();
    final String estadoStr = (item['estado'] ?? 'desconocido').toString();

    Color colorEstado;
    String textoEstado;

    switch (estadoStr.toLowerCase()) {
      case 'en_curso':
      case 'en ruta':
        colorEstado = Colors.green;
        textoEstado = 'En Ruta';
        break;
      case 'retrasado':
        colorEstado = Colors.red;
        textoEstado = 'Retrasado';
        break;
      case 'completado':
        colorEstado = Colors.grey;
        textoEstado = 'Completado';
        break;
      default:
        colorEstado = AppColors.warning;
        textoEstado = 'Pendiente';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(
              idCorto,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 13),
            ),
          ),
          const SizedBox(width: 20),
          SizedBox(
            width: 160,
            child: Text(
              chofer,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: AppColors.textPrimary, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 20),
          SizedBox(
            width: 200,
            child: Text(
              ruta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(width: 20),
          SizedBox(
            width: 120,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colorEstado.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  textoEstado,
                  style: TextStyle(color: colorEstado, fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- PC ---
  Widget _buildEncabezadoActividadPC() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: const [
          Expanded(flex: 2, child: Text('ID VIAJE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
          SizedBox(width: 16),
          Expanded(flex: 3, child: Text('CAMIÓN / CHOFER', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
          SizedBox(width: 16),
          Expanded(flex: 4, child: Text('RUTA', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
          SizedBox(width: 16),
          Expanded(flex: 2, child: Text('ESTADO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
        ],
      ),
    );
  }

  Widget _buildFilaActividadPC(dynamic item) {
    final String rawId = item['id'].toString();
    final String idCorto = _formatearId(rawId);
    final String chofer = (item['conductor_rut'] ?? 'Sin asignar').toString();
    final String ruta = (item['clientes']?['nombre_empresa'] ?? item['ruta'] ?? 'Destino Pendiente').toString();
    final String estadoStr = (item['estado'] ?? 'desconocido').toString();

    Color colorEstado;
    String textoEstado;

    switch (estadoStr.toLowerCase()) {
      case 'en_curso':
      case 'en ruta':
        colorEstado = Colors.green;
        textoEstado = 'En Ruta';
        break;
      case 'retrasado':
        colorEstado = Colors.red;
        textoEstado = 'Retrasado';
        break;
      case 'completado':
        colorEstado = Colors.grey;
        textoEstado = 'Completado';
        break;
      default:
        colorEstado = AppColors.warning;
        textoEstado = 'Pendiente';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              idCorto,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 13),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 3,
            child: Text(
              chofer,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: AppColors.textPrimary, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 4,
            child: Text(
              ruta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colorEstado.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  textoEstado,
                  style: TextStyle(color: colorEstado, fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Abre el diálogo modal con el listado completo de alertas
  void _abrirModalHistorialAlertas() {
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: Colors.white,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Container(
            width: 650,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.82,
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Cabecera del Modal con botón de cierre (X)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.history_rounded, color: AppColors.primary, size: 22),
                        SizedBox(width: 10),
                        Text(
                          'Historial de Incidentes',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppColors.textSecondary, size: 20),
                      tooltip: 'Cerrar',
                      onPressed: () => Navigator.of(dialogCtx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Registro histórico de todos los incidentes, retrasos y reportes emitidos en ruta.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                const Divider(height: 1, color: AppColors.border),
                const SizedBox(height: 16),

                // Lista de incidentes desde Supabase trayendo la relación con conductores
                Expanded(
                  child: FutureBuilder<List<dynamic>>(
                    future: Supabase.instance.client
                        .from('incidentes')
                        .select('id, conductor_rut, tipo_incidente, gravedad, descripcion, latitud, longitud, reportado_en, conductores(nombre_completo, telefono)')
                        .order('reportado_en', ascending: false),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(color: AppColors.primary),
                        );
                      }

                      if (snapshot.hasError) {
                        return Center(
                          child: Text(
                            'Error al cargar el historial: ${snapshot.error}',
                            style: const TextStyle(color: Colors.red, fontSize: 13),
                          ),
                        );
                      }

                      final List<dynamic> incidentes = snapshot.data ?? [];

                      if (incidentes.isEmpty) {
                        return const Center(
                          child: Text(
                            'No hay incidentes registrados en el sistema.',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                          ),
                        );
                      }

                      return ListView.separated(
                        itemCount: incidentes.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 14),
                        itemBuilder: (context, index) {
                          final item = Map<String, dynamic>.from(incidentes[index] as Map);
                          return _buildTarjetaIncidente(item);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Construye la tarjeta individual respetando los colores y estructura visual
  Widget _buildTarjetaIncidente(Map<String, dynamic> item) {
    final String tipoRaw = (item['tipo_incidente'] ?? 'retraso').toString().toLowerCase();
    final String gravedadRaw = (item['gravedad'] ?? 'leve').toString().toLowerCase();
    final String conductorRut = (item['conductor_rut'] ?? '').toString();
    final String conductorNombre = (item['conductores']?['nombre_completo'] ?? conductorRut).toString();
    final String descripcion = (item['descripcion'] ?? 'Sin detalle reportado').toString();
    final String tiempoRelativo = _formatearTiempoRelativo(item['reportado_en']?.toString());
    final double lat = double.tryParse(item['latitud']?.toString() ?? '') ?? -33.437514;
    final double lng = double.tryParse(item['longitud']?.toString() ?? '') ?? -70.782836;

    Color colorBase = _orangeDelayColor;
    String tituloTipo = 'Retraso Operativo';

    if (tipoRaw == 'accidente') {
      colorBase = _redAccidentColor;
      tituloTipo = 'Accidente en Ruta';
    } else if (tipoRaw == 'falla_mecanica') {
      colorBase = _yellowMechColor;
      tituloTipo = 'Falla Mecánica';
    }

    String textoGravedad = 'Leve';
    if (gravedadRaw == 'moderada') {
      textoGravedad = 'Moderada';
    } else if (gravedadRaw == 'grave') {
      textoGravedad = 'Grave';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorBase.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorBase.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: colorBase,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        tituloTipo.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      '•',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      textoGravedad,
                      style: TextStyle(
                        color: colorBase,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                tiempoRelativo,
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Conductor: $conductorNombre',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            descripcion,
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: () => _contactarConductor(conductorRut, conductorNombre),
                icon: const Icon(Icons.phone, size: 14),
                label: const Text('Contactar Conductor', style: TextStyle(fontSize: 12)),
              ),
              TextButton.icon(
                onPressed: () {
                  _abrirModalMapa(
                    lat: lat,
                    lng: lng,
                    titulo: tituloTipo,
                    conductor: conductorNombre,
                    descripcion: descripcion,
                    colorAlerta: colorBase,
                  );
                },
                icon: const Icon(Icons.map, size: 14, color: AppColors.textSecondary),
                label: const Text('Ver Mapa', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ),
            ],
          )
        ],
      ),
    );
  }

  Future<void> _recargarIncidentes() async {
    setState(() => _recargandoIncidentes = true);
    try {
      final supabase = Supabase.instance.client;

      final int totalIncidentes = await supabase
          .from('incidentes')
          .count(CountOption.exact)
          .catchError((_) => 0);

      final List<dynamic> incidentesData = await supabase
          .from('incidentes')
          .select('id, conductor_rut, tipo_incidente, gravedad, descripcion, latitud, longitud, reportado_en, conductores(nombre_completo, telefono)')
          .order('reportado_en', ascending: false)
          .limit(1)
          .catchError((_) => []);

      Map<String, dynamic>? ultimoIncidente;
      if (incidentesData.isNotEmpty) {
        ultimoIncidente = incidentesData.first as Map<String, dynamic>;
      }

      if (mounted) {
        setState(() {
          _alertasCount = totalIncidentes;
          _ultimoIncidente = ultimoIncidente;
          _recargandoIncidentes = false;
        });
      }
    } catch (e) {
      debugPrint('Error recargando incidentes: $e');
      if (mounted) setState(() => _recargandoIncidentes = false);
    }
  }
}

class _KpiData {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  _KpiData(this.title, this.value, this.icon, this.color);
}