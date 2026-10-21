import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/trabajador.dart';
import '../../theme/app_colors.dart';
import 'trabajador_form_screen.dart';
import 'modificar/trabajador_modificar_screen.dart';
import '../../utils/csv_exporter.dart';

class ListaTrabajadoresScreen extends StatefulWidget {
  const ListaTrabajadoresScreen({super.key});

  @override
  State<ListaTrabajadoresScreen> createState() => _ListaTrabajadoresScreenState();
}

class _ListaTrabajadoresScreenState extends State<ListaTrabajadoresScreen> {
  final int _itemsPorPagina = 10;
  int _paginaActual = 1;

  List<Map<String, dynamic>> _datosOriginales = [];
  List<Map<String, dynamic>> _trabajadores = [];
  bool _isLoading = true;
  int _criterioOrden = 0;
  final TextEditingController _searchController = TextEditingController();

  int get _totalPaginas {
    if (_trabajadores.isEmpty) return 1;
    return (_trabajadores.length / _itemsPorPagina).ceil();
  }

  List<Map<String, dynamic>> get _trabajadoresPaginados {
    if (_trabajadores.isEmpty) return [];
    final int inicio = (_paginaActual - 1) * _itemsPorPagina;
    if (inicio >= _trabajadores.length) return [];
    final int fin = (inicio + _itemsPorPagina > _trabajadores.length)
        ? _trabajadores.length
        : inicio + _itemsPorPagina;
    return _trabajadores.sublist(inicio, fin);
  }

