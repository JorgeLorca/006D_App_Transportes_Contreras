import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_colors.dart';
import '../../widgets/search_filter_bar.dart';
import 'camion_form_screen.dart';

class ListaCamionesScreen extends StatefulWidget {
  const ListaCamionesScreen({super.key});

  @override
  State<ListaCamionesScreen> createState() => _ListaCamionesScreenState();
}

class _ListaCamionesScreenState extends State<ListaCamionesScreen> {
  final int _itemsPorPagina = 12;
  int _paginaActual = 1;

  List<Map<String, dynamic>> _datosOriginales = [];
  List<Map<String, dynamic>> _camiones = [];
  bool _isLoading = true;

  int get _totalPaginas {
    if (_camiones.isEmpty) return 1;
    return (_camiones.length / _itemsPorPagina).ceil();
  }

  List<Map<String, dynamic>> get _camionesPaginados {
    if (_camiones.isEmpty) return [];
    final int inicio = (_paginaActual - 1) * _itemsPorPagina;
    if (inicio >= _camiones.length) return [];
    final int fin = (inicio + _itemsPorPagina > _camiones.length)
        ? _camiones.length
        : inicio + _itemsPorPagina;
    return _camiones.sublist(inicio, fin);
  }

  @override
  void initState() {
    super.initState();
    _cargarCamionesDesdeSupabase();
  }

  Future<void> _cargarCamionesDesdeSupabase() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final data = await Supabase.instance.client
          .from('camiones')
          .select('id, patente, marca, modelo, estado');

