import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'login_screen.dart'; // Asegúrate de que la ruta sea correcta

class ConductorHome extends StatefulWidget {
  const ConductorHome({super.key});

  @override
  State<ConductorHome> createState() => _ConductorHomeState();
}

class _ConductorHomeState extends State<ConductorHome> {
  int _selectedIndex = 0;
  bool _isLoading = true;
  String _nombreConductor = 'Conductor';
  
  Map<String, dynamic>? _viajeActivo;
  List<dynamic> _viajesPendientes = [];
  int _totalViajesMes = 0;

  @override
  void initState() {
    super.initState();
    _cargarDatosDashboard();
  }

  Future<void> _cargarDatosDashboard() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;

      // 1. Obtener datos del perfil del conductor
      final perfil = await Supabase.instance.client
          .from('conductores')
          .select('rut, nombre_completo')
          .eq('auth_id', userId)
          .single();

      _nombreConductor = perfil['nombre_completo'];
      final rut = perfil['rut'];

      // 2. Obtener Viaje Activo (En Curso)
      final activoData = await Supabase.instance.client
          .from('viajes')
          .select('*, clientes(nombre_empresa)')
          .eq('conductor_rut', rut)
          .eq('estado', 'en_curso')
          .maybeSingle();

      // 3. Obtener Próximas Asignaciones (Pendientes)
      final pendientesData = await Supabase.instance.client
          .from('viajes')
          .select('*, clientes(nombre_empresa)')
          .eq('conductor_rut', rut)
          .eq('estado', 'pendiente')
          .order('fecha_viaje', ascending: true)
          .limit(3); // Mostramos solo las próximas 3

      // 4. Contar viajes del mes (Simulación para el indicador numérico)
      final countResponse = await Supabase.instance.client
          .from('viajes')
          .select('id')
          .eq('conductor_rut', rut)
          .eq('estado', 'completado'); // Idealmente filtrar por fecha_viaje del mes actual

      if (mounted) {
        setState(() {
          _viajeActivo = activoData;
          _viajesPendientes = pendientesData;
          _totalViajesMes = countResponse.length;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error cargando dashboard: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
    // Aquí luego agregarás la navegación a las otras vistas del BottomNav
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF3F4F6),
        body: Center(child: CircularProgressIndicator(color: Color(0xFFE67E22))),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.local_shipping, color: Colors.white, size: 24),
            SizedBox(width: 8),
            Text('TRANSPORTES CONTRERAS', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none, color: Colors.white),
            onPressed: () {},
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- HEADER: Saludo y Estado Sincronización ---
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Panel de Inicio', style: TextStyle(color: Colors.grey, fontSize: 14)),
                    Text(
                      'Bienvenido,\n${_nombreConductor.split(' ').first}',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.green),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.cloud_done, color: Colors.green, size: 16),
                      SizedBox(width: 4),
                      Text('Sincronizado', style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // --- TARJETA VIAJE ACTIVO ---
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('VIAJE ACTIVO', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey)),
                Text('${_viajesPendientes.length} pendientes', style: const TextStyle(fontSize: 14, color: Color(0xFFE67E22), fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            _buildViajeActivoCard(),
            const SizedBox(height: 24),

            // --- ACCIONES RÁPIDAS ---
            const Text('ACCIONES RÁPIDAS', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildActionCard(Icons.access_time, 'Iniciar\nTurno', Colors.blue),
                _buildActionCard(Icons.local_gas_station, 'Cargar\nCombustible', const Color(0xFFE67E22)),
                _buildActionCard(Icons.warning_amber_rounded, 'Reportar\nIncidente', Colors.red),
              ],
            ),
            const SizedBox(height: 24),

            // --- PRÓXIMAS ASIGNACIONES ---
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('PRÓXIMAS ASIGNACIONES', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey)),
                TextButton(
                  onPressed: () {},
                  child: const Text('Ver todos', style: TextStyle(color: Color(0xFFE67E22))),
                )
              ],
            ),
            _buildProximosViajes(),
          ],
        ),
      ),
      
      // --- BARRA DE NAVEGACIÓN INFERIOR ---
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFFE67E22),
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Inicio'),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Viajes'),
          BottomNavigationBarItem(icon: Icon(Icons.insert_drive_file), label: 'Planilla'),
          BottomNavigationBarItem(icon: Icon(Icons.local_gas_station), label: 'Combustible'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Perfil'),
        ],
      ),
    );
  }

  // Widget para el Viaje en Curso
  Widget _buildViajeActivoCard() {
    if (_viajeActivo == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: const Center(child: Text('No tienes un viaje activo en este momento.', style: TextStyle(color: Colors.grey))),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A), // Azul marino
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_viajeActivo!['numero_guia'], style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.circular(12)),
                      child: const Text('En curso', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildRutaRow('ORIGEN', _viajeActivo!['region']), // Puedes cambiar por una columna de origen real si la agregas
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Icon(Icons.arrow_downward, color: Colors.grey, size: 16),
                ),
                _buildRutaRow('DESTINO', _viajeActivo!['consignatario']),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {},
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFF0F172A))),
                    child: const Text('VER DETALLES', style: TextStyle(color: Color(0xFF0F172A))),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.navigation, size: 18, color: Colors.white),
                    label: const Text('Navegar', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE67E22)),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildRutaRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10, letterSpacing: 1.2)),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
      ],
    );
  }

  // Widget para botones de Acciones Rápidas
  Widget _buildActionCard(IconData icon, String text, Color color) {
    return Expanded(
      child: Card(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: InkWell(
          onTap: () {},
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Column(
              children: [
                Icon(icon, color: color, size: 32),
                const SizedBox(height: 8),
                Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Widget para lista de Próximos Viajes
  Widget _buildProximosViajes() {
    if (_viajesPendientes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Text('No hay asignaciones pendientes.', style: TextStyle(color: Colors.grey)),
      );
    }

    return Column(
      children: _viajesPendientes.map((viaje) {
        return Card(
          elevation: 0,
          color: Colors.white,
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.calendar_month, color: Color(0xFFE67E22)),
            ),
            title: Text(viaje['numero_guia'], style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(viaje['consignatario']),
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
            onTap: () {},
          ),
        );
      }).toList(),
    );
  }
}