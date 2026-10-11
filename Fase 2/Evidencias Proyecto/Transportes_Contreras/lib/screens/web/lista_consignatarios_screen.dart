import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/consignatario.dart';
import '../../theme/app_colors.dart';
import '../../utils/csv_exporter.dart';
import 'consignatario_form_screen.dart';
import 'modificar/consignatario_modificar_screen.dart';

class ListaConsignatariosScreen extends StatefulWidget {
  const ListaConsignatariosScreen({super.key});

  @override
  State<ListaConsignatariosScreen> createState() => _ListaConsignatariosScreenState();
}

class _ListaConsignatariosScreenState extends State<ListaConsignatariosScreen> {
  final int _itemsPorPagina = 8;
  int _paginaActual = 1;

  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _datosOriginales = [];
  List<Map<String, dynamic>> _consignatarios = [];
  bool _isLoading = true;
  bool _ordenAscendente = true;

  int get _totalPaginas {
    if (_consignatarios.isEmpty) return 1;
    return (_consignatarios.length / _itemsPorPagina).ceil();
  }

  List<Map<String, dynamic>> get _consignatariosPaginados {
    if (_consignatarios.isEmpty) return [];
    final int inicio = (_paginaActual - 1) * _itemsPorPagina;
    if (inicio >= _consignatarios.length) return [];
    final int fin = (inicio + _itemsPorPagina > _consignatarios.length)
        ? _consignatarios.length
        : inicio + _itemsPorPagina;
    return _consignatarios.sublist(inicio, fin);
  }

  @override
  void initState() {
    super.initState();
    _cargarConsignatariosDesdeSupabase();
  }

  Future<void> _cargarConsignatariosDesdeSupabase() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      // Trae los datos del consignatario y los nombres de comuna y región vinculados
      final data = await Supabase.instance.client
          .from('consignatarios')
          .select('*, comunas(nombre), regiones(nombre)');

      if (mounted) {
        final List<dynamic> listaRemota = data as List<dynamic>? ?? [];
        final List<Map<String, dynamic>> datosMapeados = listaRemota.map((c) {
          final map = c as Map<String, dynamic>;
          final nombreEmpresa = (map['nombre_empresa'] ?? map['nombre'] ?? 'Sin Nombre').toString();
          final calle = (map['direccion'] ?? '').toString().trim();

          // Extraer nombres de los objetos foráneos devueltos por el join
          final comunaData = map['comunas'] as Map<String, dynamic>?;
          final regionData = map['regiones'] as Map<String, dynamic>?;

          final nombreComuna = (comunaData?['nombre'] ?? '').toString().trim();
          final nombreRegion = (regionData?['nombre'] ?? '').toString().trim();

          // Construir la dirección completa en formato: "Dirección, Comuna, Región"
          final List<String> partesDireccion = [];
          if (calle.isNotEmpty) partesDireccion.add(calle);
          if (nombreComuna.isNotEmpty) partesDireccion.add(nombreComuna);
          if (nombreRegion.isNotEmpty) partesDireccion.add(nombreRegion);

          final direccionCompleta = partesDireccion.isNotEmpty
              ? partesDireccion.join(', ')
              : 'Sin dirección registrada';

          return {
            'id': map['id'],
            'nombre': nombreEmpresa,
            'direccion': direccionCompleta,
            'calle': calle,
            'comuna': nombreComuna,
            'region': nombreRegion,
            'comuna_id': (map['comuna_id'] ?? '').toString(),
            'region_id': (map['region_id'] ?? '').toString(),
            'creado_en': (map['created_at'] ?? map['creado_en'] ?? '').toString(),
          };
        }).toList();

        _ordenarLista(datosMapeados, _ordenAscendente);

        setState(() {
          _datosOriginales = datosMapeados;
          _consignatarios = List<Map<String, dynamic>>.from(_datosOriginales);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error cargando consignatarios: $e');
      if (mounted) {
        setState(() {
          _datosOriginales = [];
          _consignatarios = [];
          _isLoading = false;
        });
      }
    }
  }

  void _ordenarLista(List<Map<String, dynamic>> lista, bool ascendente) {
    lista.sort((a, b) {
      final comp = a['nombre'].toString().toLowerCase().compareTo(b['nombre'].toString().toLowerCase());
      return ascendente ? comp : -comp;
    });
  }

  void _cambiarOrden() {
    setState(() {
      _ordenAscendente = !_ordenAscendente;
      _ordenarLista(_consignatarios, _ordenAscendente);
    });
  }

  void _filtrarConsignatarios(String query) {
    setState(() {
      _paginaActual = 1;
      if (query.isEmpty) {
        _consignatarios = List.from(_datosOriginales);
      } else {
        final q = query.toLowerCase();
        _consignatarios = _datosOriginales.where((c) {
          final nombre = c['nombre'].toString().toLowerCase();
          final direccion = c['direccion'].toString().toLowerCase();
          return nombre.contains(q) || direccion.contains(q);
        }).toList();
      }
      _ordenarLista(_consignatarios, _ordenAscendente);
    });
  }

  void _exportarCsvConsignatarios() {
    if (_consignatarios.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay consignatarios para exportar.')),
      );
      return;
    }

    final encabezados = [
      'ID',
      'Nombre Empresa',
      'Dirección / Calle',
      'Comuna',
      'Región',
      'Fecha Creación',
    ];

    final filas = _consignatarios.map((c) {
      return [
        c['id'] ?? '',
        c['nombre'] ?? '',
        c['calle'] ?? '',
        c['comuna'] ?? '',
        c['region'] ?? '',
        c['creado_en'] ?? '',
      ];
    }).toList();

    CsvExporter.descargarCsv(
      nombreArchivo: 'reporte_consignatarios_completo',
      encabezados: encabezados,
      filas: filas,
    );
  }

