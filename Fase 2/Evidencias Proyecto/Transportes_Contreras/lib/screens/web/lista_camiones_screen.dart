import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/camion.dart';
import '../../theme/app_colors.dart';
import 'camion_form_screen.dart';
import 'modificar/camion_modificar_screen.dart';
import '../../widgets/page_hero_banner.dart';
import '../../widgets/entity_list_card.dart';
import '../../widgets/list_page_widgets.dart';

typedef CamionItem = Map<String, dynamic>;

class ListaCamionesScreen extends StatefulWidget {
  const ListaCamionesScreen({super.key});

  @override
  State<ListaCamionesScreen> createState() => _ListaCamionesScreenState();
}

class _ListaCamionesScreenState extends State<ListaCamionesScreen> {
  final int _itemsPorPagina = 12;
  final TextEditingController _searchController = TextEditingController();
  int _paginaActual = 1;

  // Filtro avanzado de estado: 'todos', 'disponible', 'no_disponible'
  String _filtroDisponibilidad = 'todos';

  // Orden por patente
  bool _ordenAscendente = true;

  List<CamionItem> _datosOriginales = [];
  List<CamionItem> _camiones = [];
  bool _isLoading = true;

  int get _totalPaginas {
    if (_camiones.isEmpty) return 1;
    return (_camiones.length / _itemsPorPagina).ceil();
  }