      if (mounted) {
        final List<dynamic> listaRemota = data as List<dynamic>? ?? [];
        final List<Map<String, dynamic>> datosMapeados = listaRemota.map((c) {
          final map = c as Map<String, dynamic>;
          final estadoStr = (map['estado'] ?? '').toString().toLowerCase();
          return {
            'id': map['id'],
            'patente': (map['patente'] ?? 'S/P').toString(),
            'marca': (map['marca'] ?? 'Genérico').toString(),
            'modelo': (map['modelo'] ?? 'S/M').toString(),
            'disponible': estadoStr == 'disponible' || estadoStr == 'activo',
          };
        }).toList();

        setState(() {
          _datosOriginales = datosMapeados;
          _camiones = List<Map<String, dynamic>>.from(_datosOriginales);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error cargando camiones desde Supabase: $e');
      if (mounted) {
        setState(() {
          _datosOriginales = [];
          _camiones = [];
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _eliminarCamion(Map<String, dynamic> camion) async {
    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 24),
            SizedBox(width: 8),
            Text('Eliminar Camión', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          ],
        ),
        content: Text(
          '¿Estás seguro de que deseas eliminar el camión con patente "${camion['patente']}"?\nEsta acción no se puede deshacer.',
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
      if (camion['id'] != null) {
        query = Supabase.instance.client.from('camiones').delete().eq('id', camion['id']);
      } else {
        query = Supabase.instance.client.from('camiones').delete().eq('patente', camion['patente']);
      }

      final resultado = await query.select();

      if (mounted) {
        setState(() {
          _datosOriginales.removeWhere((c) => c['patente'] == camion['patente']);
          _camiones.removeWhere((c) => c['patente'] == camion['patente']);
          if (_paginaActual > _totalPaginas) {
            _paginaActual = _totalPaginas;
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(resultado.isNotEmpty 
                ? 'Camión ${camion['patente']} eliminado de Supabase.' 
                : 'Camión removido de la vista.'),
            backgroundColor: AppColors.textPrimary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al eliminar camión: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _filtrarCamiones(String query) {
    setState(() {
      _paginaActual = 1;
      if (query.isEmpty) {
        _camiones = List.from(_datosOriginales);
      } else {
        _camiones = _datosOriginales.where((c) {
          final patente = c['patente'].toString().toLowerCase();
          final marca = c['marca'].toString().toLowerCase();
          final modelo = c['modelo'].toString().toLowerCase();
          final q = query.toLowerCase();
          return patente.contains(q) || marca.contains(q) || modelo.contains(q);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner Hero
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 160),
            padding: const EdgeInsets.symmetric(horizontal: 40.0, vertical: 32.0),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF0F172A),
                  const Color(0xFF1E293B).withOpacity(0.92),
                  const Color(0xFF334155).withOpacity(0.85),
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Text(
                  'LISTA DE CAMIONES',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.5),
                ),
                SizedBox(height: 6),
                Text(
                  'Administre las unidades de su flota. Visualización rápida de patentes, marcas y modelos.',
                  style: TextStyle(fontSize: 13, color: Colors.white70, height: 1.4),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 36.0, vertical: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final bool esPantallaAncha = constraints.maxWidth > 650;
                    final Widget buscador = SearchFilterBar(
                      hintText: 'Buscar por patente, marca o modelo...',
                      onSearchChanged: _filtrarCamiones,
                    );

                    final Widget botonAgregar = ElevatedButton.icon(
                      onPressed: () async {
                        await Navigator.of(context).push(
                          PageRouteBuilder(
                            pageBuilder: (_, __, ___) => const CamionFormScreen(),
                            transitionDuration: Duration.zero,
                            reverseTransitionDuration: Duration.zero,
                          ),
                        );
                        _cargarCamionesDesdeSupabase();
                      },
                      icon: const Icon(Icons.add, size: 16, color: Colors.white),
                      label: const Text('Agregar Camión', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                    );

                    if (esPantallaAncha) {
                      return Row(
                        children: [
                          Expanded(child: buscador),
                          const SizedBox(width: 16),
                          botonAgregar,
                        ],
                      );
                    } else {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          buscador,
                          const SizedBox(height: 12),
                          botonAgregar,
                        ],
                      );
                    }
                  },
                ),
                const SizedBox(height: 28),

                Row(
                  children: [
                    const Text('Inventario de Vehículos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(10)),
                      child: Text('${_camiones.length} Total', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Refrescar datos',
                      icon: const Icon(Icons.refresh, size: 18, color: AppColors.textSecondary),
                      onPressed: _cargarCamionesDesdeSupabase,
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                if (_isLoading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 40.0),
                      child: CircularProgressIndicator(color: AppColors.primary),
                    ),
                  )
                else if (_camiones.isEmpty)
                  _buildCartelSinRegistros()
                else
                  LayoutBuilder(
                    builder: (context, constraints) {
                      int columnas = constraints.maxWidth > 1050 ? 3 : (constraints.maxWidth > 650 ? 2 : 1);
                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _camionesPaginados.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columnas,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          mainAxisExtent: 110,
                        ),
                        itemBuilder: (context, index) {
                          final item = _camionesPaginados[index];
                          final bool disp = item['disponible'];
                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(10)),
                                  child: const Icon(Icons.local_shipping_outlined, color: AppColors.textSecondary, size: 26),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Row(
                                        children: [
                                          Text(item['patente'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary)),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: disp ? AppColors.successBg : const Color(0xFFFEE2E2),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              disp ? 'DISPONIBLE' : 'NO DISPONIBLE',
                                              style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: disp ? AppColors.success : const Color(0xFF991B1B)),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(item['marca'], style: const TextStyle(fontSize: 12, color: Color(0xFF334155), fontWeight: FontWeight.w500)),
                                      Text(item['modelo'], style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                                    ],
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  icon: const Icon(Icons.more_vert, size: 18, color: Color(0xFF94A3B8)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  onSelected: (accion) {
                                    if (accion == 'eliminar') _eliminarCamion(item);
                                  },
                                  itemBuilder: (ctx) => [
                                    PopupMenuItem(
                                      value: 'eliminar',
                                      child: Row(
                                        children: const [
                                          Icon(Icons.delete_outline, size: 16, color: Colors.red),
                                          SizedBox(width: 8),
                                          Text('Eliminar Camión', style: TextStyle(fontSize: 12.5, color: Colors.red, fontWeight: FontWeight.bold)),
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

                const SizedBox(height: 36),

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
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4.0),
                        child: Text('...', style: TextStyle(color: Color(0xFF94A3B8))),
                      ),
                      _buildBotonNumeroPagina(12, habilitado: 12 <= _totalPaginas),
                      const SizedBox(width: 8),
                      _buildBotonSiguiente(
                        habilitado: _paginaActual < _totalPaginas,
                        alPresionar: () => setState(() => _paginaActual++),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 48),
                const Divider(height: 1, color: AppColors.border),
                const SizedBox(height: 16),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('© 2026 Transportes Contreras Enterprise • Fleet System v4.2.1', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                    Row(
                      children: [
                        _buildFooterLink('Soporte Técnico'),
                        const SizedBox(width: 16),
                        _buildFooterLink('Privacidad'),
                        const SizedBox(width: 16),
                        Row(
                          children: const [
                            Icon(Icons.circle, color: Colors.green, size: 7),
                            SizedBox(width: 5),
                            Text('SERVIDOR OPERATIVO', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green)),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
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
            child: const Icon(Icons.no_crash_outlined, size: 40, color: Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 16),
          const Text('No se encontraron vehículos registrados', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          const Text('No hay camiones en la base de datos o el criterio de búsqueda no arrojó resultados.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
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

  Widget _buildBotonSiguiente({required bool habilitado, required VoidCallback alPresionar}) {
    return OutlinedButton(
      onPressed: habilitado ? alPresionar : null,
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white,
        side: BorderSide(color: habilitado ? AppColors.border : AppColors.border.withOpacity(0.5)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      ),
      child: Text(
        'Siguiente',
        style: TextStyle(
          fontSize: 12,
          color: habilitado ? AppColors.textPrimary : const Color(0xFFCBD5E1),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildFooterLink(String texto) {
    return InkWell(
      onTap: () {},
      child: Text(
        texto,
        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
      ),
    );
  }
}