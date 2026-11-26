import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/cliente.dart';
import '../../theme/app_colors.dart';
import 'cliente_form_screen.dart';
import 'modificar/cliente_modificar_screen.dart';
import '../../utils/csv_exporter.dart';
import '../../widgets/page_hero_banner.dart';

typedef ClienteItem = Map<String, dynamic>;

class ListaClientesScreen extends StatefulWidget {
  const ListaClientesScreen({super.key});

  @override
  State<ListaClientesScreen> createState() => _ListaClientesScreenState();
}

class _ListaClientesScreenState extends State<ListaClientesScreen> {
  final int _itemsPorPagina = 9;
  int _paginaActual = 1;
  bool _ordenAscendente = true;

  final TextEditingController _searchController = TextEditingController();
  List<ClienteItem> _datosOriginales = [];
  List<ClienteItem> _clientes = [];
  bool _isLoading = true;

  int get _totalPaginas {
    if (_clientes.isEmpty) return 1;
    return (_clientes.length / _itemsPorPagina).ceil();
  }

  List<ClienteItem> get _clientesPaginados {
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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _cargarClientesDesdeSupabase() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final supabase = Supabase.instance.client;

      // 1. Obtener clientes
      final List<dynamic> listaRemota = await supabase.from('clientes').select('*');

      // 2. Obtener comunas y regiones directamente por 'id, nombre'
      final Map<String, String> mapComunas = {};
      try {
        final List<dynamic> listaComunas = await supabase.from('comunas').select('id, nombre');
        for (final com in listaComunas) {
          final id = (com['id'] ?? '').toString().toLowerCase().trim();
          final nombre = (com['nombre'] ?? '').toString().trim();
          if (id.isNotEmpty && nombre.isNotEmpty) {
            mapComunas[id] = nombre;
          }
        }
      } catch (e) {
        debugPrint('Error cargando comunas: $e');
      }

      final Map<String, String> mapRegiones = {};
      try {
        final List<dynamic> listaRegiones = await supabase.from('regiones').select('id, nombre');
        for (final reg in listaRegiones) {
          final id = (reg['id'] ?? '').toString().toLowerCase().trim();
          final nombre = (reg['nombre'] ?? '').toString().trim();
          if (id.isNotEmpty && nombre.isNotEmpty) {
            mapRegiones[id] = nombre;
          }
        }
      } catch (e) {
        debugPrint('Error cargando regiones: $e');
      }

      if (mounted) {
        final List<ClienteItem> datosMapeados = listaRemota.map((c) {
          final map = c as ClienteItem;
          final nombre = (map['nombre_empresa'] ?? 'Empresa Registrada').toString();

          String iniciales = 'CL';
          final partes = nombre.trim().split(' ');
          if (partes.length >= 2 && partes[0].isNotEmpty && partes[1].isNotEmpty) {
            iniciales = '${partes[0][0]}${partes[1][0]}'.toUpperCase();
          } else if (partes.isNotEmpty && partes[0].isNotEmpty) {
            iniciales = partes[0][0].toUpperCase();
          }

          final String dirBase = (map['direccion'] ?? '').toString().trim();
          final String comunaIdRaw = (map['comuna_id'] ?? '').toString().trim();
          final String regionIdRaw = (map['region_id'] ?? '').toString().trim();

          final String nombreComuna = mapComunas[comunaIdRaw.toLowerCase()] ?? '';
          final String nombreRegion = mapRegiones[regionIdRaw.toLowerCase()] ?? '';

          final partesUbicacion = <String>[
            if (dirBase.isNotEmpty) dirBase,
            if (nombreComuna.isNotEmpty) nombreComuna,
            if (nombreRegion.isNotEmpty) nombreRegion,
          ];
          final String direccionCompleta = partesUbicacion.isNotEmpty
              ? partesUbicacion.join(', ')
              : 'Sin dirección registrada';

          return <String, dynamic>{
            'id': (map['id'] ?? '').toString(),
            'nombre_empresa': nombre,
            'nombre_contacto': (map['nombre_contacto'] ?? '').toString(),
            'telefono': (map['telefono'] ?? '').toString(),
            'direccion': dirBase,
            'valor_viaje_camion': map['valor_viaje_camion'] ?? 0,
            'tarifa_nocturna_camion': map['tarifa_nocturna_camion'] ?? 0,
            'valor_peoneta_camion': map['valor_peoneta_camion'] ?? 0,
            'valor_viaje_rampla': map['valor_viaje_rampla'] ?? 0,
            'tarifa_nocturna_rampla': map['tarifa_nocturna_rampla'] ?? 0,
            'valor_peoneta_rampla': map['valor_peoneta_rampla'] ?? 0,
            'creado_en': (map['creado_en'] ?? '').toString(),
            'region_id': regionIdRaw,
            'comuna_id': comunaIdRaw,
            'nombre': nombre,
            'iniciales': iniciales,
            'contacto': (map['nombre_contacto'] ?? '').toString(),
            'ubicacion': direccionCompleta,
            'hace': _haceTiempo((map['creado_en'] ?? '').toString()),
            'estado': 'ACTIVO',
          };
        }).toList();

        _ordenarLista(datosMapeados);

        setState(() {
          _datosOriginales = datosMapeados;
          _clientes = List<ClienteItem>.from(_datosOriginales);
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

  void _ordenarLista(List<ClienteItem> lista) {
    lista.sort((a, b) {
      final nombreA = a['nombre'].toString().toLowerCase();
      final nombreB = b['nombre'].toString().toLowerCase();
      return _ordenAscendente ? nombreA.compareTo(nombreB) : nombreB.compareTo(nombreA);
    });
  }

  void _setOrden(bool ascendente) {
    setState(() {
      _ordenAscendente = ascendente;
      _ordenarLista(_datosOriginales);
      _ordenarLista(_clientes);
      _paginaActual = 1;
    });
  }

  /// Texto relativo ("Hace 3 días") a partir de una fecha ISO. Vacío si no se puede leer.
  String _haceTiempo(String iso) {
    final f = DateTime.tryParse(iso);
    if (f == null) return '';
    final dias = DateTime.now().difference(f).inDays;
    if (dias < 1) return 'Hoy';
    if (dias < 7) return 'Hace $dias ${dias == 1 ? 'día' : 'días'}';
    if (dias < 30) {
      final s = dias ~/ 7;
      return 'Hace $s ${s == 1 ? 'semana' : 'semanas'}';
    }
    if (dias < 365) {
      final m = dias ~/ 30;
      return 'Hace $m ${m == 1 ? 'mes' : 'meses'}';
    }
    final a = dias ~/ 365;
    return 'Hace $a ${a == 1 ? 'año' : 'años'}';
  }

  String _formatearClp(dynamic valor) {
    final num numero = valor is num ? valor : (num.tryParse(valor?.toString() ?? '0') ?? 0);
    final int entero = numero.round();
    final String str = entero.abs().toString();
    final StringBuffer buffer = StringBuffer();

    for (int i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) {
        buffer.write('.');
      }
      buffer.write(str[i]);
    }

    return '${entero < 0 ? '-' : ''}\$${buffer.toString()}';
  }

  void _abrirModalFichaCliente(ClienteItem item) {
    final String direccionMostrar = (item['ubicacion'] ?? item['direccion'] ?? 'Sin dirección').toString();

    showDialog(
      context: context,
      builder: (ctx) {
        final screenWidth = MediaQuery.of(ctx).size.width;
        final isCompact = screenWidth < 600;

        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: Colors.white,
          insetPadding: EdgeInsets.symmetric(
            horizontal: isCompact ? 14 : 24,
            vertical: 24,
          ),
          child: Container(
            width: 600,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.88,
            ),
            padding: EdgeInsets.all(isCompact ? 18 : 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Cabecera con cierre superior
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundColor: const Color(0xFF334155),
                            child: Text(
                              item['iniciales'] ?? 'CL',
                              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item['nombre_empresa'] ?? 'Cliente',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  'Ficha Corporativa y Tarifario',
                                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppColors.textSecondary, size: 20),
                      tooltip: 'Cerrar ficha',
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1, color: AppColors.border),
                const SizedBox(height: 16),

                // Contenido con scroll
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Sección 1: Datos Generales
                        const Text(
                          'INFORMACIÓN GENERAL',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary, letterSpacing: 0.6),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Column(
                            children: [
                              _buildFilaDetalleFicha(
                                icono: Icons.business_outlined,
                                etiqueta: 'Nombre Empresa',
                                valor: (item['nombre_empresa'] ?? '—').toString(),
                              ),
                              const Divider(height: 18, color: AppColors.border),
                              _buildFilaDetalleFicha(
                                icono: Icons.person_outline,
                                etiqueta: 'Nombre Contacto',
                                valor: (item['nombre_contacto'] ?? '—').toString(),
                              ),
                              const Divider(height: 18, color: AppColors.border),
                              _buildFilaDetalleFicha(
                                icono: Icons.phone_outlined,
                                etiqueta: 'Teléfono',
                                valor: (item['telefono'] ?? '—').toString(),
                              ),
                              const Divider(height: 18, color: AppColors.border),
                              _buildFilaDetalleFicha(
                                icono: Icons.location_on_outlined,
                                etiqueta: 'Dirección',
                                valor: direccionMostrar,
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Sección 2: Tarifario Camión Simple
                        const Text(
                          'TARIFARIO CAMIÓN',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary, letterSpacing: 0.6),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Column(
                            children: [
                              _buildFilaTarifaFicha('Valor Viaje Camión', _formatearClp(item['valor_viaje_camion'])),
                              const Divider(height: 16, color: AppColors.border),
                              _buildFilaTarifaFicha('Tarifa Nocturna Camión', _formatearClp(item['tarifa_nocturna_camion'])),
                              const Divider(height: 16, color: AppColors.border),
                              _buildFilaTarifaFicha('Valor Peoneta Camión', _formatearClp(item['valor_peoneta_camion'])),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Sección 3: Tarifario Rampla
                        const Text(
                          'TARIFARIO RAMPLA',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary, letterSpacing: 0.6),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Column(
                            children: [
                              _buildFilaTarifaFicha('Valor Viaje Rampla', _formatearClp(item['valor_viaje_rampla'])),
                              const Divider(height: 16, color: AppColors.border),
                              _buildFilaTarifaFicha('Tarifa Nocturna Rampla', _formatearClp(item['tarifa_nocturna_rampla'])),
                              const Divider(height: 16, color: AppColors.border),
                              _buildFilaTarifaFicha('Valor Peoneta Rampla', _formatearClp(item['valor_peoneta_rampla'])),
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
        );
      },
    );
  }

  Widget _buildFilaDetalleFicha({
    required IconData icono,
    required String etiqueta,
    required String valor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icono, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 10),
        SizedBox(
          width: 130,
          child: Text(
            etiqueta,
            style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
          ),
        ),
        Expanded(
          child: Text(
            valor.isEmpty ? '—' : valor,
            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _buildFilaTarifaFicha(String concepto, String montoFormateado) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            concepto,
            style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
          ),
        ),
        Text(
          montoFormateado,
          style: const TextStyle(fontSize: 13.5, color: AppColors.textPrimary, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Future<void> _abrirFormularioEdicion(ClienteItem item) async {
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

  Future<void> _eliminarCliente(ClienteItem cliente) async {
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
        _clientes = List<ClienteItem>.from(_datosOriginales);
      } else {
        final q = query.toLowerCase().trim();
        _clientes = _datosOriginales.where((c) {
          final nombre = c['nombre'].toString().toLowerCase();
          final contacto = c['contacto'].toString().toLowerCase();
          final ciudad = c['ubicacion'].toString().toLowerCase();
          return nombre.contains(q) || contacto.contains(q) || ciudad.contains(q);
        }).toList();
      }
      _ordenarLista(_clientes);
    });
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
            icon: Icons.handshake_outlined,
            watermarkIcon: Icons.local_shipping_outlined,
            title: 'Lista de Clientes',
            subtitle: 'Gestiona las relaciones comerciales y detalles de contacto de tu cartera logística.',
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
          else if (_clientes.isEmpty)
            _buildCartelSinRegistros()
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final int columnas = constraints.maxWidth > 1050 ? 3 : (constraints.maxWidth > 700 ? 2 : 1);
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _clientesPaginados.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columnas,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    mainAxisExtent: 206,
                  ),
                  itemBuilder: (context, index) => _buildTarjeta(_clientesPaginados[index]),
                );
              },
            ),
          const SizedBox(height: 24),

          // 5. Paginador
          if (!_isLoading && _clientes.isNotEmpty) Center(child: _buildPaginador()),

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
      onPressed: _exportarCsvClientes,
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
            pageBuilder: (_, __, ___) => const ClienteFormScreen(),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          ),
        );
        _cargarClientesDesdeSupabase();
      },
      icon: const Icon(Icons.add, size: 18, color: Colors.white),
      label: const Text(
        'Agregar Cliente',
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

  Widget _lineaDato(IconData icono, String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Icon(icono, size: 15, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto.isEmpty ? '—' : texto,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTarjeta(ClienteItem item) {
    final String hace = (item['hace'] ?? '').toString();

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: sombraTarjeta,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(color: PageHeroBanner.navyClaro, shape: BoxShape.circle),
                  child: const Icon(Icons.apartment_rounded, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item['nombre'],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14.5,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.successBg,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'ACTIVO',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.success),
                            ),
                          ),
                          _buildMenuTarjeta(item),
                        ],
                      ),
                      const SizedBox(height: 6),
                      _lineaDato(Icons.person_outline, 'Contacto: ${item['contacto']}'),
                      _lineaDato(Icons.phone_outlined, item['telefono']),
                      _lineaDato(Icons.place_outlined, item['ubicacion']),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFEEF1F7)),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.schedule, size: 15, color: AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          hace.isEmpty ? 'Sin fecha de registro' : 'Registrado: $hace',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
                InkWell(
                  onTap: () => _abrirModalFichaCliente(item),
                  borderRadius: BorderRadius.circular(6),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Row(
                      children: [
                        Text('Ver Ficha',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
                        Icon(Icons.chevron_right, size: 16, color: AppColors.primary),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuTarjeta(ClienteItem item) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 20, color: Color(0xFF64748B)),
      constraints: const BoxConstraints(),
      padding: const EdgeInsets.only(left: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onSelected: (accion) {
        if (accion == 'modificar') _abrirFormularioEdicion(item);
        if (accion == 'eliminar') _eliminarCliente(item);
      },
      itemBuilder: (ctx) => const [
        PopupMenuItem(
          value: 'modificar',
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 16, color: AppColors.primary),
              SizedBox(width: 8),
              Text('Modificar Cliente',
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
              Text('Eliminar Cliente',
                  style: TextStyle(fontSize: 12.5, color: Colors.red, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ],
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
        onChanged: _filtrarClientes,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: esPantallaPequena ? 'Buscar por empresa, contacto...' : 'Buscar por nombre de empresa, contacto o ubicación...',
          hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
          prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xFF475569)),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18, color: Color(0xFF94A3B8)),
                  onPressed: () {
                    _searchController.clear();
                    _filtrarClientes('');
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
      'Directorio de Clientes',
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(10)),
        child: Text(
          '${_clientes.length} Total',
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
            PopupMenuItem(value: true, child: Text('Nombre (A-Z)', style: TextStyle(fontSize: 13))),
            PopupMenuItem(value: false, child: Text('Nombre (Z-A)', style: TextStyle(fontSize: 13))),
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
                  _ordenAscendente ? 'Nombre (A-Z)' : 'Nombre (Z-A)',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
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
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: _cargarClientesDesdeSupabase,
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
      children: [bloqueTitulo, const SizedBox(height: 10), bloqueOrden],
    );
  }

  // ---------------------------------------------------------- paginador

  Widget _buildPaginador() {
    final int total = _totalPaginas;
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

  Widget _buildFooterResponsivo(bool esPantallaPequena) {
    final enlaces = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildFooterLink('Términos de Servicio'),
        const SizedBox(width: 14),
        _buildFooterLink('Soporte IT'),
      ],
    );

    const servidorOperativo = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, color: Colors.green, size: 7),
        SizedBox(width: 5),
        Text('SERVIDORES EN LÍNEA', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green)),
      ],
    );

    if (!esPantallaPequena) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('© 2026 Transportes Contreras Enterprise. Sistema de Gestión Logística v2.4.1', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
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
          '© 2026 Transportes Contreras Enterprise. Sistema de Gestión Logística v2.4.1',
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
        c['ubicacion'] ?? c['direccion'] ?? '',
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