  @override
  void initState() {
    super.initState();
    _cargarTrabajadoresDesdeSupabase();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _cargarTrabajadoresDesdeSupabase() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final data = await Supabase.instance.client
          .from('conductores')
          .select('*');

      if (mounted) {
        final List<dynamic> listaRemota = data as List<dynamic>? ?? [];
        final List<Map<String, dynamic>> datosMapeados = listaRemota.map((t) {
          final map = t as Map<String, dynamic>;
          final nombre = (map['nombre_completo'] ?? 'Sin Nombre').toString();

          String iniciales = 'TR';
          final partes = nombre.trim().split(' ');
          if (partes.length >= 2 && partes[0].isNotEmpty && partes[1].isNotEmpty) {
            iniciales = '${partes[0][0]}${partes[1][0]}'.toUpperCase();
          } else if (partes.isNotEmpty && partes[0].isNotEmpty) {
            iniciales = partes[0][0].toUpperCase();
          }

          return {
            'rut': (map['rut'] ?? '').toString(),
            'nombre_completo': nombre,
            'fecha_nacimiento': (map['fecha_nacimiento'] ?? '').toString(),
            'email': (map['email'] ?? 'sin_correo@tcontreras.cl').toString(),
            'telefono': (map['telefono'] ?? '+56 9 --------').toString(),
            'auth_id': (map['auth_id'] ?? '').toString(),
            'url_cedula_identidad': (map['url_cedula_identidad'] ?? '').toString(),
            'url_licencia_conducir': (map['url_licencia_conducir'] ?? '').toString(),
            'creado_en': (map['creado_en'] ?? '').toString(),
            'nombre': nombre,
            'iniciales': iniciales,
            'estado': 'Activo',
            'ultimo_viaje': 'Santiago - Antofagasta',
          };
        }).toList();

        setState(() {
          _datosOriginales = datosMapeados;
          _trabajadores = List<Map<String, dynamic>>.from(_datosOriginales);
          _isLoading = false;
        });
        _aplicarOrden();
      }
    } catch (e) {
      debugPrint('Error cargando trabajadores desde Supabase: $e');
      if (mounted) {
        setState(() {
          _datosOriginales = [];
          _trabajadores = [];
          _isLoading = false;
        });
      }
    }
  }

  String? _nullSiVacio(dynamic v) {
    final texto = (v ?? '').toString();
    return texto.isEmpty ? null : texto;
  }

  Future<void> _abrirFormularioEdicion(Map<String, dynamic> item) async {
    final fechaTexto = (item['fecha_nacimiento'] ?? '').toString();
    final fechaNacimiento = fechaTexto.isEmpty ? null : DateTime.tryParse(fechaTexto);

    final trabajadorExistente = Trabajador(
      rut: item['rut'] as String,
      nombreCompleto: item['nombre_completo'] as String,
      fechaNacimiento: fechaNacimiento,
      correo: item['email'] as String,
      telefono: item['telefono'] as String,
      authId: _nullSiVacio(item['auth_id']),
      urlCedulaIdentidad: _nullSiVacio(item['url_cedula_identidad']),
      urlLicenciaConducir: _nullSiVacio(item['url_licencia_conducir']),
    );

    final actualizado = await Navigator.of(context).push<bool>(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => TrabajadorModificarScreen(trabajador: trabajadorExistente),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );

    if (actualizado == true) {
      _cargarTrabajadoresDesdeSupabase();
    }
  }

  Future<void> _eliminarTrabajador(Map<String, dynamic> trabajador) async {
    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 24),
            SizedBox(width: 8),
            Text('Eliminar Trabajador', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          ],
        ),
        content: Text(
          '¿Estás seguro de que deseas eliminar a "${trabajador['nombre']}" (RUT: ${trabajador['rut']})?\nEsta acción no se puede deshacer.',
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
      final resultado = await Supabase.instance.client
          .from('conductores')
          .delete()
          .eq('rut', trabajador['rut'])
          .select();

      if (mounted) {
        setState(() {
          _datosOriginales.removeWhere((t) => t['rut'] == trabajador['rut']);
          _trabajadores.removeWhere((t) => t['rut'] == trabajador['rut']);
          if (_paginaActual > _totalPaginas) {
            _paginaActual = _totalPaginas;
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(resultado.isNotEmpty
                ? 'Trabajador ${trabajador['nombre']} eliminado de Supabase.'
                : 'Trabajador removido de la vista.'),
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

  void _filtrarTrabajadores(String query) {
    setState(() {
      _paginaActual = 1;
      if (query.isEmpty) {
        _trabajadores = List.from(_datosOriginales);
      } else {
        _trabajadores = _datosOriginales.where((t) {
          final nombre = t['nombre'].toString().toLowerCase();
          return nombre.contains(query.toLowerCase().trim());
        }).toList();
      }
      _aplicarOrden();
    });
  }

  void _aplicarOrden() {
    if (_criterioOrden == 1) {
      _trabajadores.sort((a, b) => a['nombre'].toString().compareTo(b['nombre'].toString()));
    } else {
      final query = _searchController.text.toLowerCase().trim();
      _trabajadores = _datosOriginales.where((t) {
        return query.isEmpty || t['nombre'].toString().toLowerCase().contains(query);
      }).toList();
    }
  }

  int get _totalPersonal => _datosOriginales.length;
  int get _conductoresActivos => _datosOriginales.where((t) => t['estado'].toString().toLowerCase() == 'activo').length;
  int get _enRutaActual => _datosOriginales.where((t) => t['estado'].toString().toLowerCase() == 'en ruta').length;

  @override
  Widget build(BuildContext context) {
    final double anchoPantalla = MediaQuery.of(context).size.width;
    final bool esPantallaPequena = anchoPantalla < 750;
    final double paddingHorizontal = esPantallaPequena ? 16.0 : 32.0;

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: paddingHorizontal, vertical: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Cabecera y Botones de Acción Superiores
          LayoutBuilder(
            builder: (context, constraints) {
              final bool esPantallaAncha = constraints.maxWidth > 750;

              final Widget bloqueTitulos = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.people_alt_outlined, size: 14, color: AppColors.textSecondary),
                      SizedBox(width: 6),
                      Text('RECURSOS HUMANOS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 0.8)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text('Lista de Trabajadores', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                ],
              );

              final Widget bloqueBotones = Wrap(
                spacing: 12,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: _exportarCsvTrabajadores,
                    icon: const Icon(Icons.download_outlined, size: 16, color: AppColors.textPrimary),
                    label: const Text('Exportar CSV', style: TextStyle(fontSize: 13, color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: AppColors.border),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () async {
                      await Navigator.of(context).push(
                        PageRouteBuilder(
                          pageBuilder: (_, __, ___) => const TrabajadorFormScreen(),
                          transitionDuration: Duration.zero,
                          reverseTransitionDuration: Duration.zero,
                        ),
                      );
                      _cargarTrabajadoresDesdeSupabase();
                    },
                    icon: const Icon(Icons.person_add_alt_1, size: 16, color: Colors.white),
                    label: const Text('AGREGAR TRABAJADOR', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
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
                  children: [bloqueTitulos, bloqueBotones],
                );
              } else {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [bloqueTitulos, const SizedBox(height: 16), bloqueBotones],
                );
              }
            },
          ),
          const SizedBox(height: 24),

          // 2. Tarjetas de Métricas Responsivas
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
                      label: 'TOTAL PERSONAL',
                      valor: '$_totalPersonal',
                      icono: Icons.people_outline,
                      colorIcono: const Color(0xFF0284C7),
                      colorFondo: const Color(0xFFE0F2FE),
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _buildTarjetaMetrica(
                      label: 'CONDUCTORES ACTIVOS',
                      valor: '$_conductoresActivos',
                      icono: Icons.verified_outlined,
                      colorIcono: AppColors.success,
                      colorFondo: AppColors.successBg,
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _buildTarjetaMetrica(
                      label: 'EN RUTA ACTUAL',
                      valor: '$_enRutaActual',
                      icono: Icons.location_on_outlined,
                      colorIcono: const Color(0xFFD97706),
                      colorFondo: const Color(0xFFFEF3C7),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),

          // 3. Buscador, Filtros y Ordenamiento Responsivo
          _buildZonaBuscadorYFiltros(esPantallaPequena),
          const SizedBox(height: 20),

          // 4. Tabla de Trabajadores: Diseño Original con soporte responsivo
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 40.0),
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          else if (_trabajadores.isEmpty)
            _buildCartelSinRegistros()
          else
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: esPantallaPequena
                  // EN MÓVIL: Scroll lateral con filas fijas de 800px para evitar aplastamientos
                  ? SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: 800,
                        child: Column(
                          children: [
                            _buildEncabezadoOriginal(),
                            ..._trabajadoresPaginados.map((item) => Column(
                                  children: [
                                    _buildFilaOriginal(item),
                                    const Divider(height: 1, color: Color(0xFFF1F5F9)),
                                  ],
                                )),
                          ],
                        ),
                      ),
                    )
                  // EN PC: Tu diseño original exacto con ListView.separated al 100%
                  : Column(
                      children: [
                        _buildEncabezadoOriginal(),
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _trabajadoresPaginados.length,
                          separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                          itemBuilder: (context, index) {
                            return _buildFilaOriginal(_trabajadoresPaginados[index]);
                          },
                        ),
                      ],
                    ),
            ),
          const SizedBox(height: 16),

          // 5. Paginación y Contador Responsivo
          _buildPaginacionResponsiva(esPantallaPequena),

          const SizedBox(height: 48),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 16),

          // 6. Footer Estandarizado Responsivo
          _buildFooterResponsivo(esPantallaPequena),
        ],
      ),
    );
  }

  // Encabezado original con su borde y padding original
  Widget _buildEncabezadoOriginal() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: const [
          Expanded(flex: 3, child: Text('Trabajador', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
          Expanded(flex: 3, child: Text('Contacto', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
          Expanded(flex: 2, child: Text('Estado', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
          Expanded(flex: 2, child: Text('RUT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
          Expanded(flex: 3, child: Text('Último Viaje', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
          SizedBox(width: 40),
        ],
      ),
    );
  }

  // Fila original exacta de tu diseño
  Widget _buildFilaOriginal(Map<String, dynamic> item) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      child: Row(
        children: [
          // Avatar y Nombre
          Expanded(
            flex: 3,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppColors.surfaceMuted,
                  child: Text(item['iniciales'], style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF334155))),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item['nombre'],
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                ),
              ],
            ),
          ),
          // Contacto
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    const Icon(Icons.call, size: 12, color: Color(0xFFE67E22)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        item['telefono'],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF334155)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    const Icon(Icons.mail_outline, size: 12, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        item['email'],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Estado
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: AppColors.successBg, borderRadius: BorderRadius.circular(12)),
                child: const Text('Activo', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.success)),
              ),
            ),
          ),
          // RUT
          Expanded(
            flex: 2,
            child: Text(item['rut'], style: const TextStyle(fontSize: 12, color: Color(0xFF334155), fontWeight: FontWeight.w500)),
          ),
          // Último Viaje
          Expanded(
            flex: 3,
            child: Text(
              item['ultimo_viaje'],
              style: const TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          // Popup Menú de acciones
          SizedBox(
            width: 40,
            child: PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 18, color: Color(0xFF94A3B8)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              onSelected: (accion) {
                if (accion == 'modificar') _abrirFormularioEdicion(item);
                if (accion == 'eliminar') _eliminarTrabajador(item);
              },
              itemBuilder: (ctx) => [
                PopupMenuItem(
                  value: 'modificar',
                  child: Row(
                    children: const [
                      Icon(Icons.edit_outlined, size: 16, color: AppColors.primary),
                      SizedBox(width: 8),
                      Text('Modificar Trabajador', style: TextStyle(fontSize: 12.5, color: AppColors.primary, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'eliminar',
                  child: Row(
                    children: const [
                      Icon(Icons.delete_outline, size: 16, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Eliminar Trabajador', style: TextStyle(fontSize: 12.5, color: Colors.red, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Zona de búsqueda con filtro a la derecha en celular y botón de recarga
  Widget _buildZonaBuscadorYFiltros(bool esPantallaPequena) {
    final Widget campoInput = Container(
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: _filtrarTrabajadores,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Buscar por nombre o apellido...',
          hintStyle: const TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
          prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF94A3B8)),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 16, color: Color(0xFF94A3B8)),
                  onPressed: () {
                    _searchController.clear();
                    _filtrarTrabajadores('');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 9),
        ),
      ),
    );

    final Widget botonFiltrosIcono = OutlinedButton(
      onPressed: () {},
      style: OutlinedButton.styleFrom(
        backgroundColor: AppColors.surfaceMuted,
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      child: const Icon(Icons.tune, size: 18, color: Color(0xFF475569)),
    );

    final Widget botonFiltrosTexto = OutlinedButton.icon(
      onPressed: () {},
      icon: const Icon(Icons.tune, size: 16, color: Color(0xFF475569)),
      label: const Text('Filtros Avanzados', style: TextStyle(fontSize: 12, color: Color(0xFF475569), fontWeight: FontWeight.w600)),
      style: OutlinedButton.styleFrom(
        backgroundColor: AppColors.surfaceMuted,
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );

    final Widget botonRecargar = IconButton(
      tooltip: 'Refrescar trabajadores',
      icon: const Icon(Icons.refresh, size: 20, color: AppColors.textSecondary),
      onPressed: _cargarTrabajadoresDesdeSupabase,
    );

    final Widget selectorOrden = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Ordenar por:', style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
        const SizedBox(width: 8),
        _buildBotonOrden('Recientes', 0),
        const SizedBox(width: 6),
        _buildBotonOrden('Nombre (A-Z)', 1),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: esPantallaPequena
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: campoInput),
                    const SizedBox(width: 8),
                    botonFiltrosIcono,
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    selectorOrden,
                    botonRecargar,
                  ],
                ),
              ],
            )
          : Row(
              children: [
                Expanded(child: campoInput),
                const SizedBox(width: 12),
                botonFiltrosTexto,
                const SizedBox(width: 16),
                selectorOrden,
                const SizedBox(width: 8),
                botonRecargar,
              ],
            ),
    );
  }

  Widget _buildPaginacionResponsiva(bool esPantallaPequena) {
    final Widget textoConteo = RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        children: [
          const TextSpan(text: 'Mostrando '),
          TextSpan(text: '${_trabajadoresPaginados.length}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const TextSpan(text: ' de '),
          TextSpan(text: '${_trabajadores.length}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const TextSpan(text: ' trabajadores registrados'),
        ],
      ),
    );

    final Widget botonesPaginador = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildBotonNumeroPagina(1, habilitado: 1 <= _totalPaginas),
        const SizedBox(width: 4),
        _buildBotonNumeroPagina(2, habilitado: 2 <= _totalPaginas),
        const SizedBox(width: 4),
        _buildBotonNumeroPagina(3, habilitado: 3 <= _totalPaginas),
      ],
    );

    if (!esPantallaPequena) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [textoConteo, botonesPaginador],
      );
    }

    return Column(
      children: [
        Center(child: textoConteo),
        const SizedBox(height: 12),
        Center(child: botonesPaginador),
      ],
    );
  }

  Widget _buildFooterResponsivo(bool esPantallaPequena) {
    final enlaces = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildFooterLink('Soporte Técnico'),
        const SizedBox(width: 14),
        _buildFooterLink('Privacidad'),
      ],
    );

    const servidorOperativo = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, color: Colors.green, size: 7),
        SizedBox(width: 5),
        Text('SERVIDOR OPERATIVO', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green)),
      ],
    );

    if (!esPantallaPequena) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('© 2026 Transportes Contreras Enterprise • Fleet System v4.2.1', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
          Row(
            children: [
              enlaces,
              const SizedBox(width: 16),
              servidorOperativo,
            ],
          ),
        ],
      );
    }

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            enlaces,
            const SizedBox(width: 16),
            servidorOperativo,
          ],
        ),
        const SizedBox(height: 10),
        const Text(
          '© 2026 Transportes Contreras Enterprise • Fleet System v4.2.1',
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
            child: const Icon(Icons.person_off_outlined, size: 40, color: Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 16),
          const Text('No se encontraron trabajadores registrados', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          const Text('No hay personal en la base de datos o el criterio de búsqueda no arrojó resultados.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildTarjetaMetrica({
    required String label,
    required String valor,
    required IconData icono,
    required Color colorIcono,
    required Color colorFondo,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 0.6)),
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: colorFondo, borderRadius: BorderRadius.circular(10)),
                child: Icon(icono, size: 20, color: colorIcono),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(valor, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppColors.textPrimary, height: 1.1)),
        ],
      ),
    );
  }

  Widget _buildBotonOrden(String texto, int index) {
    final bool activo = _criterioOrden == index;
    return InkWell(
      onTap: () {
        setState(() {
          _criterioOrden = index;
          _aplicarOrden();
        });
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: activo ? const Color(0xFFE2E8F0) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          texto,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: activo ? FontWeight.bold : FontWeight.normal,
            color: activo ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
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
          color: activo ? AppColors.primary : (habilitado ? Colors.white : const Color(0xFFF1F5F9)),
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
      child: Text(
        texto,
        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
      ),
    );
  }

  void _exportarCsvTrabajadores() {
    if (_trabajadores.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay trabajadores para exportar.')),
      );
      return;
    }

    final encabezados = [
      'RUT',
      'Nombre Completo',
      'Fecha Nacimiento',
      'Correo Electrónico',
      'Teléfono',
      'Auth ID',
      'Doc. Cédula Identidad',
      'Doc. Licencia Conducir',
      'Fecha Creación',
      'Estado',
      'Último Viaje',
    ];

    final filas = _trabajadores.map((t) {
      return [
        t['rut'] ?? '',
        t['nombre_completo'] ?? '',
        t['fecha_nacimiento'] ?? '',
        t['email'] ?? '',
        t['telefono'] ?? '',
        t['auth_id'] ?? '',
        t['url_cedula_identidad'] ?? '',
        t['url_licencia_conducir'] ?? '',
        t['creado_en'] ?? '',
        t['estado'] ?? '',
        t['ultimo_viaje'] ?? '',
      ];
    }).toList();

    CsvExporter.descargarCsv(
      nombreArchivo: 'reporte_conductores_completo',
      encabezados: encabezados,
      filas: filas,
    );
  }
}