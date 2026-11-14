import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_colors.dart';
import '../../widgets/admin_shell.dart';

typedef ViajeAdminItem = Map<String, dynamic>;

class GestionViajesAsignadosScreen extends StatefulWidget {
  const GestionViajesAsignadosScreen({super.key});

  @override
  State<GestionViajesAsignadosScreen> createState() => _GestionViajesAsignadosScreenState();
}

class _GestionViajesAsignadosScreenState extends State<GestionViajesAsignadosScreen> {
  final int _itemsPorPagina = 10;
  int _paginaActual = 1;
  final bool _ordenAscendente = false;

  List<ViajeAdminItem> _viajesOriginales = [];
  List<ViajeAdminItem> _viajesMostrados = [];
  bool _isLoading = true;

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _tablaScrollController = ScrollController();

  // Filtros
  DateTime? _fechaFiltro;
  String _estadoFiltro = 'todos'; // todos, pendiente, en_curso, completado, rechazado

  int get _totalPaginas {
    if (_viajesMostrados.isEmpty) return 1;
    return (_viajesMostrados.length / _itemsPorPagina).ceil();
  }

  List<ViajeAdminItem> get _viajesPaginados {
    if (_viajesMostrados.isEmpty) return [];
    final int inicio = (_paginaActual - 1) * _itemsPorPagina;
    if (inicio >= _viajesMostrados.length) return [];
    final int fin = (inicio + _itemsPorPagina > _viajesMostrados.length)
        ? _viajesMostrados.length
        : inicio + _itemsPorPagina;
    return _viajesMostrados.sublist(inicio, fin);
  }

  @override
  void initState() {
    super.initState();
    _cargarViajesDesdeSupabase();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tablaScrollController.dispose();
    super.dispose();
  }

  Future<void> _cargarViajesDesdeSupabase() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final supabase = Supabase.instance.client;

      final List listaRemota = await supabase
          .from('viajes')
          .select('''
            *,
            conductores (nombre_completo),
            camiones (patente),
            clientes (nombre_empresa),
            consignatarios (nombre_empresa)
          ''')
          .order('fecha_viaje', ascending: false)
          .order('hora_carga', ascending: true);

