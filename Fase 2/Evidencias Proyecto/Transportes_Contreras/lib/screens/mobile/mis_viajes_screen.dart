import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum VistaViaje { lista, detalle, enCurso, completado }

class MisViajesScreen extends StatefulWidget {
  // NUEVO: Parámetro para decirle a la pantalla que abra el viaje activo de inmediato
  final bool abrirViajeActivo; 
  
  const MisViajesScreen({super.key, this.abrirViajeActivo = false});

  @override
  State<MisViajesScreen> createState() => _MisViajesScreenState();
}

class _MisViajesScreenState extends State<MisViajesScreen> {
  bool _isLoading = true;
  VistaViaje _vistaActual = VistaViaje.lista;
  
  Map<String, dynamic>? _viajeSeleccionado;
  Map<String, dynamic>? _viajeActivo;
  List<dynamic> _viajesPendientes = [];

  final Color _primaryColor = const Color(0xFF0F172A);
  final Color _orangeColor = const Color(0xFFE67E22);

  @override
  void initState() {
    super.initState();
    _cargarViajes();
  }

  Future<void> _cargarViajes() async {
    setState(() => _isLoading = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;
      
      final perfil = await Supabase.instance.client
          .from('conductores')
          .select('rut')
          .eq('auth_id', userId)
          .single();
          
      final rut = perfil['rut'];

      const querySelect = '''
        *,
        clientes (*),
        regiones (*),
        consignatarios (*),
        camiones (*)
      ''';

      final activoData = await Supabase.instance.client
          .from('viajes')
          .select(querySelect)
          .eq('conductor_rut', rut)
          .eq('estado', 'en_curso')
          .maybeSingle();

      final pendientesData = await Supabase.instance.client
          .from('viajes')
          .select(querySelect)
          .eq('conductor_rut', rut)
          .eq('estado', 'pendiente')
          .order('fecha_viaje', ascending: true);

      if (mounted) {
        setState(() {
          _viajeActivo = activoData;
          _viajesPendientes = pendientesData;
          
          // NUEVO: Si el Home nos pidió abrir el viaje activo y existe, saltamos directo a esa vista
          if (widget.abrirViajeActivo && _viajeActivo != null) {
            _viajeSeleccionado = _viajeActivo;
            _vistaActual = VistaViaje.enCurso;
          }
          
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error cargando viajes: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

// ... EL RESTO DE TU ARCHIVO HACIA ABAJO SE MANTIENE EXACTAMENTE IGUAL ...

  Future<void> _iniciarRuta() async {
    if (_viajeSeleccionado == null) return;
    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client
          .from('viajes')
          .update({
            'estado': 'en_curso',
            'iniciado_en': DateTime.now().toIso8601String(),
          })
          .eq('id', _viajeSeleccionado!['id']);
          
      await _cargarViajes(); 
      setState(() {
        _viajeSeleccionado = _viajeActivo;
        _vistaActual = VistaViaje.enCurso;
      });
    } catch (e) {
      debugPrint('Error al iniciar ruta: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _mostrarFormularioFinalizacion() {
    final numGuiaCtrl = TextEditingController();
    final horasNocturnasCtrl = TextEditingController();
    final horasSabadoCtrl = TextEditingController();
    final montoTagCtrl = TextEditingController();
    final guiaPetroleoCtrl = TextEditingController();
    final obsCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (BuildContext context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 20, right: 20, top: 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Finalizar Viaje', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                const SizedBox(height: 8),
                const Text('Complete los datos operativos para cerrar el viaje.', style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 20),
                
                TextField(
                  controller: numGuiaCtrl,
                  decoration: const InputDecoration(labelText: 'Número de Guía', border: OutlineInputBorder(), prefixIcon: Icon(Icons.receipt_long)),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: horasNocturnasCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Hrs Nocturnas', border: OutlineInputBorder(), prefixIcon: Icon(Icons.mode_night)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: horasSabadoCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Hrs Sábado', border: OutlineInputBorder(), prefixIcon: Icon(Icons.calendar_today)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: montoTagCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Monto TAG (\$)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.toll)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: guiaPetroleoCtrl,
                  decoration: const InputDecoration(labelText: 'Guía Petróleo (Opcional)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.local_gas_station)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: obsCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Observaciones del Conductor',
                    hintText: 'Detalle peonetas, retrasos u otros eventos...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    onPressed: () {
                      if (numGuiaCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('El Número de Guía es obligatorio'), backgroundColor: Colors.red));
                        return;
                      }
                      Navigator.pop(context);
                      _procesarFinalizacion(
                        numGuiaCtrl.text.trim(),
                        horasNocturnasCtrl.text,
                        horasSabadoCtrl.text,
                        montoTagCtrl.text,
                        guiaPetroleoCtrl.text.trim(),
                        obsCtrl.text.trim(),
                      );
                    },
                    child: const Text('CONFIRMAR Y FINALIZAR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _procesarFinalizacion(String guia, String hNocturnas, String hSabado, String tag, String petroleo, String obs) async {
    if (_viajeSeleccionado == null) return;
    setState(() => _isLoading = true);
    
    try {
      await Supabase.instance.client
          .from('viajes')
          .update({
            'estado': 'completado',
            'numero_guia': guia,
            'horas_nocturnas': double.tryParse(hNocturnas.replaceAll(',', '.')) ?? 0.0,
            'horas_sabado': double.tryParse(hSabado.replaceAll(',', '.')) ?? 0.0,
            'monto_tag': int.tryParse(tag) ?? 0,
            'guia_petroleo': petroleo.isEmpty ? null : petroleo,
            'observaciones_conductor': obs.isEmpty ? null : obs,
            'finalizado_en': DateTime.now().toIso8601String(),
          })
          .eq('id', _viajeSeleccionado!['id']);
          
      setState(() {
        _viajeSeleccionado!['numero_guia'] = guia;
        _vistaActual = VistaViaje.completado;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error al finalizar viaje: $e');
      setState(() => _isLoading = false);
    }
  }

  void _volverALista() {
    setState(() {
      _vistaActual = VistaViaje.lista;
      _viajeSeleccionado = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
    backgroundColor: _primaryColor,
    elevation: 0,
    // NUEVO: Asegura que todos los íconos del AppBar (incluida la flecha por defecto de Flutter) sean blancos
    iconTheme: const IconThemeData(color: Colors.white), 
    leading: _vistaActual != VistaViaje.lista && _vistaActual != VistaViaje.completado
        ? IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white), 
            onPressed: _volverALista
          )
        : null,
    title: const Text('Mis Viajes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
  ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: _orangeColor))
          : _construirVistaActual(),
    );
  }

  Widget _construirVistaActual() {
    switch (_vistaActual) {
      case VistaViaje.lista: return _buildListaViajes();
      case VistaViaje.detalle: return _buildDetalleViaje();
      case VistaViaje.enCurso: return _buildViajeEnCurso();
      case VistaViaje.completado: return _buildViajeCompletado();
    }
  }

  // --- EXTRACTOR INTELIGENTE MULTI-LLAVE ---
  // Busca entre varias posibles columnas hasta encontrar la que tiene el dato
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

  String _generarIdVisual(String? uuid) {
    if (uuid == null || uuid.isEmpty) return 'N/A';
    String shortId = uuid.length >= 8 ? uuid.substring(0, 8).toUpperCase() : uuid.toUpperCase();
    return 'TRP-$shortId';
  }
  
  // ================================================================= //
  // VISTA 1: LISTA DE VIAJES
  // ================================================================= //
  Widget _buildListaViajes() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('EN CURSO', style: TextStyle(color: Color(0xFF475569), fontSize: 12, fontWeight: FontWeight.bold)),
                      Text(_viajeActivo != null ? '01' : '00', style: const TextStyle(color: Color(0xFF0F172A), fontSize: 24, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('PENDIENTES', style: TextStyle(color: Color(0xFF475569), fontSize: 12, fontWeight: FontWeight.bold)),
                      Text(_viajesPendientes.length.toString().padLeft(2, '0'), style: const TextStyle(color: Color(0xFF0F172A), fontSize: 24, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          if (_viajeActivo != null) ...[
            const Text('VIAJE ACTUAL', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 12),
            _tarjetaViaje(_viajeActivo!, esEnCurso: true),
            const SizedBox(height: 24),
          ],

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('PRÓXIMOS SERVICIOS', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
              Text('TOTAL: ${_viajesPendientes.length}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 12),
          if (_viajesPendientes.isEmpty)
            const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('No tienes viajes asignados.')))
          else
            ..._viajesPendientes.map((viaje) => _tarjetaViaje(viaje, esEnCurso: false)),
        ],
      ),
    );
  }

  Widget _tarjetaViaje(Map<String, dynamic> viaje, {required bool esEnCurso}) {
    // Aquí implementamos el extractor inteligente buscando múltiples nombres de columnas
    final clienteNombre = _safeString(viaje['clientes'], ['nombre_empresa', 'nombre', 'razon_social'], 'Cliente Desconocido');
    final consignatarioNombre = _safeString(viaje['consignatarios'], ['nombre_empresa', 'nombre', 'razon_social'], 'Destino Desconocido');
    final regionNombre = _safeString(viaje['regiones'], ['nombre', 'region'], 'Región no especificada');
    final idCarga = _generarIdVisual(viaje['id']);
    
    final fechaViaje = viaje['fecha_viaje'] ?? '--/--/----';
    final horaCarga = viaje['hora_carga'] ?? '--:--';
    final pallets = viaje['pallets']?.toString() ?? '0';

    return GestureDetector(
      onTap: () {
        setState(() {
          _viajeSeleccionado = viaje;
          _vistaActual = esEnCurso ? VistaViaje.enCurso : VistaViaje.detalle;
        });
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.local_shipping_outlined, size: 18),
                      const SizedBox(width: 8),
                      Text(idCarga, style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: esEnCurso ? _orangeColor : const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(12)),
                    child: Text(
                      esEnCurso ? 'EN CURSO' : 'PENDIENTE',
                      style: TextStyle(color: esEnCurso ? Colors.white : const Color(0xFF475569), fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  )
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _lineaRutaBasica('ORIGEN', '$regionNombre / $clienteNombre'),
                  const SizedBox(height: 16),
                  _lineaRutaBasica('DESTINO', consignatarioNombre),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _columnaDetalleLigero(Icons.calendar_today, 'FECHA', fechaViaje),
                      _columnaDetalleLigero(Icons.access_time, 'HORA EST.', horaCarga),
                      _columnaDetalleLigero(Icons.inventory_2, 'PALLETS', pallets),
                    ],
                  )
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(color: Color(0xFFF8FAFC), borderRadius: BorderRadius.vertical(bottom: Radius.circular(16))),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Ver detalles', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 13)),
                  Icon(Icons.arrow_forward_ios, size: 14, color: _primaryColor),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _columnaDetalleLigero(IconData icon, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 12, color: Colors.grey),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
      ],
    );
  }

  Widget _lineaRutaBasica(String titulo, String lugar) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(titulo == 'ORIGEN' ? Icons.circle_outlined : Icons.location_on, size: 16, color: _primaryColor),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
              Text(lugar, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
            ],
          ),
        ),
      ],
    );
  }

  // ================================================================= //
  // VISTA 2: DETALLE DEL VIAJE
  // ================================================================= //
  Widget _buildDetalleViaje() {
    final viaje = _viajeSeleccionado!;
    final idCarga = _generarIdVisual(viaje['id']);
    
    final clienteNombre = _safeString(viaje['clientes'], ['nombre_empresa', 'nombre', 'razon_social'], 'Cliente Desconocido');
    final clienteDir = _safeString(viaje['clientes'], ['direccion', 'ubicacion'], '');
    final consignatarioNombre = _safeString(viaje['consignatarios'], ['nombre_empresa', 'nombre', 'razon_social'], 'Destino Desconocido');
    final consignatarioDir = _safeString(viaje['consignatarios'], ['direccion', 'ubicacion'], '');
    final regionNombre = _safeString(viaje['regiones'], ['nombre', 'region'], 'Región no especificada');
    final patente = _safeString(viaje['camiones'], ['patente', 'placa'], 'No asignado');
    
    final fecha = viaje['fecha_viaje'] ?? '--/--/----';
    final horaCarga = viaje['hora_carga'] ?? '--:--';
    final obsAdmin = viaje['observaciones_admin'] ?? 'Sin observaciones del administrador.';

    return SingleChildScrollView(
      child: Column(
        children: [
          Container(
            height: 150,
            width: double.infinity,
            color: Colors.blueGrey.shade100,
            child: const Center(child: Icon(Icons.map, size: 50, color: Colors.white)),
          ),
          Container(
            transform: Matrix4.translationValues(0.0, -20.0, 0.0),
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ID DE CARGA', style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
                Text(idCarga, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),
                
                _lineaRutaBasica('ORIGEN', '$clienteNombre, $regionNombre\n$clienteDir'),
                const Padding(
                  padding: EdgeInsets.only(left: 7.0, top: 4, bottom: 4),
                  child: SizedBox(height: 20, child: VerticalDivider(color: Colors.grey, thickness: 1)),
                ),
                _lineaRutaBasica('DESTINO', '$consignatarioNombre\n$consignatarioDir'),
                
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
                        child: _columnaDetalleLigero(Icons.calendar_today, 'FECHA', fecha),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
                        child: _columnaDetalleLigero(Icons.access_time, 'HORA DE CARGA', horaCarga),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: _iniciarRuta,
                    icon: const Icon(Icons.navigation, color: Colors.white),
                    label: const Text('INICIAR RUTA', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(backgroundColor: _primaryColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  ),
                ),
                const SizedBox(height: 32),
                
                const Text('INFORMACIÓN LOGÍSTICA', style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                _cajaInfo(Icons.inventory_2_outlined, 'Carga', '${viaje['pallets'] ?? 0} Pallets'),
                const SizedBox(height: 12),
                _cajaInfo(Icons.directions_car, 'Vehículo Asignado', 'Patente: $patente'),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: const Color(0xFFFFF7ED), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFFFEDD5))),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.description, size: 14, color: Color(0xFFEA580C)),
                          SizedBox(width: 6),
                          Text('NOTAS DE DESPACHO', style: TextStyle(fontSize: 10, color: Color(0xFFEA580C), fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('"$obsAdmin"', style: TextStyle(fontSize: 13, color: Colors.orange.shade900, fontStyle: FontStyle.italic)),
                    ],
                  ),
                ),
                
                const SizedBox(height: 32),
                const Text('CONTACTO CLIENTE', style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
                  child: Row(
                    children: [
                      const CircleAvatar(backgroundColor: Color(0xFFE2E8F0), child: Icon(Icons.person, color: Colors.grey)),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Representante Comercial', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            Text(clienteNombre, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () {},
                        icon: const Icon(Icons.phone),
                        style: IconButton.styleFrom(backgroundColor: const Color(0xFFF1F5F9), foregroundColor: _primaryColor),
                      )
                    ],
                  ),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cajaInfo(IconData icono, String titulo, String subtitulo) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
      child: Row(
        children: [
          Icon(icono, color: _primaryColor),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
              Text(subtitulo, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
            ],
          )
        ],
      ),
    );
  }

  // ================================================================= //
  // VISTA 3: VIAJE EN CURSO
  // ================================================================= //
  Widget _buildViajeEnCurso() {
    final viaje = _viajeSeleccionado!;
    final idCarga = _generarIdVisual(viaje['id']);
    
    final clienteNombre = _safeString(viaje['clientes'], ['nombre_empresa', 'nombre', 'razon_social'], 'Origen Desconocido');
    final consignatarioNombre = _safeString(viaje['consignatarios'], ['nombre_empresa', 'nombre', 'razon_social'], 'Destino Desconocido');
    final patente = _safeString(viaje['camiones'], ['patente', 'placa'], 'No asignado');
    
    final horaCarga = viaje['hora_carga'] ?? '--:--';
    final horaDescarga = viaje['hora_descarga'] ?? '--:--';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: _primaryColor, borderRadius: BorderRadius.circular(16)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ID DE VIAJE', style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
                    Text(idCarga, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(12)),
                      child: const Text('● En curso', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    )
                  ],
                ),
                const Icon(Icons.local_shipping, size: 60, color: Colors.white24)
              ],
            ),
          ),
          const SizedBox(height: 24),
          
          const Text('Detalles del Traslado', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
            child: Row(
              children: [
                Icon(Icons.directions_car, color: _primaryColor),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('VEHÍCULO ASIGNADO', style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                    Text('Patente: $patente', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                  ],
                )
              ],
            ),
          ),
          const SizedBox(height: 16),
          
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.history, size: 16, color: Colors.grey),
                    SizedBox(width: 8),
                    Text('HOJA DE RUTA', style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 16),
                _lineaHojaRuta(Icons.radio_button_checked, _primaryColor, clienteNombre, 'SALIDA EST: $horaCarga'),
                const Padding(
                  padding: EdgeInsets.only(left: 7.0, top: 2, bottom: 2),
                  child: SizedBox(height: 30, child: VerticalDivider(color: Colors.grey, thickness: 1)),
                ),
                _lineaHojaRuta(Icons.location_on, _orangeColor, consignatarioNombre, 'LLEGADA EST: $horaDescarga'),
              ],
            ),
          ),
          
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton.icon(
              onPressed: _mostrarFormularioFinalizacion,
              icon: const Icon(Icons.check_circle, color: Colors.white),
              label: const Text('FINALIZAR VIAJE', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lineaHojaRuta(IconData icon, Color color, String titulo, String subtitulo) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
              Text(subtitulo, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
        ),
      ],
    );
  }

  // ================================================================= //
  // VISTA 4: COMPLETADO
  // ================================================================= //
  Widget _buildViajeCompletado() {
    final viaje = _viajeSeleccionado!;
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
              child: const Icon(Icons.check, size: 60, color: Colors.white),
            ),
            const SizedBox(height: 24),
            const Text('¡Viaje Finalizado!', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.green)),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text('El reporte ha sido registrado exitosamente en el sistema.', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Colors.grey)),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(20)),
              child: Text('GUÍA: ${viaje['numero_guia'] ?? 'N/A'}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 48),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _volverALista,
                  style: ElevatedButton.styleFrom(backgroundColor: _primaryColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: const Text('Ver Mis Viajes', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}