import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/cliente.dart';
import '../../theme/app_colors.dart';
import 'cliente_form_screen.dart';
import 'modificar/cliente_modificar_screen.dart';
import '../../utils/csv_exporter.dart';

class ListaClientesScreen extends StatefulWidget {
  const ListaClientesScreen({super.key});

  @override
  State<ListaClientesScreen> createState() => _ListaClientesScreenState();
}

class _ListaClientesScreenState extends State<ListaClientesScreen> {
  final int _itemsPorPagina = 9;
  int _paginaActual = 1;

  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _datosOriginales = [];
  List<Map<String, dynamic>> _clientes = [];
  bool _isLoading = true;

  int get _totalPaginas {
    if (_clientes.isEmpty) return 1;
    return (_clientes.length / _itemsPorPagina).ceil();
  }

  List<Map<String, dynamic>> get _clientesPaginados {
    if (_clientes.isEmpty) return [];
    final int inicio = (_paginaActual - 1) * _itemsPorPagina;
    if (inicio >= _clientes.length) return [];
    final int fin = (inicio + _itemsPorPagina > _clientes.length)
        ? _clientes.length
        : inicio + _itemsPorPagina;
    return _clientes.sublist(inicio, fin);
  }

  @override
  void initState() {
    super.initState();
    _cargarClientesDesdeSupabase();
  }

  Future<void> _cargarClientesDesdeSupabase() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      // Trae todas las columnas de la tabla 'clientes'
      final data = await Supabase.instance.client
          .from('clientes')
          .select('*');

