import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../local_db/database_helper.dart';
import '../../local_db/sync_helper.dart';

enum VistaCombustible { historial, formulario }

class CombustibleScreen extends StatefulWidget {
  final VistaCombustible vistaInicial;

  const CombustibleScreen({
    super.key,
    this.vistaInicial = VistaCombustible.historial,
  });

  @override
  State<CombustibleScreen> createState() => _CombustibleScreenState();
}

class _CombustibleScreenState extends State<CombustibleScreen> {
  late VistaCombustible _vistaActual;
  bool _isLoading = true;
  bool _estaOnline = true;

  String? _rutConductor;
  String _camionId = '';
  String _camionPatente = 'TC-9042';
  bool _usarPatenteManual = false;

  ListaRegistros _camionesDisponibles = [];
  ListaRegistros _registros = [];
  String _busqueda = '';
  String _filtroEstado = 'todos'; // 'todos', 'sincronizado', 'pendiente'

  // Controladores del formulario de registro
  final _estacionCtrl = TextEditingController(text: 'AIRE');
  final _patenteManualCtrl = TextEditingController();
  final _odometroCtrl = TextEditingController();
  final _litrosCtrl = TextEditingController();
  final _costoCtrl = TextEditingController();
  String _tipoCombustible = 'Diesel';

  String? _rutaFotoVoucher;
  String? _rutaFotoTablero;
  final ImagePicker _picker = ImagePicker();

  final Color _primaryColor = const Color(0xFF0F172A);
  final Color _orangeColor = const Color(0xFFE67E22);

  @override
  void initState() {
    super.initState();
    _vistaActual = widget.vistaInicial;
    _inicializarDatos();
  }

  @override
  void dispose() {
    _estacionCtrl.dispose();
    _patenteManualCtrl.dispose();
    _odometroCtrl.dispose();
    _litrosCtrl.dispose();
    _costoCtrl.dispose();
    super.dispose();
  }

