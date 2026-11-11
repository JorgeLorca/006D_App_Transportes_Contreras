import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../local_db/database_helper.dart';
import '../local_db/sync_helper.dart';
import 'login_screen.dart';
import 'mobile/mis_viajes_screen.dart';
import 'mobile/combustible_screen.dart';
import 'mobile/asistencia_screen.dart';
import 'mobile/perfil_conductor_screen.dart';
import 'mobile/incidentes_screen.dart';
import '../utils/notificaciones_accidentes_service.dart';
import 'mobile/planilla_screen.dart';

class ConductorHome extends StatefulWidget {
  const ConductorHome({super.key});

  @override
  State<ConductorHome> createState() => _ConductorHomeState();
}

class _ConductorHomeState extends State<ConductorHome> {
  int _selectedIndex = 0;
  bool _isLoading = true;
  bool _estaOnline = true;
  String _nombreConductor = 'Conductor';
  String _rutConductor = '--';
  bool _turnoEnCurso = false;

  RegistroMapa? _viajeActivo;
  List<dynamic> _viajesPendientes = [];
  int _totalViajesMes = 0;

  @override
  void initState() {
    super.initState();
    _cargarDatosDashboard();
  }

  Future<void> _cargarDatosDashboard() async {
    try {
      String? rut;
      String? nombre;

      final sesionLocal = await DatabaseHelper.instance.obtenerSesionConductor();
      if (sesionLocal != null) {
        rut = sesionLocal['rut']?.toString();
        nombre = sesionLocal['nombre_completo']?.toString();
      }

      if (rut == null) {
        final user = Supabase.instance.client.auth.currentUser;
        if (user != null) {
          final perfil = await Supabase.instance.client
              .from('conductores')
              .select('rut, nombre_completo')
              .eq('auth_id', user.id)
              .single();
          rut = perfil['rut'].toString();
          nombre = perfil['nombre_completo'].toString();
          await DatabaseHelper.instance.guardarSesionConductor(user.id, rut, nombre);
        }
      }

      if (rut == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      _rutConductor = rut;
      _nombreConductor = nombre ?? 'Conductor';

      // Activa la escucha en tiempo real de Accidentes en Ruta reportados por otros conductores
      NotificacionesAccidentesService.inicializarYEscuchar(
        rutConductorActual: rut,
        context: context,
      );

      await _leerDesdeSQLite(rut);

      final sincronizado = await SyncHelper.sincronizarTodo(rut);
      if (mounted) {
        setState(() => _estaOnline = sincronizado);
      }

      if (sincronizado) {
        await _leerDesdeSQLite(rut);
      }
    } catch (e) {
      debugPrint('Error cargando dashboard: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _leerDesdeSQLite(String rut) async {
    final activosLocal = await DatabaseHelper.instance.obtenerViajesPorEstado(rut, 'en_curso');
    final pendientesLocal = await DatabaseHelper.instance.obtenerViajesPorEstado(rut, 'pendiente');
    final completadosLocal = await DatabaseHelper.instance.obtenerViajesPorEstado(rut, 'completado');
    final ultimoEventoAsistencia = await DatabaseHelper.instance.obtenerUltimoEventoAsistencia(rut);

    final bool enTurno = ultimoEventoAsistencia != null &&
        (ultimoEventoAsistencia['tipo_evento']?.toString().toLowerCase() == 'entrada');

    if (mounted) {
      setState(() {
        _viajeActivo = activosLocal.isNotEmpty ? activosLocal.first : null;
        _viajesPendientes = pendientesLocal.take(3).toList();
        _totalViajesMes = completadosLocal.length;
        _turnoEnCurso = enTurno;
        _isLoading = false;
      });
    }
  }

  void _abrirAsistencia() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AsistenciaScreen()),
    ).then((_) {
      setState(() => _isLoading = true);
      _cargarDatosDashboard();
    });
  }