  List<CamionItem> get _camionesPaginados {
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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _cargarCamionesDesdeSupabase() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final data = await Supabase.instance.client.from('camiones').select(
          'id, patente, marca, modelo, anio, estado, url_revision_tecnica, '
          'url_permiso_circulacion, url_seguro_soap, url_padron');

      if (mounted) {
        final List<dynamic> listaRemota = data as List<dynamic>? ?? [];
        final List<CamionItem> datosMapeados = listaRemota.map((c) {
          final map = c as CamionItem;
          final estadoStr = (map['estado'] ?? '').toString().toLowerCase().trim();
          return <String, dynamic>{
            'id': map['id'],
            'patente': (map['patente'] ?? 'S/P').toString(),
            'marca': (map['marca'] ?? 'Genérico').toString(),
            'modelo': (map['modelo'] ?? 'S/M').toString(),
            'anio': map['anio'],
            'estado': (map['estado'] ?? 'disponible').toString(),
            'url_revision_tecnica': (map['url_revision_tecnica'] ?? '').toString(),
            'url_permiso_circulacion': (map['url_permiso_circulacion'] ?? '').toString(),
            'url_seguro_soap': (map['url_seguro_soap'] ?? '').toString(),
            'url_padron': (map['url_padron'] ?? '').toString(),
            'disponible': estadoStr == 'disponible' || estadoStr == 'activo',
          };
        }).toList();

        setState(() {
          _datosOriginales = datosMapeados;
          _isLoading = false;
        });
        _aplicarFiltros();
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

  String? _nullSiVacio(dynamic v) {
    final texto = (v ?? '').toString();
    return texto.isEmpty ? null : texto;
  }

  Future<void> _abrirFormularioEdicion(CamionItem item) async {
    final anioRaw = item['anio'];
    final anio = anioRaw is int ? anioRaw : int.tryParse('$anioRaw') ?? DateTime.now().year;

    final camionExistente = Camion(
      id: item['id'],
      patente: item['patente'] as String,
      marca: item['marca'] as String,
      modelo: item['modelo'] as String,
      anio: anio,
      estado: (item['estado'] ?? 'disponible').toString(),
      urlRevisionTecnica: _nullSiVacio(item['url_revision_tecnica']),
      urlPermisoCirculacion: _nullSiVacio(item['url_permiso_circulacion']),
      urlSeguroSoap: _nullSiVacio(item['url_seguro_soap']),
      urlPadron: _nullSiVacio(item['url_padron']),
    );

    final actualizado = await Navigator.of(context).push<bool>(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => CamionModificarScreen(camion: camionExistente),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );

    if (actualizado == true) {
      _cargarCamionesDesdeSupabase();
    }
  }

  Future<void> _eliminarCamion(CamionItem camion) async {
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

  /// Combina el filtro de texto, el filtro de disponibilidad y el orden.
  void _aplicarFiltros() {
    final q = _searchController.text.toLowerCase().trim();

    final filtrados = _datosOriginales.where((c) {
      final patente = c['patente'].toString().toLowerCase();
      final marca = c['marca'].toString().toLowerCase();
      final modelo = c['modelo'].toString().toLowerCase();
      final coincideTexto = q.isEmpty || patente.contains(q) || marca.contains(q) || modelo.contains(q);
      if (!coincideTexto) return false;

      final bool esDisponible = c['disponible'] == true;
      final String estadoRaw = c['estado'].toString().toLowerCase().trim();

      if (_filtroDisponibilidad == 'disponible') return esDisponible;
      if (_filtroDisponibilidad == 'no_disponible') return !esDisponible || estadoRaw == 'asignado';
      return true;
    }).toList();

    filtrados.sort((a, b) {
      final pa = a['patente'].toString().toLowerCase();
      final pb = b['patente'].toString().toLowerCase();
      return _ordenAscendente ? pa.compareTo(pb) : pb.compareTo(pa);
    });

    setState(() {
      _paginaActual = 1;
      _camiones = filtrados;
    });
  }

  void _filtrarCamiones(String query) => _aplicarFiltros();

  Future<void> _abrirFiltros() async {
    final r = await mostrarFiltroDialog<String>(
      context,
      descripcion: 'Filtrar unidades por disponibilidad operativa:',
      actual: _filtroDisponibilidad,
      valorLimpiar: 'todos',
      opciones: const <OpcionFiltro<String>>[
        OpcionFiltro(
          valor: 'todos',
          titulo: 'Todos los vehículos',
          subtitulo: 'Muestra la flota completa sin restricción',
        ),
        OpcionFiltro(
          valor: 'disponible',
          titulo: 'Disponible',
          subtitulo: 'Camiones libres listos para asignar viaje',
          color: AppColors.success,
        ),
        OpcionFiltro(
          valor: 'no_disponible',
          titulo: 'No Disponible',
          subtitulo: 'Camiones actualmente asignados o en ruta',
          color: Color(0xFF991B1B),
        ),
      ],
    );
    if (r == null) return;
    _filtroDisponibilidad = r;
    _aplicarFiltros();
  }

  String? get _textoFiltroActivo {
    if (_filtroDisponibilidad == 'disponible') return 'Filtro: Disponible';
    if (_filtroDisponibilidad == 'no_disponible') return 'Filtro: No Disponible';
    return null;
  }

  void _verDetalle(CamionItem item) {
    final bool disp = item['disponible'] == true;
    String doc(String clave) => item[clave].toString().trim().isEmpty ? 'Pendiente' : 'Adjunto';

    mostrarDetalleDialog(
      context,
      icono: Icons.local_shipping_outlined,
      titulo: item['patente'].toString(),
      estado: EstadoBadge(
        texto: disp ? 'Disponible' : 'No disponible',
        tipo: disp ? EstadoTipo.ok : EstadoTipo.peligro,
      ),
      filas: [
        DetalleFila('Marca', item['marca'].toString()),
        DetalleFila('Modelo', item['modelo'].toString()),
        DetalleFila('Año', '${item['anio'] ?? '—'}'),
        DetalleFila('Revisión técnica', doc('url_revision_tecnica')),
        DetalleFila('Permiso circulación', doc('url_permiso_circulacion')),
        DetalleFila('Seguro SOAP', doc('url_seguro_soap')),
        DetalleFila('Padrón', doc('url_padron')),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool esPantallaPequena = MediaQuery.of(context).size.width < 750;
    final double paddingHorizontal = esPantallaPequena ? 16.0 : 32.0;

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: paddingHorizontal, vertical: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeroBanner(
            icon: Icons.local_shipping_outlined,
            watermarkIcon: Icons.local_shipping,
            title: 'Lista de Camiones',
            subtitle: 'Visualiza y gestiona los camiones de su flota, marcas y modelos.',
          ),
          const SizedBox(height: 20),

          ListToolbar(
            controller: _searchController,
            hint: 'Buscar por patente, marca o modelo...',
            onChanged: _filtrarCamiones,
            onFiltros: _abrirFiltros,
            filtroActivoTexto: _textoFiltroActivo,
            labelAgregar: 'Agregar Camión',
            onAgregar: () async {
              await Navigator.of(context).push(
                PageRouteBuilder(
                  pageBuilder: (_, __, ___) => const CamionFormScreen(),
                  transitionDuration: Duration.zero,
                  reverseTransitionDuration: Duration.zero,
                ),
              );
              _cargarCamionesDesdeSupabase();
            },
          ),
          const SizedBox(height: 28),

          ListSectionHeader(
            titulo: 'Inventario de Camiones',
            contador: '${_camiones.length} Total',
            orden: SortDropdown<bool>(
              valor: _ordenAscendente,
              opciones: const {true: 'Patente (A-Z)', false: 'Patente (Z-A)'},
              onChanged: (v) {
                _ordenAscendente = v;
                _aplicarFiltros();
              },
            ),
            acciones: [
              ListIconButton(
                icono: Icons.refresh,
                tooltip: 'Refrescar datos',
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
            const ListEmptyState(
              icono: Icons.no_crash_outlined,
              titulo: 'No se encontraron vehículos registrados',
              mensaje: 'No hay camiones en la base de datos o el criterio de búsqueda no arrojó resultados.',
            )
          else
            EntityGrid(
              itemCount: _camionesPaginados.length,
              anchoMinimo: 340,
              maxColumnas: 3,
              altoItem: 112,
              itemBuilder: (context, index) {
                final item = _camionesPaginados[index];
                final bool disp = item['disponible'] == true;
                return EntityListCard(
                  leading: const CardAvatar.icono(Icons.local_shipping_outlined),
                  titulo: item['patente'].toString(),
                  estado: EstadoBadge(
                    texto: disp ? 'Disponible' : 'No disponible',
                    tipo: disp ? EstadoTipo.ok : EstadoTipo.peligro,
                  ),
                  detalles: [
                    CardInfoLine(texto: item['marca'].toString(), destacado: true),
                    CardInfoLine(texto: item['modelo'].toString()),
                  ],
                  tooltipVer: 'Ver camión',
                  onVer: () => _verDetalle(item),
                  acciones: [
                    EntityCardAction(
                      label: 'Modificar Camión',
                      icono: Icons.edit_outlined,
                      onTap: () => _abrirFormularioEdicion(item),
                    ),
                    EntityCardAction(
                      label: 'Eliminar Camión',
                      icono: Icons.delete_outline,
                      destructiva: true,
                      onTap: () => _eliminarCamion(item),
                    ),
                  ],
                );
              },
            ),

          const SizedBox(height: 32),
          ListPaginator(
            pagina: _paginaActual,
            total: _totalPaginas,
            onChanged: (p) => setState(() => _paginaActual = p),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}