  /// Abre la screen de edición, precargada con los datos de [item] (el Map
  /// que usa la tarjeta). Si vuelve con `true` (se guardó algo), recarga la
  /// lista desde Supabase.
  Future<void> _abrirFormularioEdicion(Map<String, dynamic> item) async {
    final consignatarioExistente = Consignatario(
      id: item['id'],
      nombreEmpresa: item['nombre'] as String,
      direccion: item['calle'] as String,
      comunaId: item['comuna_id'] as String,
      regionId: item['region_id'] as String,
    );

    final actualizado = await Navigator.of(context).push<bool>(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => ConsignatarioModificarScreen(consignatario: consignatarioExistente),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );

    if (actualizado == true) {
      _cargarConsignatariosDesdeSupabase();
    }
  }

  Future<void> _eliminarConsignatario(Map<String, dynamic> item) async {
    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 24),
            SizedBox(width: 8),
            Text('Eliminar Consignatario', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          ],
        ),
        content: Text(
          '¿Estás seguro de que deseas eliminar "${item['nombre']}"?\nEsta acción no se puede deshacer.',
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
      await Supabase.instance.client
          .from('consignatarios')
          .delete()
          .eq('id', item['id']);

      if (mounted) {
        setState(() {
          _datosOriginales.removeWhere((c) => c['id'] == item['id']);
          _consignatarios.removeWhere((c) => c['id'] == item['id']);
          if (_paginaActual > _totalPaginas) {
            _paginaActual = _totalPaginas;
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Consignatario ${item['nombre']} eliminado.'),
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

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Cabecera y Botones de Acción
          LayoutBuilder(
            builder: (context, constraints) {
              final bool esPantallaAncha = constraints.maxWidth > 750;

              final Widget bloqueTextos = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.inventory_2_outlined, size: 14, color: Color(0xFFD97706)),
                      SizedBox(width: 6),
                      Text(
                        'BASE DE DATOS LOGÍSTICA',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFD97706),
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Lista de Consignatarios',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Visualice y gestione las empresas receptoras de mercancía para la emisión de guías de despacho y manifiestos.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                  ),
                ],
              );

              final Widget bloqueBotones = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton.icon(
                    onPressed: _exportarCsvConsignatarios,
                    icon: const Icon(Icons.download_outlined, size: 16, color: AppColors.textPrimary),
                    label: const Text(
                      'Exportar CSV',
                      style: TextStyle(fontSize: 13, color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                    ),
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
                          pageBuilder: (_, __, ___) => const ConsignatarioFormScreen(),
                          transitionDuration: Duration.zero,
                          reverseTransitionDuration: Duration.zero,
                        ),
                      );
                      _cargarConsignatariosDesdeSupabase();
                    },
                    icon: const Icon(Icons.add, size: 16, color: Colors.white),
                    label: const Text(
                      'AGREGAR CONSIGNATARIO',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
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
                  children: [
                    Expanded(child: bloqueTextos),
                    const SizedBox(width: 16),
                    bloqueBotones,
                  ],
                );
              } else {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    bloqueTextos,
                    const SizedBox(height: 16),
                    bloqueBotones,
                  ],
                );
              }
            },
          ),
          const SizedBox(height: 24),

          // 2. Buscador con Filtros y Badge Total
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
                      onChanged: _filtrarConsignatarios,
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: 'Buscar consignatario por nombre o dirección...',
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
                  icon: const Icon(Icons.filter_list, size: 16, color: Color(0xFF475569)),
                  label: const Text(
                    'Filtros',
                    style: TextStyle(fontSize: 12, color: Color(0xFF475569), fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: AppColors.surfaceMuted,
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    'Total: ${_consignatarios.length}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF475569),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // 3. Fila Directorio de Recepción + Ordenar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'DIRECTORIO DE RECEPCIÓN',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.6,
                ),
              ),
              Row(
                children: [
                  const Text('Ordenar:', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: _cambiarOrden,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Row(
                        children: [
                          Text(
                            _ordenAscendente ? 'A-Z' : 'Z-A',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            _ordenAscendente ? Icons.arrow_upward : Icons.arrow_downward,
                            size: 14,
                            color: AppColors.textPrimary,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Refrescar consignatarios',
                    icon: const Icon(Icons.refresh, size: 18, color: AppColors.textSecondary),
                    onPressed: _cargarConsignatariosDesdeSupabase,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 4. Grilla de Consignatarios
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 40.0),
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          else if (_consignatarios.isEmpty)
            _buildCartelSinRegistros()
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final int columnas = constraints.maxWidth > 850 ? 2 : 1;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _consignatariosPaginados.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columnas,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    mainAxisExtent: 88,
                  ),
                  itemBuilder: (context, index) {
                    final item = _consignatariosPaginados[index];
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: const Icon(
                              Icons.domain,
                              color: Color(0xFF334155),
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  item['nombre'],
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13.5,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.place_outlined, size: 13, color: AppColors.textSecondary),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        item['direccion'],
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert, size: 18, color: Color(0xFF94A3B8)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            onSelected: (accion) {
                              if (accion == 'modificar') _abrirFormularioEdicion(item);
                              if (accion == 'eliminar') _eliminarConsignatario(item);
                            },
                            itemBuilder: (ctx) => [
                              PopupMenuItem(
                                value: 'modificar',
                                child: Row(
                                  children: const [
                                    Icon(Icons.edit_outlined, size: 16, color: AppColors.primary),
                                    SizedBox(width: 8),
                                    Text('Modificar Consignatario', style: TextStyle(fontSize: 12.5, color: AppColors.primary, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'eliminar',
                                child: Row(
                                  children: const [
                                    Icon(Icons.delete_outline, size: 16, color: Colors.red),
                                    SizedBox(width: 8),
                                    Text('Eliminar Consignatario', style: TextStyle(fontSize: 12.5, color: Colors.red, fontWeight: FontWeight.bold)),
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

          // 5. Paginador
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildBotonPaginadorIcono(
                  Icons.chevron_left,
                  habilitado: _paginaActual > 1,
                  onTap: () => setState(() => _paginaActual--),
                ),
                const SizedBox(width: 6),
                _buildBotonNumeroPagina(1, habilitado: 1 <= _totalPaginas),
                const SizedBox(width: 4),
                _buildBotonNumeroPagina(2, habilitado: 2 <= _totalPaginas),
                const SizedBox(width: 4),
                _buildBotonNumeroPagina(3, habilitado: 3 <= _totalPaginas),
                const SizedBox(width: 4),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4.0),
                  child: Text('...', style: TextStyle(color: Color(0xFF94A3B8))),
                ),
                const SizedBox(width: 4),
                _buildBotonPaginadorIcono(
                  Icons.chevron_right,
                  habilitado: _paginaActual < _totalPaginas,
                  onTap: () => setState(() => _paginaActual++),
                ),
              ],
            ),
          ),

          const SizedBox(height: 48),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 16),

          // 6. Footer de Consignatarios
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '© 2026 Transportes Contreras Enterprise. Sistema Centralizado de Logística v2.4.1',
                style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
              ),
              Row(
                children: [
                  _buildFooterLink('Términos de Servicio'),
                  const SizedBox(width: 16),
                  _buildFooterLink('Soporte Operacional'),
                  const SizedBox(width: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFBBF7D0)),
                    ),
                    child: Row(
                      children: const [
                        Icon(Icons.circle, color: Color(0xFF16A34A), size: 6),
                        SizedBox(width: 5),
                        Text(
                          'SERVIDORES SEGUROS',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF16A34A)),
                        ),
                      ],
                    ),
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
            child: const Icon(Icons.domain_disabled_outlined, size: 40, color: Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 16),
          const Text('No se encontraron consignatarios registrados', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          const Text('No hay registros en la base de datos o el término buscado no coincide.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
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

  Widget _buildBotonPaginadorIcono(IconData icon, {required bool habilitado, required VoidCallback onTap}) {
    return InkWell(
      onTap: habilitado ? onTap : null,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: habilitado ? Colors.white : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: habilitado ? AppColors.border : AppColors.border.withOpacity(0.5)),
        ),
        child: Icon(icon, size: 16, color: habilitado ? const Color(0xFF475569) : const Color(0xFFCBD5E1)),
      ),
    );
  }

  Widget _buildFooterLink(String texto) {
    return InkWell(
      onTap: () {},
      child: Text(texto, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
    );
  }
}