      if (mounted) {
        final List<ViajeAdminItem> mapeados = [];

        for (final item in listaRemota) {
          if (item is! Map) continue;
          final ViajeAdminItem v = ViajeAdminItem.from(item);

          final cond = v['conductores'] is Map ? v['conductores'] as Map : {};
          final cam = v['camiones'] is Map ? v['camiones'] as Map : {};
          final cli = v['clientes'] is Map ? v['clientes'] as Map : {};
          final cons = v['consignatarios'] is Map ? v['consignatarios'] as Map : {};

          final String conductorRut = (v['conductor_rut'] ?? '').toString();

          mapeados.add({
            'id': v['id'].toString(),
            'estado': (v['estado'] ?? 'pendiente').toString(),
            'fecha_viaje': v['fecha_viaje']?.toString() ?? '',
            'hora_carga': v['hora_carga']?.toString() ?? '--:--',
            'pallets': v['pallets']?.toString() ?? '0',
            'numero_guia': v['numero_guia']?.toString() ?? '',
            'conductor_rut': conductorRut,
            'conductor_nombre': cond['nombre_completo']?.toString() ?? conductorRut,
            'camion_id': v['camion_id']?.toString() ?? '',
            'camion_patente': cam['patente']?.toString() ?? 'S/P',
            'cliente_nombre': cli['nombre_empresa']?.toString() ?? 'Origen',
            'consignatario_id': v['consignatario_id']?.toString(),
            'consignatario_nombre': cons['nombre_empresa']?.toString() ?? 'Pendiente',
            'observaciones_conductor': v['observaciones_conductor']?.toString() ?? '',
          });
        }

        setState(() {
          _viajesOriginales = mapeados;
          _viajesMostrados = List<ViajeAdminItem>.from(_viajesOriginales);
          _isLoading = false;
        });
        _aplicarFiltros();
      }
    } catch (e) {
      debugPrint('Error cargando gestión de viajes: $e');
      if (mounted) {
        setState(() {
          _viajesOriginales = [];
          _viajesMostrados = [];
          _isLoading = false;
        });
      }
    }
  }

  void _aplicarFiltros() {
    final query = _searchController.text.toLowerCase().trim();

    final List<ViajeAdminItem> filtrados = _viajesOriginales.where((v) {
      if (query.isNotEmpty) {
        final id = v['id'].toString().toLowerCase();
        final guia = v['numero_guia'].toString().toLowerCase();
        final cond = v['conductor_nombre'].toString().toLowerCase();
        final cam = v['camion_patente'].toString().toLowerCase();
        final cli = v['cliente_nombre'].toString().toLowerCase();
        final cons = v['consignatario_nombre'].toString().toLowerCase();

        if (!id.contains(query) &&
            !guia.contains(query) &&
            !cond.contains(query) &&
            !cam.contains(query) &&
            !cli.contains(query) &&
            !cons.contains(query)) {
          return false;
        }
      }

      if (_estadoFiltro != 'todos') {
        if (v['estado'].toString().toLowerCase() != _estadoFiltro) {
          return false;
        }
      }

      if (_fechaFiltro != null) {
        final f = v['fecha_viaje'].toString();
        if (f.isNotEmpty) {
          final dt = DateTime.tryParse(f);
          if (dt == null ||
              dt.year != _fechaFiltro!.year ||
              dt.month != _fechaFiltro!.month ||
              dt.day != _fechaFiltro!.day) {
            return false;
          }
        } else {
          return false;
        }
      }

      return true;
    }).toList();

    filtrados.sort((a, b) {
      final fA = a['fecha_viaje'].toString();
      final fB = b['fecha_viaje'].toString();
      int comp = fA.compareTo(fB);
      if (comp == 0) {
        final hA = a['hora_carga'].toString();
        final hB = b['hora_carga'].toString();
        comp = hA.compareTo(hB);
      }
      return _ordenAscendente ? comp : -comp;
    });

    setState(() {
      _viajesMostrados = filtrados;
      if (_paginaActual > _totalPaginas) {
        _paginaActual = _totalPaginas > 0 ? _totalPaginas : 1;
      }
    });
  }

  Future<void> _eliminarViaje(ViajeAdminItem viaje) async {
    final estado = viaje['estado'].toString().toLowerCase();
    final esCompletado = estado == 'completado';

    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 24),
            SizedBox(width: 8),
            Text(
              'Cancelar y Eliminar Viaje',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
          ],
        ),
        content: Text(
          esCompletado
              ? 'Este viaje figura como COMPLETADO para ${viaje['conductor_nombre']}.\n\nSi lo eliminas, se descontará automáticamente de su Planilla Mensual y desaparecerá de su cartola.\n¿Deseas eliminarlo de todas formas?'
              : '¿Estás seguro de que deseas cancelar y eliminar el viaje asignado a ${viaje['conductor_nombre']} (${viaje['cliente_nombre']} ➔ ${viaje['consignatario_nombre']})?\nEsta acción retirará la ruta de la aplicación del conductor.',
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Sí, Eliminar Viaje', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    try {
      await Supabase.instance.client.from('viajes').delete().eq('id', viaje['id']);

      if (mounted) {
        _cargarViajesDesdeSupabase();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Viaje eliminado y planilla actualizada correctamente.'),
            backgroundColor: AppColors.textPrimary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al eliminar: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _mostrarModalReasignacion(ViajeAdminItem viaje) {
    String? nuevoConductorRut = viaje['conductor_rut']?.toString();
    String? nuevoCamionId = viaje['camion_id']?.toString();
    String? nuevoConsignatarioId = viaje['consignatario_id']?.toString();
    bool guardando = false;

    showDialog(
      context: context,
      builder: (modalCtx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text(
                'Reasignar Conductor, Camión o Destino',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              content: SizedBox(
                width: 480,
                child: FutureBuilder(
                  future: Future.wait([
                    Supabase.instance.client.from('conductores').select('rut, nombre_completo'),
                    Supabase.instance.client.from('camiones').select('id, patente'),
                    Supabase.instance.client.from('consignatarios').select('id, nombre_empresa'),
                  ]),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SizedBox(height: 180, child: Center(child: CircularProgressIndicator()));
                    }

                    final data = snapshot.data;
                    if (data == null) return const Text('Error cargando catálogos');

                    final List listCond = data[0] as List;
                    final List listCam = data[1] as List;
                    final List listCons = data[2] as List;

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cliente Origen: ${viaje['cliente_nombre']}',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                        ),
                        const SizedBox(height: 16),

                        DropdownButtonFormField<String>(
                          value: listCond.any((c) => c['rut'].toString() == nuevoConductorRut) ? nuevoConductorRut : null,
                          decoration: const InputDecoration(labelText: 'Conductor Asignado', border: OutlineInputBorder()),
                          items: listCond.map((c) {
                            return DropdownMenuItem<String>(
                              value: c['rut'].toString(),
                              child: Text(c['nombre_completo'].toString()),
                            );
                          }).toList(),
                          onChanged: (v) => setModalState(() => nuevoConductorRut = v),
                        ),
                        const SizedBox(height: 14),

                        DropdownButtonFormField<String>(
                          value: listCam.any((c) => c['id'].toString() == nuevoCamionId) ? nuevoCamionId : null,
                          decoration: const InputDecoration(labelText: 'Camión (Patente)', border: OutlineInputBorder()),
                          items: listCam.map((c) {
                            return DropdownMenuItem<String>(
                              value: c['id'].toString(),
                              child: Text(c['patente'].toString().toUpperCase()),
                            );
                          }).toList(),
                          onChanged: (v) => setModalState(() => nuevoCamionId = v),
                        ),
                        const SizedBox(height: 14),

                        DropdownButtonFormField<String>(
                          value: listCons.any((c) => c['id'].toString() == nuevoConsignatarioId) ? nuevoConsignatarioId : null,
                          decoration: const InputDecoration(
                            labelText: 'Consignatario (Destino)',
                            border: OutlineInputBorder(),
                          ),
                          items: listCons.map((c) {
                            return DropdownMenuItem<String>(
                              value: c['id'].toString(),
                              child: Text(c['nombre_empresa'].toString()),
                            );
                          }).toList(),
                          onChanged: (v) => setModalState(() => nuevoConsignatarioId = v),
                        ),
                      ],
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(modalCtx),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                  onPressed: guardando
                      ? null
                      : () async {
                          if (nuevoConductorRut == null || nuevoCamionId == null) return;
                          setModalState(() => guardando = true);
                          try {
                            final updatePayload = <String, dynamic>{
                              'conductor_rut': nuevoConductorRut,
                              'camion_id': nuevoCamionId,
                            };
                            if (nuevoConsignatarioId != null && nuevoConsignatarioId!.isNotEmpty) {
                              updatePayload['consignatario_id'] = nuevoConsignatarioId;
                            }
                            // Si el viaje estaba rechazado y se reasigna, vuelve a pendiente
                            if (viaje['estado'].toString().toLowerCase() == 'rechazado') {
                              updatePayload['estado'] = 'pendiente';
                              updatePayload['observaciones_conductor'] = null;
                            }

                            await Supabase.instance.client
                                .from('viajes')
                                .update(updatePayload)
                                .eq('id', viaje['id']);

                            if (mounted) {
                              Navigator.pop(modalCtx);
                              _cargarViajesDesdeSupabase();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Viaje actualizado/reasignado correctamente.')),
                              );
                            }
                          } catch (e) {
                            setModalState(() => guardando = false);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                              );
                            }
                          }
                        },
                  child: guardando
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('GUARDAR CAMBIOS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _formatearIdCorto(String uuid) {
    if (uuid.length > 8) return '#${uuid.substring(0, 8).toUpperCase()}';
    return '#${uuid.toUpperCase()}';
  }

  String _formatearFechaCorta(String raw) {
    if (raw.isEmpty) return '—';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  String _formatearHoraSimple(String raw) {
    if (raw.isEmpty || raw.toLowerCase() == 'null') return '—';
    if (raw.length >= 5) return raw.substring(0, 5);
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final double anchoPantalla = MediaQuery.of(context).size.width;
    final bool esPantallaPequena = anchoPantalla < 750;

    final int totalEnRuta = _viajesOriginales.where((v) => v['estado'].toString().toLowerCase() == 'en_curso').length;
    final int totalRechazados = _viajesOriginales.where((v) => v['estado'].toString().toLowerCase() == 'rechazado').length;

    return AdminShell(
      selectedIndex: 14,
      title: 'Gestión de Viajes Asignados',
      subtitle: 'Supervise, reasigne o elimine rutas asignadas a los conductores.',
      eyebrowIcon: Icons.route_outlined,
      showBackButton: true,
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: esPantallaPequena ? 16.0 : 32.0, vertical: 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'GESTIÓN OPERATIVA',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary, letterSpacing: 0.8),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Viajes Asignados y Rutas',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                  ],
                ),
                IconButton(
                  tooltip: 'Refrescar lista',
                  icon: const Icon(Icons.refresh, size: 22, color: AppColors.textSecondary),
                  onPressed: _cargarViajesDesdeSupabase,
                ),
              ],
            ),
            const SizedBox(height: 24),

            LayoutBuilder(
              builder: (context, constraints) {
                final double w = constraints.maxWidth > 900 ? (constraints.maxWidth - 32) / 3 : double.infinity;
                return Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    SizedBox(
                      width: w,
                      child: _buildMetricaCard('TOTAL VIAJES', '${_viajesOriginales.length}', Icons.assignment_outlined, Colors.blue),
                    ),
                    SizedBox(
                      width: w,
                      child: _buildMetricaCard('RUTAS EN CURSO', '$totalEnRuta', Icons.local_shipping_outlined, Colors.green),
                    ),
                    SizedBox(
                      width: w,
                      child: _buildMetricaCard(
                        'VIAJES RECHAZADOS',
                        '$totalRechazados',
                        Icons.flag_rounded,
                        Colors.red,
                        isAlert: totalRechazados > 0,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),

            _buildBarraFiltros(esPantallaPequena),
            const SizedBox(height: 24),

            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              )
            else if (_viajesMostrados.isEmpty)
              _buildEmptyState()
            else
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Scrollbar(
                  controller: _tablaScrollController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _tablaScrollController,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: 1220,
                      child: Column(
                        children: [
                          _buildEncabezadoTabla(),
                          for (final v in _viajesPaginados) _buildFilaTabla(v),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 16),
            _buildPaginacion(),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricaCard(String label, String value, IconData icon, Color color, {bool isAlert = false}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isAlert ? color : AppColors.border, width: isAlert ? 1.5 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppColors.textSecondary)),
              Icon(icon, size: 20, color: color),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: isAlert ? color : AppColors.textPrimary),
          ),
        ],
      ),
    );
  }

  Widget _buildBarraFiltros(bool esPantallaPequena) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: esPantallaPequena ? double.infinity : 320,
            height: 40,
            child: TextField(
              controller: _searchController,
              onChanged: (_) => _aplicarFiltros(),
              decoration: const InputDecoration(
                hintText: 'Buscar por chofer, patente, cliente o guía...',
                prefixIcon: Icon(Icons.search, size: 18),
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _fechaFiltro ?? DateTime.now(),
                firstDate: DateTime(2024),
                lastDate: DateTime(2030),
              );
              if (d != null) {
                setState(() {
                  _fechaFiltro = d;
                  _aplicarFiltros();
                });
              }
            },
            icon: const Icon(Icons.calendar_today, size: 16),
            label: Text(
              _fechaFiltro != null ? _formatearFechaCorta(_fechaFiltro!.toIso8601String()) : 'Todas las fechas',
            ),
          ),
          if (_fechaFiltro != null)
            IconButton(
              tooltip: 'Quitar filtro de fecha',
              icon: const Icon(Icons.clear, color: Colors.red, size: 18),
              onPressed: () => setState(() {
                _fechaFiltro = null;
                _aplicarFiltros();
              }),
            ),
          DropdownButton<String>(
            value: _estadoFiltro,
            underline: const SizedBox(),
            items: const [
              DropdownMenuItem(value: 'todos', child: Text('Estado: Todos')),
              DropdownMenuItem(value: 'pendiente', child: Text('Estado: Pendiente')),
              DropdownMenuItem(value: 'en_curso', child: Text('Estado: En Ruta')),
              DropdownMenuItem(value: 'rechazado', child: Text('Estado: Rechazados 🚩')),
              DropdownMenuItem(value: 'completado', child: Text('Estado: Completado')),
            ],
            onChanged: (val) {
              if (val != null) {
                setState(() {
                  _estadoFiltro = val;
                  _aplicarFiltros();
                });
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: const Column(
        children: [
          Icon(Icons.route_outlined, size: 40, color: AppColors.textSecondary),
          SizedBox(height: 16),
          Text('No se encontraron viajes con estos filtros', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        ],
      ),
    );
  }

  Widget _buildEncabezadoTabla() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: const Row(
        children: [
          SizedBox(width: 100, child: Text('ID / GUÍA', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.textSecondary))),
          SizedBox(width: 14),
          SizedBox(width: 130, child: Text('FECHA Y HORA', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.textSecondary))),
          SizedBox(width: 14),
          SizedBox(width: 200, child: Text('CONDUCTOR / CAMIÓN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.textSecondary))),
          SizedBox(width: 14),
          Expanded(child: Text('RUTA (CLIENTE ➔ CONSIGNATARIO)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.textSecondary))),
          SizedBox(width: 14),
          SizedBox(width: 140, child: Text('ESTADO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.textSecondary))),
          SizedBox(width: 14),
          SizedBox(width: 210, child: Text('ACCIONES', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.textSecondary))),
        ],
      ),
    );
  }

  Widget _buildFilaTabla(ViajeAdminItem item) {
    final est = item['estado'].toString().toLowerCase();
    final guia = item['numero_guia'].toString();
    final obs = item['observaciones_conductor'].toString();

    Color cEst = AppColors.warning;
    String tEst = 'PENDIENTE';
    if (est == 'en_curso') {
      cEst = Colors.green;
      tEst = 'EN RUTA';
    } else if (est == 'completado') {
      cEst = Colors.blueGrey;
      tEst = 'COMPLETADO';
    } else if (est == 'rechazado') {
      cEst = Colors.red;
      tEst = '🚩 RECHAZADO';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatearIdCorto(item['id'].toString()),
                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 13),
                ),
                if (guia.isNotEmpty)
                  Text('Guía: $guia', style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 130,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_formatearFechaCorta(item['fecha_viaje'].toString()), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                Text(_formatearHoraSimple(item['hora_carga'].toString()), style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 200,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['conductor_nombre'].toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                Text('🚛 ${item['camion_patente']}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item['cliente_nombre']} ➔ ${item['consignatario_nombre']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary),
                ),
                if (est == 'rechazado' && obs.isNotEmpty)
                  Text(
                    obs,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.red, fontSize: 11.5, fontWeight: FontWeight.w600),
                  )
                else
                  Text('📦 ${item['pallets']} pallets', style: const TextStyle(color: Colors.grey, fontSize: 11.5)),
              ],
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 140,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: cEst.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
                child: Text(tEst, style: TextStyle(color: cEst, fontWeight: FontWeight.bold, fontSize: 10.5)),
              ),
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 210,
            child: Row(
              children: [
                OutlinedButton(
                  onPressed: () => _mostrarModalReasignacion(item),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    minimumSize: Size.zero,
                    side: const BorderSide(color: AppColors.primary),
                  ),
                  child: const Text('Reasignar', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.primary)),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => _eliminarViaje(item),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    minimumSize: Size.zero,
                    side: const BorderSide(color: Colors.red),
                  ),
                  child: const Text('Eliminar', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.red)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaginacion() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: _paginaActual > 1 ? () => setState(() => _paginaActual--) : null,
        ),
        Text('Página $_paginaActual de $_totalPaginas'),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: _paginaActual < _totalPaginas ? () => setState(() => _paginaActual++) : null,
        ),
      ],
    );
  }
}