  Future<void> _inicializarDatos() async {
    setState(() => _isLoading = true);
    try {
      final sesion = await DatabaseHelper.instance.obtenerSesionConductor();
      if (sesion != null) {
        _rutConductor = sesion['rut']?.toString();
      } else {
        final user = Supabase.instance.client.auth.currentUser;
        if (user != null) {
          final perfil = await Supabase.instance.client
              .from('conductores')
              .select('rut, nombre_completo')
              .eq('auth_id', user.id)
              .single();
          _rutConductor = perfil['rut'].toString();
          await DatabaseHelper.instance.guardarSesionConductor(
            user.id,
            _rutConductor!,
            perfil['nombre_completo'].toString(),
          );
        }
      }

      if (_rutConductor == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // 1. Cargamos primero desde SQLite
      await _cargarDesdeSQLite(_rutConductor!);

      // 2. Sincronizamos en segundo plano (incluye la flota de camiones)
      final online = await SyncHelper.sincronizarTodo(_rutConductor!);
      if (mounted) {
        setState(() => _estaOnline = online);
      }

      if (online) {
        await _cargarDesdeSQLite(_rutConductor!);
      }
    } catch (e) {
      debugPrint('Error inicializando combustible: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _cargarDesdeSQLite(String rut) async {
    final camionInfo = await DatabaseHelper.instance.obtenerCamionActualConductor(rut);
    final todosCamiones = await DatabaseHelper.instance.obtenerTodosLosCamiones();
    final lista = await DatabaseHelper.instance.obtenerRegistrosCombustible(rut);
    final redDisponible = await SyncHelper.tieneInternet();

    if (mounted) {
      setState(() {
        _camionesDisponibles = todosCamiones;

        if (!_usarPatenteManual) {
          final asignadoId = camionInfo['camion_id'] ?? '';
          final asignadoPatente = camionInfo['patente'] ?? 'TC-9042';

          if (_camionId.isEmpty) {
            _camionId = asignadoId;
            _camionPatente = asignadoPatente;
          }

          // Verificamos si el camión asignado está en la lista; si no, lo agregamos visualmente
          final existeEnLista = _camionesDisponibles.any((c) => c['id']?.toString() == _camionId);
          if (!existeEnLista && _camionId.isNotEmpty) {
            _camionesDisponibles.insert(0, {
              'id': _camionId,
              'patente': _camionPatente,
            });
          } else if (_camionesDisponibles.isNotEmpty && _camionId.isEmpty) {
            _camionId = _camionesDisponibles.first['id']?.toString() ?? '';
            _camionPatente = _camionesDisponibles.first['patente']?.toString() ?? 'TC-9042';
          }
        }

        _registros = lista;
        _estaOnline = redDisponible;
        _isLoading = false;
      });
    }
  }

  // Generador UUID v4 sin signos < > para evitar errores al copiar
  String _generarUuidV4() {
    final rnd = Random.secure();
    const chars = '0123456789abcdef';
    final buf = StringBuffer();
    for (int i = 0; i < 36; i++) {
      if (i == 8 || i == 13 || i == 18 || i == 23) {
        buf.write('-');
      } else if (i == 14) {
        buf.write('4');
      } else if (i == 19) {
        buf.write(chars[(rnd.nextInt(16) & 0x3) | 0x8]);
      } else {
        buf.write(chars[rnd.nextInt(16)]);
      }
    }
    return buf.toString();
  }

  Future<void> _seleccionarFoto(bool esVoucher) async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                esVoucher ? 'Evidencia: Foto Voucher' : 'Evidencia: Foto Tablero',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _primaryColor),
              ),
            ),
            ListTile(
              leading: CircleAvatar(backgroundColor: Colors.orange.shade50, child: Icon(Icons.camera_alt, color: _orangeColor)),
              title: const Text('Tomar foto con la Cámara'),
              onTap: () {
                Navigator.pop(ctx);
                _capturarImagen(ImageSource.camera, esVoucher);
              },
            ),
            ListTile(
              leading: CircleAvatar(backgroundColor: Colors.blue.shade50, child: const Icon(Icons.photo_library, color: Colors.blue)),
              title: const Text('Seleccionar desde la Galería'),
              onTap: () {
                Navigator.pop(ctx);
                _capturarImagen(ImageSource.gallery, esVoucher);
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _capturarImagen(ImageSource source, bool esVoucher) async {
    try {
      final XFile? picked = await _picker.pickImage(source: source, imageQuality: 75);
      if (picked == null) return;

      final appDir = await getApplicationDocumentsDirectory();
      final nombreArchivo = '${esVoucher ? "voucher" : "tablero"}_${DateTime.now().millisecondsSinceEpoch}${p.extension(picked.path)}';
      final archivoLocal = await File(picked.path).copy(p.join(appDir.path, nombreArchivo));

      if (mounted) {
        setState(() {
          if (esVoucher) {
            _rutaFotoVoucher = archivoLocal.path;
          } else {
            _rutaFotoTablero = archivoLocal.path;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo capturar la imagen: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _guardarRegistroCombustible() async {
    if (_rutConductor == null) return;

    final odometroTexto = _odometroCtrl.text.replaceAll('.', '').replaceAll(',', '').trim();
    final litrosTexto = _litrosCtrl.text.replaceAll(',', '.').trim();
    final costoTexto = _costoCtrl.text.replaceAll('.', '').replaceAll(',', '.').trim();
    const estacionTexto = 'AIRE';

    String patenteFinal = _camionPatente;
    String camionIdFinal = _camionId;

    if (_usarPatenteManual) {
      patenteFinal = _patenteManualCtrl.text.trim().toUpperCase();
      if (patenteFinal.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Por favor ingrese la patente del camión que está ocupando.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      // Si la patente escrita coincide con algún camión del catálogo, usamos su ID real
      final coincidencia = _camionesDisponibles.where(
        (c) => (c['patente'] ?? '').toString().toUpperCase() == patenteFinal,
      );
      if (coincidencia.isNotEmpty) {
        camionIdFinal = coincidencia.first['id']?.toString() ?? '';
      } else {
        camionIdFinal = '';
      }
    }

    if (odometroTexto.isEmpty || litrosTexto.isEmpty || costoTexto.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor complete Odómetro, Cantidad de Litros y Costo Total.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final odometro = int.tryParse(odometroTexto) ?? 0;
    final litros = double.tryParse(litrosTexto) ?? 0.0;
    final costoTotal = double.tryParse(costoTexto) ?? 0.0;

    setState(() => _isLoading = true);

    try {
      final nuevoId = _generarUuidV4();

      await DatabaseHelper.instance.insertarCombustibleOffline({
        'id': nuevoId,
        'conductor_rut': _rutConductor,
        'camion_id': camionIdFinal,
        'camion_patente': patenteFinal,
        'estacion': estacionTexto,
        'odometro': odometro,
        'tipo_combustible': _tipoCombustible,
        'litros': litros,
        'costo_total': costoTotal,
        'local_path_voucher': _rutaFotoVoucher,
        'local_path_tablero': _rutaFotoTablero,
        'url_foto_voucher': _rutaFotoVoucher,
        'url_foto_tablero': _rutaFotoTablero,
        'estado_revision': 'pendiente',
        'registrado_en': DateTime.now().toIso8601String(),
      });

      _estacionCtrl.text = 'AIRE';
      _odometroCtrl.clear();
      _litrosCtrl.clear();
      _costoCtrl.clear();
      _patenteManualCtrl.clear();
      _usarPatenteManual = false;
      _rutaFotoVoucher = null;
      _rutaFotoTablero = null;

      await _cargarDesdeSQLite(_rutConductor!);

      setState(() {
        _vistaActual = VistaCombustible.historial;
      });

      final subido = await SyncHelper.sincronizarTodo(_rutConductor!);
      if (mounted) {
        await _cargarDesdeSQLite(_rutConductor!);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              subido
                  ? 'Carga en AIRE ($patenteFinal) registrada y enviada a revisión.'
                  : 'Sin señal: Carga guardada en el teléfono (se subirá al recuperar red).',
            ),
            backgroundColor: subido ? Colors.green : _orangeColor,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error guardando combustible: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatearPesos(num valor) {
    final entero = valor.round().toString();
    final buffer = StringBuffer();
    int contador = 0;
    for (int i = entero.length - 1; i >= 0; i--) {
      buffer.write(entero[i]);
      contador++;
      if (contador == 3 && i != 0) {
        buffer.write('.');
        contador = 0;
      }
    }
    return '\$${buffer.toString().split('').reversed.join()}';
  }

  String _formatearGastoCorto(double total) {
    if (total >= 1000) {
      return '${(total / 1000).round()}K';
    }
    return total.round().toString();
  }

  String _obtenerNombreMesActual() {
    const meses = [
      'ENERO', 'FEBRERO', 'MARZO', 'ABRIL', 'MAYO', 'JUNIO',
      'JULIO', 'AGOSTO', 'SEPTIEMBRE', 'OCTUBRE', 'NOVIEMBRE', 'DICIEMBRE'
    ];
    return meses[DateTime.now().month - 1];
  }

  String _formatearFechaTarjeta(String? iso) {
    if (iso == null || iso.isEmpty) return 'Hoy';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return 'Hoy';
    final ahora = DateTime.now();
    if (dt.year == ahora.year && dt.month == ahora.month && dt.day == ahora.day) {
      return 'Hoy';
    }
    const mesesCortos = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];
    return '${dt.day.toString().padLeft(2, '0')} ${mesesCortos[dt.month - 1]} ${dt.year}';
  }

  String _formatearHoraTarjeta(String? iso) {
    if (iso == null || iso.isEmpty) return '--:--';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '--:--';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: IconThemeData(color: _primaryColor),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: _primaryColor),
          onPressed: () {
            if (_vistaActual == VistaCombustible.formulario && widget.vistaInicial == VistaCombustible.historial) {
              setState(() => _vistaActual = VistaCombustible.historial);
            } else {
              Navigator.pop(context);
            }
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'TRANSPORTES CONTRERAS',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.8),
            ),
            Text(
              _vistaActual == VistaCombustible.historial ? 'Historial de Carga' : 'Registro de Combustible',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _primaryColor),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Center(
              child: GestureDetector(
                onTap: () {
                  if (_rutConductor != null) {
                    setState(() => _isLoading = true);
                    _inicializarDatos();
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _estaOnline ? const Color(0xFFF0FDF4) : const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _estaOnline ? Colors.green.shade300 : const Color(0xFFF59E0B),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _estaOnline ? Icons.check_circle_outline : Icons.error_outline,
                        size: 14,
                        color: _estaOnline ? Colors.green.shade700 : const Color(0xFFD97706),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _estaOnline ? 'Sincronizado' : 'Sin conexión',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: _estaOnline ? Colors.green.shade700 : const Color(0xFFD97706),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: _vistaActual == VistaCombustible.historial
          ? FloatingActionButton(
              backgroundColor: _orangeColor,
              onPressed: () {
                setState(() => _vistaActual = VistaCombustible.formulario);
              },
              child: const Icon(Icons.add, color: Colors.white, size: 28),
            )
          : null,
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: _orangeColor))
          : _vistaActual == VistaCombustible.historial
              ? _buildVistaHistorial()
              : _buildVistaFormulario(),
    );
  }

  // ================================================================= //
  // VISTA 1: HISTORIAL DE CARGA
  // ================================================================= //
  Widget _buildVistaHistorial() {
    final ahora = DateTime.now();
    double totalLitrosMes = 0;
    double totalGastoMes = 0;

    for (final r in _registros) {
      final dt = DateTime.tryParse(r['registrado_en']?.toString() ?? '');
      if (dt == null || (dt.month == ahora.month && dt.year == ahora.year)) {
        totalLitrosMes += (r['litros'] as num?)?.toDouble() ?? 0.0;
        totalGastoMes += (r['costo_total'] as num?)?.toDouble() ?? 0.0;
      }
    }

    final registrosFiltrados = _registros.where((r) {
      final textoEstacion = (r['estacion'] ?? 'AIRE').toString().toLowerCase();
      final textoPatente = (r['camion_patente'] ?? '').toString().toLowerCase();
      final textoId = (r['id'] ?? '').toString().toLowerCase();
      final coincideBusqueda = _busqueda.isEmpty ||
          textoEstacion.contains(_busqueda.toLowerCase()) ||
          textoPatente.contains(_busqueda.toLowerCase()) ||
          textoId.contains(_busqueda.toLowerCase());

      final isSynced = (r['is_synced'] ?? 1) == 1;
      final coincideEstado = _filtroEstado == 'todos' ||
          (_filtroEstado == 'sincronizado' && isSynced) ||
          (_filtroEstado == 'pendiente' && !isSynced);

      return coincideBusqueda && coincideEstado;
    }).toList();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                height: 150,
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1E293B), Color(0xFF334155)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      right: -10,
                      top: -10,
                      child: Icon(Icons.local_gas_station, size: 140, color: Colors.white.withOpacity(0.07)),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 24, 20, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Combustible',
                            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Registro histórico de consumos y cargas (Convenio AIRE)',
                            style: TextStyle(fontSize: 13, color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 100, 16, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: const Color(0xFFF1F5F9),
                              child: Icon(Icons.trending_up, size: 18, color: _primaryColor),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'TOTAL ${_obtenerNombreMesActual()}',
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
                            ),
                            const SizedBox(height: 4),
                            RichText(
                              text: TextSpan(
                                children: [
                                  TextSpan(
                                    text: '${totalLitrosMes.round()} ',
                                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _primaryColor),
                                  ),
                                  const TextSpan(
                                    text: 'Litros',
                                    style: TextStyle(fontSize: 12, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: const Color(0xFFECFDF5),
                              child: Icon(Icons.credit_card, size: 18, color: Colors.green.shade700),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'GASTO',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
                            ),
                            const SizedBox(height: 4),
                            RichText(
                              text: TextSpan(
                                children: [
                                  TextSpan(
                                    text: '${_formatearGastoCorto(totalGastoMes)} ',
                                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _primaryColor),
                                  ),
                                  const TextSpan(
                                    text: 'CLP',
                                    style: TextStyle(fontSize: 12, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (val) => setState(() => _busqueda = val),
                    decoration: InputDecoration(
                      hintText: 'Buscar por patente o ID...',
                      hintStyle: const TextStyle(fontSize: 13, color: Colors.grey),
                      prefixIcon: const Icon(Icons.search, color: Colors.grey, size: 20),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: _primaryColor),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                PopupMenuButton(
                  onSelected: (valor) => setState(() => _filtroEstado = valor.toString()),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'todos', child: Text('Todos los registros')),
                    PopupMenuItem(value: 'sincronizado', child: Text('Solo Sincronizados')),
                    PopupMenuItem(value: 'pendiente', child: Text('Solo Pendientes (Offline)')),
                  ],
                  child: Container(
                    height: 48,
                    width: 48,
                    decoration: BoxDecoration(
                      color: _filtroEstado == 'todos' ? Colors.white : _primaryColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Icon(
                      Icons.filter_alt_outlined,
                      color: _filtroEstado == 'todos' ? _primaryColor : Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.history, size: 18, color: _primaryColor),
                    const SizedBox(width: 6),
                    Text(
                      'Registros Recientes',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _primaryColor),
                    ),
                  ],
                ),
                Text(
                  'Mostrando ${registrosFiltrados.length} items',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          if (registrosFiltrados.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.local_gas_station_outlined, size: 42, color: Colors.grey),
                    const SizedBox(height: 8),
                    const Text(
                      'No hay cargas de combustible registradas.',
                      style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: () => setState(() => _vistaActual = VistaCombustible.formulario),
                      icon: Icon(Icons.add_circle_outline, color: _orangeColor),
                      label: Text('Registrar primera carga', style: TextStyle(color: _orangeColor, fontWeight: FontWeight.bold)),
                    )
                  ],
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: registrosFiltrados.map((reg) => _buildTarjetaCombustible(reg)).toList(),
              ),
            ),

          const SizedBox(height: 8),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: const Color(0xFFE2E8F0),
                    child: Icon(Icons.near_me_outlined, size: 18, color: _primaryColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Recordatorio de evidencia',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _primaryColor),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Asegúrese de sacar foto al comprobante de la guía y al odómetro del tablero.',
                          style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 90),
        ],
      ),
    );
  }

  Widget _buildTarjetaCombustible(RegistroMapa reg) {
    final bool isSynced = (reg['is_synced'] ?? 1) == 1;
    final String estacion = reg['estacion']?.toString().isNotEmpty == true ? reg['estacion'].toString() : 'AIRE';
    final String patente = reg['camion_patente']?.toString() ?? '';
    final String tituloTarjeta = patente.isNotEmpty ? '$estacion – $patente' : estacion;
    final String estadoRev = (reg['estado_revision'] ?? 'pendiente').toString().toLowerCase();
    final double litros = (reg['litros'] as num?)?.toDouble() ?? 0.0;
    final double costo = (reg['costo_total'] as num?)?.toDouble() ?? 0.0;
    final String fecha = _formatearFechaTarjeta(reg['registrado_en']?.toString());
    final String hora = _formatearHoraTarjeta(reg['registrado_en']?.toString());

    final String litrosFormateado = litros % 1 == 0 ? '${litros.toInt()} L' : '${litros.toStringAsFixed(1)} L';

    Color colorRevBg = const Color(0xFFF1F5F9);
    Color colorRevTxt = const Color(0xFF475569);
    String textoRev = 'En revisión';
    if (estadoRev == 'aprobado') {
      colorRevBg = const Color(0xFFDCFCE7);
      colorRevTxt = const Color(0xFF15803D);
      textoRev = 'Aprobada';
    } else if (estadoRev == 'rechazado') {
      colorRevBg = const Color(0xFFFEE2E2);
      colorRevTxt = const Color(0xFFB91C1C);
      textoRev = 'Rechazada';
    }

    return GestureDetector(
      onTap: () => _mostrarDetalleCargaModal(reg),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Container(
              height: 48,
              width: 48,
              decoration: BoxDecoration(
                color: isSynced ? const Color(0xFFE2E8F0) : const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.water_drop_outlined,
                color: isSynced ? _primaryColor : const Color(0xFFD97706),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          tituloTarjeta,
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _primaryColor),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isSynced ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          isSynced ? 'sincronizado' : 'pendiente',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isSynced ? const Color(0xFF15803D) : const Color(0xFFB45309),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.calendar_today_outlined, size: 12, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(fecha, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      const SizedBox(width: 12),
                      const Icon(Icons.access_time, size: 12, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(hora, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: colorRevBg, borderRadius: BorderRadius.circular(6)),
                        child: Text(
                          textoRev,
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: colorRevTxt),
                        ),
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: Divider(height: 1),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('LITROS', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey)),
                          Text(litrosFormateado, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _primaryColor)),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text('COSTO', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey)),
                          Text(
                            _formatearPesos(costo),
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F3E66)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
          ],
        ),
      ),
    );
  }

  void _mostrarDetalleCargaModal(RegistroMapa reg) {
    final patente = reg['camion_patente']?.toString() ?? _camionPatente;
    final odometro = reg['odometro']?.toString() ?? '0';
    final tipo = reg['tipo_combustible']?.toString() ?? 'Diesel';
    final estadoRev = (reg['estado_revision'] ?? 'pendiente').toString().toUpperCase();
    final obsAdmin = reg['observaciones_admin']?.toString();
    final localVoucher = reg['local_path_voucher']?.toString();
    final localTablero = reg['local_path_tablero']?.toString();
    final urlVoucher = reg['url_foto_voucher']?.toString();
    final urlTablero = reg['url_foto_tablero']?.toString();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Carga AIRE ($patente)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _primaryColor)),
                Chip(label: Text(estadoRev, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
              ],
            ),
            const SizedBox(height: 8),
            Text('Odómetro: $odometro KM  •  Combustible: $tipo', style: const TextStyle(color: Colors.grey)),
            if (obsAdmin != null && obsAdmin.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Nota Admin: $obsAdmin', style: TextStyle(color: _orangeColor, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _miniaturaEvidencia('Voucher', localVoucher, urlVoucher)),
                const SizedBox(width: 12),
                Expanded(child: _miniaturaEvidencia('Tablero', localTablero, urlTablero)),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _miniaturaEvidencia(String titulo, String? localPath, String? remoteUrl) {
    Widget contenido;
    if (localPath != null && localPath.isNotEmpty && File(localPath).existsSync()) {
      contenido = Image.file(File(localPath), fit: BoxFit.cover);
    } else if (remoteUrl != null && remoteUrl.startsWith('http')) {
      contenido = Image.network(remoteUrl, fit: BoxFit.cover);
    } else {
      contenido = const Center(child: Text('Sin foto', style: TextStyle(fontSize: 12, color: Colors.grey)));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Container(
          height: 110,
          width: double.infinity,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: contenido,
        ),
      ],
    );
  }

  // ================================================================= //
  // VISTA 2: FORMULARIO REGISTRO DE COMBUSTIBLE
  // ================================================================= //
  Widget _buildVistaFormulario() {
    String textoUltimaCarga = 'Sin cargas previas';
    if (_registros.isNotEmpty) {
      final ultimo = _registros.first;
      final fechaUlt = _formatearFechaTarjeta(ultimo['registrado_en']?.toString());
      final litrosUlt = (ultimo['litros'] as num?)?.round() ?? 0;
      textoUltimaCarga = '$fechaUlt – ${litrosUlt}L';
    }

    final patenteMostrada = _usarPatenteManual
        ? (_patenteManualCtrl.text.trim().isEmpty ? 'OTRO' : _patenteManualCtrl.text.trim().toUpperCase())
        : _camionPatente;

    // Valor actual del Dropdown de camión
    final String valorDropdownCamion = _usarPatenteManual ? '__OTRO__' : _camionId;

    return SingleChildScrollView(
      child: Column(
        children: [
          Container(
            height: 140,
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1E293B), Color(0xFF475569)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F294A),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ÚLTIMA CARGA',
                            style: TextStyle(fontSize: 9, color: Colors.white70, fontWeight: FontWeight.bold, letterSpacing: 0.6),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            textoUltimaCarga,
                            style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _primaryColor),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.local_shipping, size: 13, color: _orangeColor),
                          const SizedBox(width: 5),
                          Text(
                            'Vehículo: $patenteMostrada',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _primaryColor),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 4)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE2E8F0),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.local_shipping_outlined, size: 18, color: _primaryColor),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'INFORMACIÓN DEL CAMIÓN',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _primaryColor),
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Divider(height: 1),
                  ),

