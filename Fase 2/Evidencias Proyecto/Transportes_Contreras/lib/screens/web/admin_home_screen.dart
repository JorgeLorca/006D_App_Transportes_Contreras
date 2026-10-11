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

      // 1. Contar total de conductores (Sintaxis moderna)
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

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      selectedIndex: 0,
      title: 'Panel de Control',
      subtitle: 'Resumen de Operaciones',
      showBackButton: false,
      actions: [
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
      ],
      child: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
        : SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeroBanner(),
                const SizedBox(height: 24),
                
                // KPIs Superiores dinámicos
                Row(
                  children: [
                    Expanded(child: _buildKpiCard('VIAJES ACTIVOS', _viajesActivosCount.toString(), Icons.local_shipping, Colors.blue)),
                    const SizedBox(width: 16),
                    Expanded(child: _buildKpiCard('CARGAS PENDIENTES', _cargasPendientesCount.toString(), Icons.inventory_2, AppColors.warning)),
                    const SizedBox(width: 16),
                    Expanded(child: _buildKpiCard('CONDUCTORES', _conductoresCount.toString(), Icons.person, AppColors.success)),
                    const SizedBox(width: 16),
                    Expanded(child: _buildKpiCard('ALERTAS', _alertasCount.toString(), Icons.warning_amber_rounded, Colors.red)),
                  ],
                ),
                const SizedBox(height: 24),

                // Resumen Diario y Alertas
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 2, child: _buildResumenDiario()),
                    const SizedBox(width: 24),
                    Expanded(flex: 1, child: _buildAlertasCriticas()),
                  ],
                ),
                const SizedBox(height: 24),

                // Acciones Rápidas
                const Text('Acciones Rápidas', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    ElevatedButton.icon(
                      // push (no pushReplacement) para que "Descartar" en la
                      // pantalla de asignación vuelva al panel de control.
                      onPressed: () => Navigator.of(context).push(
                        PageRouteBuilder(
                          pageBuilder: (_, __, ___) => const AsignarViajeScreen(),
                          transitionDuration: Duration.zero,
                          reverseTransitionDuration: Duration.zero,
                        ),
                      ),
                      icon: const Icon(Icons.add, size: 16, color: Colors.white),
                      label: const Text('NUEVA CARGA', style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.picture_as_pdf, size: 16),
                      label: const Text('REPORTES PDF'),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16)),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.map, size: 16),
                      label: const Text('PLANIFICAR RUTA'),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16)),
                    ),
                    const Spacer(),
                    const Row(
                      children: [
                        Icon(Icons.check_circle, color: AppColors.success, size: 16),
                        SizedBox(width: 6),
                        Text('SISTEMA EN LÍNEA', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.bold, fontSize: 12)),
                      ],
                    )
                  ],
                ),
                const SizedBox(height: 32),

                // Tabla de Actividad
                const Text('Actividad Reciente de Flota', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _buildTablaActividad(),
              ],
            ),
          ),
    );
  }

  Widget _buildHeroBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
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
              const Text('Flota Operativa ACTUALIZADO: EN TIEMPO REAL', style: TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 16),
          const Text('ESTADO DE OPERACIONES', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 12)),
          const Text('Transportes Contreras', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
            child: const Text('Sincronizado con Central', style: TextStyle(color: Colors.white70, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface, 
        borderRadius: BorderRadius.circular(12), 
        border: Border.all(color: AppColors.border)
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textSecondary)),
              Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildResumenDiario() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Resumen Diario', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              TextButton(onPressed: (){}, child: const Text('Ver Detalles >', style: TextStyle(color: AppColors.primary)))
            ],
          ),
          const Text('Monitoreo de cumplimiento en tiempo real', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Cumplimiento de\nRutas', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const Text('Progreso Global de Despachos', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(child: LinearProgressIndicator(value: 0.85, backgroundColor: Colors.grey[200], color: AppColors.primary, minHeight: 8)),
                        const SizedBox(width: 12),
                        const Text('85%', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                      ],
                    )
                  ],
                ),
              ),
              const SizedBox(width: 40),
              Expanded(
                flex: 3,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatBox('A TIEMPO', '18', AppColors.success),
                    _buildStatBox('RETRASADOS', '4', Colors.red),
                    _buildStatBox('PENDIENTES', '2', Colors.grey),
                  ],
                ),
              )
            ],
          )
        ],
      ),
    );
  }

  Widget _buildStatBox(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  Widget _buildAlertasCriticas() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
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
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.red.withOpacity(0.05), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red.withOpacity(0.2))),
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
                    const Text('hace 10 min', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
                const SizedBox(height: 8),
                const Text('Camión CTR-402', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 4),
                const Text('Retraso detectado en Ruta 5 Sur por congestión vehicular.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    TextButton.icon(onPressed: (){}, icon: const Icon(Icons.phone, size: 14), label: const Text('Contactar Driver', style: TextStyle(fontSize: 12))),
                    TextButton.icon(onPressed: (){}, icon: const Icon(Icons.map, size: 14, color: AppColors.textSecondary), label: const Text('Ver Mapa', style: TextStyle(fontSize: 12, color: AppColors.textSecondary))),
                  ],
                )
              ],
            ),
          ),
          const SizedBox(height: 16),
          Center(child: TextButton(onPressed: (){}, child: const Text('Ver historial de alertas', style: TextStyle(color: AppColors.textSecondary)))),
        ],
      ),
    );
  }

  Widget _buildTablaActividad() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
      child: DataTable(
        headingTextStyle: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textSecondary, fontSize: 12),
        columns: const [
          DataColumn(label: Text('ID VIAJE')),
          DataColumn(label: Text('CAMIÓN / CHOFER')),
          DataColumn(label: Text('RUTA')),
          DataColumn(label: Text('ESTADO')),
        ],
        rows: _viajesRecientes.isNotEmpty
            ? _viajesRecientes.map((viaje) => _crearFila(
                viaje['id'].toString(),
                viaje['conductor_rut'] ?? 'Sin asignar', // Acá uniremos conductor y camión después
                viaje['clientes']?['nombre_empresa'] ?? 'Destino Pendiente',
                viaje['estado'] ?? 'desconocido',
              )).toList()
            // Datos de respaldo por si no hay viajes aún
            : [
                _crearFila('V-2845', 'Marco Soto', 'Santiago → Valparaíso', 'en_curso'),
                _crearFila('V-2846', 'Luis Rivas', 'Santiago → Concepción', 'retrasado'),
                _crearFila('V-2847', 'Elena Paz', 'Rancagua → Santiago', 'completado'),
              ],
      ),
    );
  }

  DataRow _crearFila(String id, String chofer, String ruta, String estadoStr) {
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

    return DataRow(cells: [
      DataCell(Text(id, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary))),
      DataCell(Text(chofer, style: const TextStyle(fontSize: 13))),
      DataCell(Text(ruta, style: const TextStyle(color: AppColors.textSecondary))),
      DataCell(Text(textoEstado, style: TextStyle(color: colorEstado, fontWeight: FontWeight.bold))),
    ]);
  }
}