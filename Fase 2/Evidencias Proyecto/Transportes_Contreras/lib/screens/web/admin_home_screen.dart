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
  final int _alertasCount = 3; // Simulado temporalmente hasta crear la tabla de alertas

  // Lista de viajes para la tabla inferior
  List<dynamic> _viajesRecientes = [];

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

      // 4. Obtener últimos 5 viajes para la tabla
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

                  // 4. Tabla de Actividad Reciente con separación óptima entre columnas
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
      _KpiData('ALERTAS', _alertasCount.toString(), Icons.warning_amber_rounded, Colors.red),
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
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red, size: 20),
              SizedBox(width: 8),
              Text('Alertas Críticas', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)),
                      child: const Text('RETRASO', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                    const Text('hace 10 min', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                  ],
                ),
                const SizedBox(height: 8),
                const Text('Camión CTR-402', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 4),
                const Text(
                  'Retraso detectado en Ruta 5 Sur por congestión vehicular.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.phone, size: 14),
                      label: const Text('Contactar Driver', style: TextStyle(fontSize: 12)),
                    ),
                    TextButton.icon(
                      onPressed: () {},
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
              onPressed: () {},
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
          // EN MÓVIL: Scroll lateral con anchos definidos y margen entre columnas
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
          // EN PC: 100% de ancho con proporciones y paddings idénticos a Trabajadores
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
          // ID corto que nunca se corta ni deforma
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
}

class _KpiData {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  _KpiData(this.title, this.value, this.icon, this.color);
}