                  // NUEVO: Selector de Camión / Patente por si el chofer ocupa otro camión
                  const Text(
                    'CAMIÓN / PATENTE QUE OCUPA',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField(
                    value: (_camionesDisponibles.any((c) => c['id']?.toString() == valorDropdownCamion) || valorDropdownCamion == '__OTRO__')
                        ? valorDropdownCamion
                        : '__OTRO__',
                    isExpanded: true,
                    decoration: InputDecoration(
                      prefixIcon: Icon(Icons.directions_bus_filled_outlined, size: 18, color: _primaryColor),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                    items: [
                      ..._camionesDisponibles.map((cam) {
                        final idCam = cam['id']?.toString() ?? '';
                        final patCam = cam['patente']?.toString() ?? 'S/P';
                        final marcaCam = cam['marca']?.toString() ?? '';
                        final textoItem = marcaCam.isNotEmpty ? 'Patente: $patCam ($marcaCam)' : 'Patente: $patCam';
                        return DropdownMenuItem(
                          value: idCam,
                          child: Text(textoItem, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        );
                      }),
                      const DropdownMenuItem(
                        value: '__OTRO__',
                        child: Text('Otro camión (Digitar patente manualmente)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFFE67E22))),
                      ),
                    ],
                    onChanged: (val) {
                      final seleccion = val?.toString() ?? '';
                      setState(() {
                        if (seleccion == '__OTRO__') {
                          _usarPatenteManual = true;
                        } else {
                          _usarPatenteManual = false;
                          _camionId = seleccion;
                          final encontrado = _camionesDisponibles.where((c) => c['id']?.toString() == seleccion);
                          if (encontrado.isNotEmpty) {
                            _camionPatente = encontrado.first['patente']?.toString() ?? _camionPatente;
                          }
                        }
                      });
                    },
                  ),

                  if (_usarPatenteManual) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: _patenteManualCtrl,
                      textCapitalization: TextCapitalization.characters,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Ingrese la patente del camión',
                        hintText: 'Ej: JKLP-78',
                        prefixIcon: Icon(Icons.edit_road, size: 18, color: _orangeColor),
                        filled: true,
                        fillColor: const Color(0xFFFFF7ED),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: _orangeColor),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: _orangeColor),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 14),

                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'ODÓMETRO (KM)',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _odometroCtrl,
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              decoration: InputDecoration(
                                hintText: 'Ej: 145.280',
                                prefixIcon: const Icon(Icons.near_me_outlined, size: 16, color: Colors.grey),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.grey.shade300),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.grey.shade300),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'TIPO COMBUSTIBLE',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
                            ),
                            const SizedBox(height: 6),
                            DropdownButtonFormField(
                              value: _tipoCombustible,
                              isExpanded: true,
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.local_gas_station_outlined, size: 16, color: Colors.grey),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.grey.shade300),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.grey.shade300),
                                ),
                              ),
                              items: const [
                                DropdownMenuItem(value: 'Diesel', child: Text('DIESEL', style: TextStyle(fontSize: 12))),
                                DropdownMenuItem(value: 'BENCINA 93', child: Text('BENCINA 93', style: TextStyle(fontSize: 12))),
                                DropdownMenuItem(value: 'BENCINA 95', child: Text('BENCINA 95', style: TextStyle(fontSize: 12))),
                                DropdownMenuItem(value: 'BENCINA 97', child: Text('BENCINA 97', style: TextStyle(fontSize: 12))),
                              ],
                              onChanged: (val) {
                                if (val != null) setState(() => _tipoCombustible = val.toString());
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.local_gas_station, size: 18, color: _orangeColor),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'DETALLES DE CARGA',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _primaryColor),
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Divider(height: 1),
                  ),

                  const Text('Estación de Servicio (Convenio)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _estacionCtrl,
                    readOnly: true,
                    style: TextStyle(fontWeight: FontWeight.bold, color: _primaryColor),
                    decoration: InputDecoration(
                      prefixIcon: Icon(Icons.verified_outlined, size: 18, color: _orangeColor),
                      suffixIcon: const Icon(Icons.lock_outline, size: 16, color: Colors.grey),
                      filled: true,
                      fillColor: const Color(0xFFF1F5F9),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  const Text('Cantidad de Litros (L)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _litrosCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      hintText: 'Ej: 450',
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: _primaryColor),
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  const Text('Costo Total (\$)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _costoCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      hintText: '0.00',
                      prefixIcon: const Padding(
                        padding: EdgeInsets.only(left: 14, top: 12),
                        child: Text('\$', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey)),
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: _primaryColor),
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  const Text('Evidencia de Carga', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _buildBotonEvidencia(
                          titulo: 'FOTO VOUCHER',
                          rutaImagen: _rutaFotoVoucher,
                          onTap: () => _seleccionarFoto(true),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildBotonEvidencia(
                          titulo: 'FOTO TABLERO',
                          rutaImagen: _rutaFotoTablero,
                          onTap: () => _seleccionarFoto(false),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _orangeColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _guardarRegistroCombustible,
                child: const Text(
                  'REGISTRAR CARGA',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.5),
                ),
              ),
            ),
          ),

          const SizedBox(height: 8),

          TextButton(
            onPressed: () => setState(() => _vistaActual = VistaCombustible.historial),
            child: const Text(
              'Ver Historial de Cargas',
              style: TextStyle(color: Color(0xFF475569), fontWeight: FontWeight.w600),
            ),
          ),

          const SizedBox(height: 8),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.info_outline, size: 15, color: Color(0xFFD97706)),
                  SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'LOS DATOS SE GUARDARÁN LOCALMENTE SI NO HAY SEÑAL',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFB45309)),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildBotonEvidencia({
    required String titulo,
    required String? rutaImagen,
    required VoidCallback onTap,
  }) {
    final bool tieneFoto = rutaImagen != null && rutaImagen.isNotEmpty;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 92,
        decoration: BoxDecoration(
          color: tieneFoto ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: tieneFoto ? Colors.green : Colors.grey.shade300,
            width: 1.2,
          ),
        ),
        child: tieneFoto
            ? Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: Image.file(
                      File(rutaImagen),
                      fit: BoxFit.cover,
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.check_circle, color: Colors.white, size: 24),
                        const SizedBox(height: 4),
                        Text(
                          titulo,
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.camera_alt_outlined, color: Color(0xFF475569), size: 24),
                  const SizedBox(height: 6),
                  Text(
                    titulo,
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                  ),
                ],
              ),
      ),
    );
  }
}