      if (mounted) {
        final List<dynamic> listaRemota = data as List<dynamic>? ?? [];
        final List<Map<String, dynamic>> datosMapeados = listaRemota.map((c) {
          final map = c as Map<String, dynamic>;
          final nombre = (map['nombre_empresa'] ?? 'Empresa Registrada').toString();

          String iniciales = 'CL';
          final partes = nombre.trim().split(' ');
          if (partes.length >= 2 && partes[0].isNotEmpty && partes[1].isNotEmpty) {
            iniciales = '${partes[0][0]}${partes[1][0]}'.toUpperCase();
          } else if (partes.isNotEmpty && partes[0].isNotEmpty) {
            iniciales = partes[0][0].toUpperCase();
          }

          return {
            // Columnas directas de la base de datos
            'id': (map['id'] ?? '').toString(),
            'nombre_empresa': nombre,
            'nombre_contacto': (map['nombre_contacto'] ?? '').toString(),
            'telefono': (map['telefono'] ?? '').toString(),
            'direccion': (map['direccion'] ?? '').toString(),
            'valor_viaje_camion': map['valor_viaje_camion'] ?? 0,
            'tarifa_nocturna_camion': map['tarifa_nocturna_camion'] ?? 0,
            'valor_peoneta_camion': map['valor_peoneta_camion'] ?? 0,
            'valor_viaje_rampla': map['valor_viaje_rampla'] ?? 0,
            'tarifa_nocturna_rampla': map['tarifa_nocturna_rampla'] ?? 0,
            'valor_peoneta_rampla': map['valor_peoneta_rampla'] ?? 0,
            'creado_en': (map['creado_en'] ?? '').toString(),
            'region_id': (map['region_id'] ?? '').toString(),
            'comuna_id': (map['comuna_id'] ?? '').toString(),

            // Llaves que usa la UI de las tarjetas
            'nombre': nombre,
            'iniciales': iniciales,
            'contacto': (map['nombre_contacto'] ?? '').toString(),
            'email': 'contacto@${nombre.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')}.cl',
            'ubicacion': (map['direccion'] ?? 'Sin dirección').toString(),
            'ultimo_envio': 'Hace 2 días',
            'estado': 'ACTIVO',
          };
        }).toList();

        datosMapeados.sort((a, b) => a['nombre'].toString().compareTo(b['nombre'].toString()));

        setState(() {
          _datosOriginales = datosMapeados;
          _clientes = List<Map<String, dynamic>>.from(_datosOriginales);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error cargando clientes desde Supabase: $e');
      if (mounted) {
        setState(() {
          _datosOriginales = [];
          _clientes = [];
          _isLoading = false;
        });
      }
    }
  }

  /// Abre el formulario de cliente en modo edición, precargado con los
  /// datos de [item] (el Map que usa la tarjeta). Si vuelve con `true`
  /// (se guardó algo), recarga la lista desde Supabase.
  Future<void> _abrirFormularioEdicion(Map<String, dynamic> item) async {
    final clienteExistente = Cliente(
      id: item['id'] as String?,
      nombreEmpresa: item['nombre_empresa'] as String,
      nombreContacto: item['nombre_contacto'] as String,
      telefono: item['telefono'] as String,
      direccion: item['direccion'] as String,
      comunaId: item['comuna_id'] as String,
      regionId: item['region_id'] as String,
      valorViajeCamion: (item['valor_viaje_camion'] as num?)?.toDouble() ?? 0,
      tarifaNocturnaCamion: (item['tarifa_nocturna_camion'] as num?)?.toDouble() ?? 0,
      valorPeonetaCamion: (item['valor_peoneta_camion'] as num?)?.toDouble() ?? 0,
      valorViajeRampla: (item['valor_viaje_rampla'] as num?)?.toDouble() ?? 0,
      tarifaNocturnaRampla: (item['tarifa_nocturna_rampla'] as num?)?.toDouble() ?? 0,
      valorPeonetaRampla: (item['valor_peoneta_rampla'] as num?)?.toDouble() ?? 0,
    );

    final actualizado = await Navigator.of(context).push<bool>(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => ClienteModificarScreen(cliente: clienteExistente),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );

    if (actualizado == true) {
      _cargarClientesDesdeSupabase();
    }
  }

  Future<void> _eliminarCliente(Map<String, dynamic> cliente) async {
    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 24),
            SizedBox(width: 8),
            Text('Eliminar Cliente', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          ],
        ),
        content: Text(
          '¿Estás seguro de que deseas eliminar la empresa "${cliente['nombre']}"?\nEsta acción no se puede deshacer.',
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
            child: const Text('Eliminar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    try {
      final dynamic query;
      if (cliente['id'] != null) {
        query = Supabase.instance.client.from('clientes').delete().eq('id', cliente['id']);
      } else {
        query = Supabase.instance.client.from('clientes').delete().eq('nombre_empresa', cliente['nombre']);
      }

      final resultado = await query.select();

      if (mounted) {
        setState(() {
          _datosOriginales.removeWhere((c) => c['id'] == cliente['id']);
          _clientes.removeWhere((c) => c['id'] == cliente['id']);
          if (_paginaActual > _totalPaginas) {
            _paginaActual = _totalPaginas;
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(resultado.isNotEmpty
                ? 'Cliente ${cliente['nombre']} eliminado de Supabase.'
                : 'Cliente removido de la vista.'),
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

  void _filtrarClientes(String query) {
    setState(() {
      _paginaActual = 1;
      if (query.isEmpty) {
        _clientes = List.from(_datosOriginales);
      } else {
        _clientes = _datosOriginales.where((c) {
          final nombre = c['nombre'].toString().toLowerCase();
          final contacto = c['contacto'].toString().toLowerCase();
          final ciudad = c['ubicacion'].toString().toLowerCase();
          final q = query.toLowerCase();
          return nombre.contains(q) || contacto.contains(q) || ciudad.contains(q);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final bool esPantallaAncha = constraints.maxWidth > 750;

              final Widget bloqueTextos = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'BASE DE DATOS',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.primary, letterSpacing: 0.8),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Lista de Clientes', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.successBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF86EFAC)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.circle, color: AppColors.success, size: 6),
                            SizedBox(width: 5),
                            Text('Base Sincronizada', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.success)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text('Gestione las relaciones corporativas y detalles de contacto de su cartera logística de Transportes Contreras.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ],
              );

              final Widget bloqueBotones = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton.icon(
                    onPressed: _exportarCsvClientes, // () {}
                    icon: const Icon(Icons.download_outlined, size: 16, color: AppColors.textPrimary),
                    label: const Text('Exportar CSV', style: TextStyle(fontSize: 13, color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: AppColors.border),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () async {
                      await Navigator.of(context).push(
                        PageRouteBuilder(
                          pageBuilder: (_, __, ___) => const ClienteFormScreen(),
                          transitionDuration: Duration.zero,
                          reverseTransitionDuration: Duration.zero,
                        ),
                      );
                      _cargarClientesDesdeSupabase();
                    },
                    icon: const Icon(Icons.add, size: 16, color: Colors.white),
                    label: const Text('+ AGREGAR CLIENTE', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      elevation: 0,
                    ),
                  ),
                ],
              );

              if (esPantallaAncha) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [Expanded(child: bloqueTextos), const SizedBox(width: 16), bloqueBotones],
                );
              } else {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [bloqueTextos, const SizedBox(height: 16), bloqueBotones],
                );
              }
            },
          ),
          const SizedBox(height: 24),

          // Métricas
          LayoutBuilder(
            builder: (context, constraints) {
              final double cardWidth = constraints.maxWidth > 900
                  ? (constraints.maxWidth - (16 * 2)) / 3
                  : double.infinity;

              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  SizedBox(
                    width: cardWidth,
                    child: _buildTarjetaMetrica(
                      label: 'CLIENTES TOTALES',
                      valor: '${_datosOriginales.length}',
                      icono: Icons.domain,
                      iconColor: AppColors.textSecondary,
                      subtitulo: '↗ +8 este mes',
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _buildTarjetaMetrica(
                      label: 'RECURRENCIA PROM.',
                      valor: '94%',
                      icono: Icons.sync_alt,
                      iconColor: Colors.blue,
                      subtitulo: null,
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _buildTarjetaMetrica(
                      label: 'INGRESOS Q2',
                      valor: '\$12.4M',
                      icono: Icons.trending_up,
                      iconColor: Colors.green,
                      subtitulo: null,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),

          // Buscador con Filtros Avanzados y Limpiar
          Container(
            padding: const EdgeInsets.all(12.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: _filtrarClientes,
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: 'Buscar por nombre de empresa, contacto o ubicación...',
                        hintStyle: TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
                        prefixIcon: Icon(Icons.search, size: 18, color: Color(0xFF94A3B8)),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 9),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.tune, size: 16, color: Color(0xFF475569)),
                  label: const Text('Filtros Avanzados', style: TextStyle(fontSize: 12, color: Color(0xFF475569), fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: AppColors.surfaceMuted,
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(width: 10),
                TextButton(
                  onPressed: () {
                    _searchController.clear();
                    _filtrarClientes('');
                  },
                  child: const Text('Limpiar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Fila Directorio Empresarial + Ordenar por + Refrescar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text('DIRECTORIO EMPRESARIAL', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 0.5)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(10)),
                    child: Text('${_clientes.length} Resultados', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
                  ),
                ],
              ),
              Row(
                children: [
                  const Text('Ordenar por:', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  const SizedBox(width: 8),
                  const Text('Nombre (A-Z)', style: TextStyle(fontSize: 12, color: Color(0xFF1E293B), fontWeight: FontWeight.bold)),
                  const SizedBox(width: 12),
                  IconButton(
                    tooltip: 'Refrescar clientes',
                    icon: const Icon(Icons.refresh, size: 18, color: AppColors.textSecondary),
                    onPressed: _cargarClientesDesdeSupabase,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Grilla de Cards
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 40.0),
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          else if (_clientes.isEmpty)
            _buildCartelSinRegistros()
          else
            LayoutBuilder(
              builder: (context, constraints) {
                int columnas = constraints.maxWidth > 1050 ? 3 : (constraints.maxWidth > 700 ? 2 : 1);
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _clientesPaginados.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columnas,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    mainAxisExtent: 250,
                  ),
                  itemBuilder: (context, index) {
                    final item = _clientesPaginados[index];
                    return Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor: const Color(0xFF334155),
                                child: Text(item['iniciales'], style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item['nombre'],
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary, height: 1.2),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Icon(Icons.people_outline, size: 14, color: AppColors.textSecondary),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text('Contacto: ${item['contacto']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(color: AppColors.successBg, borderRadius: BorderRadius.circular(6)),
                                child: const Text('ACTIVO', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.success)),
                              ),
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert, size: 18, color: Color(0xFF64748B)),
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.only(left: 4),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                onSelected: (accion) {
                                  if (accion == 'modificar') _abrirFormularioEdicion(item);
                                  if (accion == 'eliminar') _eliminarCliente(item);
                                },
                                itemBuilder: (ctx) => [
                                  PopupMenuItem(
                                    value: 'modificar',
                                    child: Row(
                                      children: const [
                                        Icon(Icons.edit_outlined, size: 16, color: AppColors.primary),
                                        SizedBox(width: 8),
                                        Text('Modificar Cliente', style: TextStyle(fontSize: 12.5, color: AppColors.primary, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'eliminar',
                                    child: Row(
                                      children: const [
                                        Icon(Icons.delete_outline, size: 16, color: Colors.red),
                                        SizedBox(width: 8),
                                        Text('Eliminar Cliente', style: TextStyle(fontSize: 12.5, color: Colors.red, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          const Divider(height: 1, color: Color(0xFFF1F5F9)),
                          const SizedBox(height: 14),

                          // Fila con EMAIL y TELÉFONO
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: const [
                                        Icon(Icons.mail_outline, size: 13, color: AppColors.textSecondary),
                                        SizedBox(width: 4),
                                        Text('EMAIL', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 0.5)),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(item['email'], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: Color(0xFF1E293B), fontWeight: FontWeight.w500)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: const [
                                        Icon(Icons.call_outlined, size: 13, color: AppColors.textSecondary),
                                        SizedBox(width: 4),
                                        Text('TELÉFONO', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 0.5)),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(item['telefono'], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: Color(0xFF1E293B), fontWeight: FontWeight.w500)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Bloque UBICACIÓN
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: const [
                                  Icon(Icons.place_outlined, size: 13, color: AppColors.textSecondary),
                                  SizedBox(width: 4),
                                  Text('UBICACIÓN', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 0.5)),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(item['ubicacion'], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: Color(0xFF1E293B), fontWeight: FontWeight.w500)),
                            ],
                          ),
                          const Spacer(),
                          const Divider(height: 1, color: Color(0xFFF1F5F9)),
                          const SizedBox(height: 10),

                          // Pie de la tarjeta
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.access_time, size: 13, color: AppColors.textSecondary),
                                  const SizedBox(width: 4),
                                  Text('Último envío: ${item['ultimo_envio']}', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                                ],
                              ),
                              InkWell(
                                onTap: () {},
                                child: Row(
                                  children: const [
                                    Text('Ver Ficha', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary)),
                                    SizedBox(width: 2),
                                    Icon(Icons.chevron_right, size: 14, color: AppColors.primary),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          const SizedBox(height: 28),

          // Paginador
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildBotonNumeroPagina(1, habilitado: 1 <= _totalPaginas),
                const SizedBox(width: 4),
                _buildBotonNumeroPagina(2, habilitado: 2 <= _totalPaginas),
                const SizedBox(width: 4),
                _buildBotonNumeroPagina(3, habilitado: 3 <= _totalPaginas),
                const SizedBox(width: 4),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 4.0), child: Text('...', style: TextStyle(color: Color(0xFF94A3B8)))),
                _buildBotonNumeroPagina(12, habilitado: 12 <= _totalPaginas),
              ],
            ),
          ),

          const SizedBox(height: 48),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 16),

          // Footer de Clientes
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('© 2026 Transportes Contreras Enterprise. Sistema de Gestión Logística v2.4.1', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
              Row(
                children: [
                  _buildFooterLink('Términos de Servicio'),
                  const SizedBox(width: 16),
                  _buildFooterLink('Soporte IT'),
                  const SizedBox(width: 16),
                  Row(
                    children: const [
                      Icon(Icons.circle, color: Colors.green, size: 7),
                      SizedBox(width: 5),
                      Text('SERVIDORES EN LÍNEA', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green)),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCartelSinRegistros() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48.0, horizontal: 24.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(color: AppColors.surfaceMuted, shape: BoxShape.circle),
            child: const Icon(Icons.business_center_outlined, size: 40, color: Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 16),
          const Text('No se encontraron clientes registrados', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          const Text('No hay clientes en la base de datos o el término ingresado no coincide.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildTarjetaMetrica({
    required String label,
    required String valor,
    required IconData icono,
    required Color iconColor,
    String? subtitulo,
  }) {
    return Container(
      height: 115,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 0.5)),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: iconColor.withOpacity(0.1), shape: BoxShape.circle),
                child: Icon(icono, size: 16, color: iconColor),
              ),
            ],
          ),
          Text(valor, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          subtitulo != null
              ? Text(subtitulo, style: const TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold))
              : const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildBotonNumeroPagina(int pagina, {required bool habilitado}) {
    final bool activo = _paginaActual == pagina;
    return InkWell(
      onTap: habilitado ? () => setState(() => _paginaActual = pagina) : null,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: activo ? AppColors.primary : (habilitado ? Colors.white : const Color(0xFFF8FAFC)),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: activo ? AppColors.primary : (habilitado ? AppColors.border : AppColors.border.withOpacity(0.5)),
          ),
        ),
        child: Text(
          '$pagina',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: activo ? Colors.white : (habilitado ? const Color(0xFF475569) : const Color(0xFFCBD5E1)),
          ),
        ),
      ),
    );
  }

  Widget _buildFooterLink(String texto) {
    return InkWell(
      onTap: () {},
      child: Text(texto, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
    );
  }

  void _exportarCsvClientes() {
    if (_clientes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay clientes para exportar.')),
      );
      return;
    }

    final encabezados = [
      'ID',
      'Razón Social / Empresa',
      'Contacto',
      'Teléfono',
      'Dirección',
      'Valor Viaje (Camión Simple)',
      'Tarifa Nocturna (Camión Simple)',
      'Valor Peoneta (Camión Simple)',
      'Valor Viaje (Rampla)',
      'Tarifa Nocturna (Rampla)',
      'Valor Peoneta (Rampla)',
      'Fecha Creación',
      'Region ID',
      'Comuna ID',
    ];

    final filas = _clientes.map((c) {
      return [
        c['id'] ?? '',
        c['nombre_empresa'] ?? '',
        c['nombre_contacto'] ?? '',
        c['telefono'] ?? '',
        c['direccion'] ?? '',
        c['valor_viaje_camion'] ?? '',
        c['tarifa_nocturna_camion'] ?? '',
        c['valor_peoneta_camion'] ?? '',
        c['valor_viaje_rampla'] ?? '',
        c['tarifa_nocturna_rampla'] ?? '',
        c['valor_peoneta_rampla'] ?? '',
        c['creado_en'] ?? '',
        c['region_id'] ?? '',
        c['comuna_id'] ?? '',
      ];
    }).toList();

    CsvExporter.descargarCsv(
      nombreArchivo: 'reporte_clientes_completo',
      encabezados: encabezados,
      filas: filas,
    );
  }
}