  void _abrirPerfil() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const PerfilConductorScreen()),
    ).then((_) {
      setState(() => _isLoading = true);
      _cargarDatosDashboard();
    });
  }

  Future<void> _cerrarSesionDesdeMenu() async {
    final confirmar = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar Sesión'),
        content: const Text('¿Desea cerrar su sesión actual?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salir', style: TextStyle(color: Colors.white)),
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

  void _onItemTapped(int index) {
    if (index == 1) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const MisViajesScreen()),
      ).then((_) {
        setState(() => _isLoading = true);
        _cargarDatosDashboard();
      });
    } else if (index == 2) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const PlanillaScreen()),
      ).then((_) {
        setState(() => _isLoading = true);
        _cargarDatosDashboard();
      });
    } else if (index == 3) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const CombustibleScreen(vistaInicial: VistaCombustible.historial),
        ),
      ).then((_) {
        setState(() => _isLoading = true);
        _cargarDatosDashboard();
      });
    } else if (index == 4) {
      _abrirPerfil();
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
      drawer: _buildMenuLateral(),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.local_shipping, color: Colors.white, size: 22),
            SizedBox(width: 8),
            Text('TRANSPORTES CONTRERAS', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync, color: Colors.white),
            tooltip: 'Sincronizar ahora',
            onPressed: () {
              setState(() => _isLoading = true);
              _cargarDatosDashboard();
            },
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
                    color: (_estaOnline ? Colors.green : const Color(0xFFE67E22)).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _estaOnline ? Colors.green : const Color(0xFFE67E22)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _estaOnline ? Icons.cloud_done : Icons.cloud_off,
                        color: _estaOnline ? Colors.green : const Color(0xFFE67E22),
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _estaOnline ? 'Sincronizado' : 'Modo Offline',
                        style: TextStyle(
                          color: _estaOnline ? Colors.green : const Color(0xFFE67E22),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
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
                _buildActionCard(
                  _turnoEnCurso ? Icons.logout_rounded : Icons.access_time,
                  _turnoEnCurso ? 'Finalizar\nTurno' : 'Iniciar\nTurno',
                  _turnoEnCurso ? Colors.green : Colors.blue,
                  onTap: _abrirAsistencia,
                ),
                _buildActionCard(
                  Icons.local_gas_station,
                  'Cargar\nCombustible',
                  const Color(0xFFE67E22),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CombustibleScreen(vistaInicial: VistaCombustible.formulario),
                      ),
                    ).then((_) {
                      setState(() => _isLoading = true);
                      _cargarDatosDashboard();
                    });
                  },
                ),
                _buildActionCard(
                  Icons.warning_amber_rounded,
                  'Reportar\nIncidente',
                  Colors.red,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => IncidentesScreen(
                          viajeIdInicial: _viajeActivo?['id']?.toString(),
                        ),
                      ),
                    ).then((_) {
                      setState(() => _isLoading = true);
                      _cargarDatosDashboard();
                    });
                  },
                ),
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

  Widget _buildMenuLateral() {
    return Drawer(
      backgroundColor: Colors.white,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 52, 20, 24),
            decoration: const BoxDecoration(color: Color(0xFF0F172A)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: const Color(0xFFE67E22),
                  child: Text(
                    _nombreConductor.isNotEmpty ? _nombreConductor[0].toUpperCase() : 'C',
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _nombreConductor,
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'RUT: $_rutConductor',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _turnoEnCurso ? Colors.green.withOpacity(0.25) : Colors.white12,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _turnoEnCurso ? '● Turno Activo (En Jornada)' : '○ Fuera de Turno',
                    style: TextStyle(
                      color: _turnoEnCurso ? Colors.greenAccent : Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                ListTile(
                  leading: const Icon(Icons.home_outlined, color: Color(0xFF0F172A)),
                  title: const Text('Panel de Inicio', style: TextStyle(fontWeight: FontWeight.w600)),
                  onTap: () => Navigator.pop(context),
                ),
                ListTile(
                  leading: const Icon(Icons.where_to_vote_outlined, color: Color(0xFFE67E22)),
                  title: const Text('Asistencia (Entrada / Salida)', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    _turnoEnCurso ? 'Jornada en curso • Marcar salida' : 'Marcar entrada (Radio 500m)',
                    style: const TextStyle(fontSize: 11),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _abrirAsistencia();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.map_outlined, color: Color(0xFF0F172A)),
                  title: const Text('Mis Viajes', style: TextStyle(fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.pop(context);
                    _onItemTapped(1);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.insert_drive_file_outlined, color: Color(0xFF0F172A)),
                  title: const Text('Mi Planilla (Ciclo 21 al 20)', style: TextStyle(fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.pop(context);
                    _onItemTapped(2);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.local_gas_station_outlined, color: Color(0xFF0F172A)),
                  title: const Text('Combustible (AIRE)', style: TextStyle(fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.pop(context);
                    _onItemTapped(3);
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.person_outline, color: Color(0xFF0F172A)),
                  title: const Text('Mi Perfil', style: TextStyle(fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.pop(context);
                    _abrirPerfil();
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text(
                'Cerrar Sesión',
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
              ),
              onTap: () {
                Navigator.pop(context);
                _cerrarSesionDesdeMenu();
              },
            ),
          ),
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

    final idCarga = _generarIdVisual(_viajeActivo!['id']?.toString());
    final horaCarga = _formatearHora(_viajeActivo!['hora_carga']?.toString());
    final horaDescarga = _formatearHora(_viajeActivo!['hora_descarga']?.toString());

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
                        MaterialPageRoute(builder: (context) => const MisViajesScreen(abrirViajeActivo: true)),
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

  Widget _buildActionCard(IconData icon, String text, Color color, {VoidCallback? onTap}) {
    return Expanded(
      child: Card(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: InkWell(
          onTap: onTap ?? () {},
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Column(
              children: [
                Icon(icon, color: color, size: 32),
                const SizedBox(height: 8),
                Text(
                  text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                ),
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

        final horaCarga = _formatearHora(viaje['hora_carga']?.toString());
        final horaDescarga = _formatearHora(viaje['hora_descarga']?.toString());
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