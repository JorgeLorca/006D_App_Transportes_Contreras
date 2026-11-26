import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/consignatario.dart';
import '../../theme/app_colors.dart';
import '../../utils/csv_exporter.dart';
import '../../widgets/page_hero_banner.dart';
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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _cargarConsignatariosDesdeSupabase() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final data = await Supabase.instance.client
          .from('consignatarios')
          .select('*, comunas(nombre), regiones(nombre)');

      if (mounted) {
        final List<dynamic> listaRemota = data as List<dynamic>? ?? [];
        final List<Map<String, dynamic>> datosMapeados = listaRemota.map((c) {
          final map = c as Map<String, dynamic>;
          final nombreEmpresa = (map['nombre_empresa'] ?? map['nombre'] ?? 'Sin Nombre').toString();
          final calle = (map['direccion'] ?? '').toString().trim();

          final comunaData = map['comunas'] as Map<String, dynamic>?;
          final regionData = map['regiones'] as Map<String, dynamic>?;

          final nombreComuna = (comunaData?['nombre'] ?? '').toString().trim();
          final nombreRegion = (regionData?['nombre'] ?? '').toString().trim();

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

  void _setOrden(bool ascendente) {
    setState(() {
      _ordenAscendente = ascendente;
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
    final double anchoPantalla = MediaQuery.of(context).size.width;
    final bool esPantallaPequena = anchoPantalla < 750;
    final double paddingHorizontal = esPantallaPequena ? 16.0 : 24.0;

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: paddingHorizontal, vertical: 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Banner de cabecera
          PageHeroBanner(
            icon: Icons.inventory_2_outlined,
            watermarkIcon: Icons.local_shipping_outlined,
            title: 'Lista de Consignatarios',
            subtitle:
                'Visualiza y gestiona las empresas receptoras de mercancía para la emisión de guías de despacho y manifiestos.',
            actions: [_buildBotonCsv(), _buildBotonAgregar()],
          ),
          const SizedBox(height: 20),

          // 2. Buscador
          _buildBuscadorResponsivo(esPantallaPequena),
          const SizedBox(height: 24),

          // 3. Directorio + Ordenar
          _buildCabeceraDirectorio(esPantallaPequena),
          const SizedBox(height: 14),

          // 4. Grilla
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
                    mainAxisSpacing: 14,
                    mainAxisExtent: 82,
                  ),
                  itemBuilder: (context, index) => _buildTarjeta(_consignatariosPaginados[index]),
                );
              },
            ),
          const SizedBox(height: 24),

          // 5. Paginador
          if (!_isLoading && _consignatarios.isNotEmpty) Center(child: _buildPaginador()),

          const SizedBox(height: 40),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 16),

          // 6. Footer
          _buildFooterResponsivo(esPantallaPequena),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- botones

  Widget _buildBotonCsv() {
    return ElevatedButton.icon(
      onPressed: _exportarCsvConsignatarios,
      icon: const Icon(Icons.download_outlined, size: 18, color: AppColors.textPrimary),
      label: const Text(
        'Exportar CSV',
        style: TextStyle(fontSize: 13, color: AppColors.textPrimary, fontWeight: FontWeight.w600),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      ),
    );
  }

  Widget _buildBotonAgregar() {
    return ElevatedButton.icon(
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
      icon: const Icon(Icons.add, size: 18, color: Colors.white),
      label: const Text(
        'Agregar Consignatario',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
    );
  }

  // ------------------------------------------------------------ tarjeta

  Widget _buildTarjeta(Map<String, dynamic> item) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: sombraTarjeta,
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(color: Color(0xFFEEF1F7), shape: BoxShape.circle),
            child: const Icon(Icons.apartment_rounded, color: Color(0xFF334155), size: 24),
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
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    const Icon(Icons.place_outlined, size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        item['direccion'],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 20, color: Color(0xFF64748B)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            onSelected: (accion) {
              if (accion == 'modificar') _abrirFormularioEdicion(item);
              if (accion == 'eliminar') _eliminarConsignatario(item);
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(
                value: 'modificar',
                child: Row(
                  children: [
                    Icon(Icons.edit_outlined, size: 16, color: AppColors.primary),
                    SizedBox(width: 8),
                    Text('Modificar Consignatario',
                        style: TextStyle(fontSize: 12.5, color: AppColors.primary, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'eliminar',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, size: 16, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Eliminar Consignatario',
                        style: TextStyle(fontSize: 12.5, color: Colors.red, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------- buscador

  Widget _buildBuscadorResponsivo(bool esPantallaPequena) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: sombraTarjeta,
      ),
      child: TextField(
        controller: _searchController,
        onChanged: _filtrarConsignatarios,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: esPantallaPequena ? 'Buscar consignatario...' : 'Buscar consignatario por nombre o dirección...',
          hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
          prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xFF475569)),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18, color: Color(0xFF94A3B8)),
                  onPressed: () {
                    _searchController.clear();
                    _filtrarConsignatarios('');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  // ------------------------------------------------ directorio + orden

  Widget _buildCabeceraDirectorio(bool esPantallaPequena) {
    final Widget bloqueTitulo = SeccionTitulo(
      'Directorio de Recepción',
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(10)),
        child: Text(
          '${_consignatarios.length} Total',
          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF475569)),
        ),
      ),
    );

    final Widget bloqueOrden = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Ordenar:', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        const SizedBox(width: 8),
        PopupMenuButton<bool>(
          tooltip: 'Ordenar',
          onSelected: _setOrden,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          itemBuilder: (_) => const [
            PopupMenuItem(value: true, child: Text('A-Z', style: TextStyle(fontSize: 13))),
            PopupMenuItem(value: false, child: Text('Z-A', style: TextStyle(fontSize: 13))),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: sombraTarjeta,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _ordenAscendente ? 'A-Z' : 'Z-A',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
                const SizedBox(width: 4),
                Icon(
                  _ordenAscendente ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 13,
                  color: AppColors.textPrimary,
                ),
                const Icon(Icons.keyboard_arrow_down, size: 18, color: AppColors.textPrimary),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Material(
          color: Colors.white,
          shape: const CircleBorder(),
          elevation: 0,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: _cargarConsignatariosDesdeSupabase,
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.refresh, size: 18, color: AppColors.textPrimary),
            ),
          ),
        ),
      ],
    );

    if (!esPantallaPequena) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [bloqueTitulo, bloqueOrden],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        bloqueTitulo,
        const SizedBox(height: 10),
        bloqueOrden,
      ],
    );
  }

  // ---------------------------------------------------------- paginador

  Widget _buildPaginador() {
    final int total = _totalPaginas;
    // Ventana de hasta 3 páginas alrededor de la actual.
    final int inicio = (_paginaActual - 1).clamp(1, total > 3 ? total - 2 : 1).toInt();
    final int fin = (inicio + 2) > total ? total : inicio + 2;
    final bool hayMasAdelante = fin < total;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildBotonPaginadorIcono(
          Icons.chevron_left,
          habilitado: _paginaActual > 1,
          onTap: () => setState(() => _paginaActual--),
        ),
        const SizedBox(width: 6),
        for (int p = inicio; p <= fin; p++) ...[
          _buildBotonNumeroPagina(p),
          const SizedBox(width: 6),
        ],
        if (hayMasAdelante) ...[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4.0),
            child: Text('...', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          const SizedBox(width: 6),
        ],
        _buildBotonPaginadorIcono(
          Icons.chevron_right,
          habilitado: _paginaActual < total,
          onTap: () => setState(() => _paginaActual++),
        ),
      ],
    );
  }

  Widget _buildBotonNumeroPagina(int pagina) {
    final bool activo = _paginaActual == pagina;
    return InkWell(
      onTap: () => setState(() => _paginaActual = pagina),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: activo ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: activo ? null : sombraTarjeta,
        ),
        child: Text(
          '$pagina',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: activo ? Colors.white : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildBotonPaginadorIcono(IconData icon, {required bool habilitado, required VoidCallback onTap}) {
    return InkWell(
      onTap: habilitado ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: sombraTarjeta,
        ),
        child: Icon(icon, size: 18, color: habilitado ? AppColors.textPrimary : const Color(0xFFCBD5E1)),
      ),
    );
  }

  // Footer Responsivo
  Widget _buildFooterResponsivo(bool esPantallaPequena) {
    final enlaces = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildFooterLink(esPantallaPequena ? 'Términos de Servicio' : 'Términos de Servicio'),
        const SizedBox(width: 12),
        _buildFooterLink(esPantallaPequena ? 'Soporte' : 'Soporte Operacional'),
      ],
    );

    final servidorSeguro = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.circle, color: Color(0xFF16A34A), size: 6),
          SizedBox(width: 5),
          Text(
            'SERVIDORES SEGUROS',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF16A34A)),
          ),
        ],
      ),
    );

    if (!esPantallaPequena) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            '© 2026 Transportes Contreras Enterprise. Sistema Centralizado de Logística v2.4.1',
            style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
          ),
          Row(
            children: [
              enlaces,
              const SizedBox(width: 16),
              servidorSeguro,
            ],
          ),
        ],
      );
    }

    return Column(
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            enlaces,
            servidorSeguro,
          ],
        ),
        const SizedBox(height: 10),
        const Text(
          '© 2026 Transportes Contreras Enterprise. Sistema Centralizado de Logística v2.4.1',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8)),
        ),
      ],
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

  Widget _buildFooterLink(String texto) {
    return InkWell(
      onTap: () {},
      child: Text(texto, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
    );
  }
}