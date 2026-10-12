import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart'; 
import 'mobile/mis_viajes_screen.dart'; 

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

      final perfil = await Supabase.instance.client
          .from('conductores')
          .select('rut, nombre_completo')
          .eq('auth_id', userId)
          .single();

      _nombreConductor = perfil['nombre_completo'];
      final rut = perfil['rut'];

      const querySelect = '''
        *,
        clientes (*),
        regiones (*),
        consignatarios (*)
      ''';

      final activoData = await Supabase.instance.client
          .from('viajes')
          .select(querySelect)
          .eq('conductor_rut', rut)
          .eq('estado', 'en_curso')
          .limit(1)
          .maybeSingle();

      final pendientesData = await Supabase.instance.client
          .from('viajes')
          .select(querySelect)
          .eq('conductor_rut', rut)
          .eq('estado', 'pendiente')
          .order('fecha_viaje', ascending: true)
          .limit(3); 

      final countResponse = await Supabase.instance.client
          .from('viajes')
          .select('id')
          .eq('conductor_rut', rut)
          .eq('estado', 'completado'); 

      if (mounted) {
        setState(() {
          _viajeActivo = activoData;
          _viajesPendientes = pendientesData;
          _totalViajesMes = countResponse.length;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error cargando dashboard: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _onItemTapped(int index) {
    if (index == 1) { 
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const MisViajesScreen()),
      ).then((_) {
        setState(() => _isLoading = true);
        _cargarDatosDashboard();
      });
    } else {
      setState(() {
        _selectedIndex = index;
      });
    }
  }

  String _safeString(dynamic relacion, List<String> keys, String fallback) {
    if (relacion == null) return fallback;
    Map? data;
    if (relacion is Map) {
      data = relacion;
    } else if (relacion is List && relacion.isNotEmpty && relacion.first is Map) {
      data = relacion.first;
    }
    if (data != null) {
      for (String key in keys) {
        if (data.containsKey(key) && data[key] != null && data[key].toString().trim().isNotEmpty) {
          return data[key].toString();
        }
      }
    }
    return fallback;
  }

  String _formatearHora(String? hora) {
    if (hora == null || hora.isEmpty) return '--:--';
    final partes = hora.split(':');
    if (partes.length >= 2) return '${partes[0]}:${partes[1]}';
    return hora;
  }

  // NUEVO: Generador del ID visual (TRP-XXXXX) para el Home
  String _generarIdVisual(String? uuid) {
    if (uuid == null || uuid.isEmpty) return 'N/A';
    String shortId = uuid.length >= 8 ? uuid.substring(0, 8).toUpperCase() : uuid.toUpperCase();
    return 'TRP-$shortId';
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

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('PRÓXIMAS ASIGNACIONES', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey)),
                TextButton(
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const MisViajesScreen())).then((_) {
                      setState(() => _isLoading = true);
                      _cargarDatosDashboard();
                    });
                  },
                  child: const Text('Ver todos', style: TextStyle(color: Color(0xFFE67E22))),
                )
              ],
            ),
            _buildProximosViajes(),
          ],
        ),
      ),
      
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

  Widget _buildViajeActivoCard() {
    if (_viajeActivo == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: const Center(child: Text('No tienes un viaje activo en este momento.', style: TextStyle(color: Colors.grey))),
      );
    }

    final clienteNombre = _safeString(_viajeActivo!['clientes'], ['nombre_empresa', 'nombre', 'razon_social'], 'Origen Desconocido');
    final consignatarioNombre = _safeString(_viajeActivo!['consignatarios'], ['nombre_empresa', 'nombre', 'razon_social'], 'Destino Desconocido');
    
    // Extraemos el ID y las horas
    final idCarga = _generarIdVisual(_viajeActivo!['id']);
    final horaCarga = _formatearHora(_viajeActivo!['hora_carga']);
    final horaDescarga = _formatearHora(_viajeActivo!['hora_descarga']);
    
    final direccionDestino = _safeString(_viajeActivo!['consignatarios'], ['direccion', 'ubicacion'], '');

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A), 
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
                    Text(idCarga, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 16)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.circular(12)),
                      child: const Text('En curso', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildRutaRow('ORIGEN', clienteNombre, horaCarga),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Icon(Icons.arrow_downward, color: Colors.grey, size: 16),
                ),
                _buildRutaRow('DESTINO', consignatarioNombre, horaDescarga),
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
                    onPressed: () {
                      Navigator.push(
                        context, 
                        MaterialPageRoute(builder: (context) => const MisViajesScreen(abrirViajeActivo: true))
                      ).then((_) {
                        setState(() => _isLoading = true);
                        _cargarDatosDashboard();
                      });
                    },
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFF0F172A))),
                    child: const Text('VER DETALLES', style: TextStyle(color: Color(0xFF0F172A), fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      if (direccionDestino.isNotEmpty) {
                        final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(direccionDestino)}');
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        } else {
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo abrir el mapa')));
                        }
                      } else {
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Este destino no tiene una dirección registrada en la base de datos.')));
                      }
                    },
                    icon: const Icon(Icons.navigation, size: 16, color: Colors.white),
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

  // MODIFICADO: Ahora acepta la hora y la alinea a la derecha
  Widget _buildRutaRow(String label, String value, String hora) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10, letterSpacing: 1.2)),
              Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        if (hora != '--:--')
          Row(
            children: [
              const Icon(Icons.access_time, color: Colors.grey, size: 14),
              const SizedBox(width: 4),
              Text(hora, style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold)),
            ],
          ),
      ],
    );
  }

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

  Widget _buildProximosViajes() {
    if (_viajesPendientes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Text('No hay asignaciones pendientes.', style: TextStyle(color: Colors.grey)),
      );
    }

    return Column(
      children: _viajesPendientes.map((viaje) {
        final clienteNombre = _safeString(viaje['clientes'], ['nombre_empresa', 'nombre', 'razon_social'], 'Cliente');
        final consignatarioNombre = _safeString(viaje['consignatarios'], ['nombre_empresa', 'nombre', 'razon_social'], 'Consignatario');
        
        final tituloViaje = '$clienteNombre / $consignatarioNombre';
        
        final horaCarga = _formatearHora(viaje['hora_carga']);
        final horaDescarga = _formatearHora(viaje['hora_descarga']);
        final subtituloHoras = '$horaCarga / $horaDescarga';

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
            title: Text(tituloViaje, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            subtitle: Text(subtituloHoras, style: const TextStyle(color: Colors.grey, fontSize: 12)),
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
            onTap: () {
               Navigator.push(context, MaterialPageRoute(builder: (context) => const MisViajesScreen())).then((_) {
                  setState(() => _isLoading = true);
                  _cargarDatosDashboard();
               });
            },
          ),
        );
      }).toList(),
    );
  }
}