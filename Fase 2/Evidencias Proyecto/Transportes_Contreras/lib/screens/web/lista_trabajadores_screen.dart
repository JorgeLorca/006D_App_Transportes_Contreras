import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/trabajador.dart';
import '../../theme/app_colors.dart';
import 'trabajador_form_screen.dart';
import 'modificar/trabajador_modificar_screen.dart';
import '../../utils/csv_exporter.dart';
import '../../widgets/page_hero_banner.dart';
import '../../widgets/entity_list_card.dart';
import '../../widgets/list_page_widgets.dart';

typedef TrabajadorItem = Map<String, dynamic>;

class ListaTrabajadoresScreen extends StatefulWidget {
  const ListaTrabajadoresScreen({super.key});

  @override
  State<ListaTrabajadoresScreen> createState() => _ListaTrabajadoresScreenState();
}

class _ListaTrabajadoresScreenState extends State<ListaTrabajadoresScreen> {
  static const String _bucketDocumentos = 'documentos_identidad';

  final int _itemsPorPagina = 12;
  int _paginaActual = 1;
  bool _ordenAscendente = true;

  // Filtro de estado: 'todos', 'activo', 'en ruta', 'inactivo'
  String _filtroEstado = 'todos';

  List<TrabajadorItem> _datosOriginales = [];
  List<TrabajadorItem> _trabajadores = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  int get _totalPaginas {
    if (_trabajadores.isEmpty) return 1;
    return (_trabajadores.length / _itemsPorPagina).ceil();
  }

  List<TrabajadorItem> get _trabajadoresPaginados {
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
      final supabase = Supabase.instance.client;

      // 1. Obtener todos los conductores
      final List listaRemota = await supabase.from('conductores').select('*');

      // 2. Obtener viajes con Cliente y Consignatario
      List listaViajes = [];
      try {
        listaViajes = await supabase
            .from('viajes')
            .select('conductor_rut, estado, fecha_viaje, iniciado_en, finalizado_en, clientes(nombre_empresa), consignatarios(nombre_empresa)')
            .order('fecha_viaje', ascending: false);
      } catch (e) {
        debugPrint('Aviso consultando viajes para trabajadores: $e');
      }

      // 3. Obtener el historial de asistencia
      List listaAsistencias = [];
      try {
        listaAsistencias = await supabase
            .from('asistencia')
            .select('conductor_rut, tipo_evento, hora_evento')
            .order('hora_evento', ascending: false);
      } catch (e) {
        debugPrint('Aviso consultando asistencia para trabajadores: $e');
      }

      if (mounted) {
        final List<TrabajadorItem> datosMapeados = [];

        for (final t in listaRemota) {
          if (t is! Map) continue;
          final TrabajadorItem map = TrabajadorItem.from(t);
          final String rut = (map['rut'] ?? '').toString().trim();
          final String nombre = (map['nombre_completo'] ?? 'Sin Nombre').toString();

          String iniciales = 'TR';
          final partes = nombre.trim().split(' ');
          if (partes.length >= 2 && partes[0].isNotEmpty && partes[1].isNotEmpty) {
            iniciales = '${partes[0][0]}${partes[1][0]}'.toUpperCase();
          } else if (partes.isNotEmpty && partes[0].isNotEmpty) {
            iniciales = partes[0][0].toUpperCase();
          }

          // Filtrar los viajes que pertenecen a este RUT y buscar si hay uno en_curso
          final List<TrabajadorItem> viajesDelChofer = [];
          TrabajadorItem? viajeEnCurso;

          for (final itemV in listaViajes) {
            if (itemV is Map) {
              final TrabajadorItem vMap = TrabajadorItem.from(itemV);
              final String rutViaje = (vMap['conductor_rut'] ?? '').toString().trim();
              if (rutViaje == rut) {
                viajesDelChofer.add(vMap);
                final String estV = (vMap['estado'] ?? '').toString().toLowerCase().trim();
                if (viajeEnCurso == null && estV == 'en_curso') {
                  viajeEnCurso = vMap;
                }
              }
            }
          }

          // Construir el texto real de Último Viaje: "Cliente -> Consignatario"
          String ultimoViajeTexto = 'Sin viajes registrados';
          final TrabajadorItem? viajeReferencia =
              viajeEnCurso ?? (viajesDelChofer.isNotEmpty ? viajesDelChofer.first : null);

          if (viajeReferencia != null) {
            String nombreCliente = 'Origen';
            final cliData = viajeReferencia['clientes'];
            if (cliData is Map) {
              nombreCliente = (cliData['nombre_empresa'] ?? 'Origen').toString();
            }

            String nombreConsignatario = 'Destino';
            final conData = viajeReferencia['consignatarios'];
            if (conData is Map) {
              nombreConsignatario = (conData['nombre_empresa'] ?? 'Destino').toString();
            }
            ultimoViajeTexto = '$nombreCliente ➔ $nombreConsignatario';
          }

          // Determinar el Estado real del trabajador ('En Ruta', 'Activo', 'Inactivo')
          String estadoReal = (map['estado'] ?? '').toString().trim();
          if (viajeEnCurso != null) {
            estadoReal = 'En Ruta';
          } else {
            TrabajadorItem? ultimaAsistencia;
            for (final itemA in listaAsistencias) {
              if (itemA is Map) {
                final TrabajadorItem aMap = TrabajadorItem.from(itemA);
                final String rutAsist = (aMap['conductor_rut'] ?? '').toString().trim();
                if (rutAsist == rut) {
                  ultimaAsistencia = aMap;
                  break;
                }
              }
            }

            if (ultimaAsistencia != null) {
              final String tipoEv = (ultimaAsistencia['tipo_evento'] ?? '').toString().toLowerCase().trim();
              estadoReal = (tipoEv == 'entrada') ? 'Activo' : 'Inactivo';
            } else if (estadoReal.isEmpty) {
              estadoReal = 'Inactivo';
            }
          }

          datosMapeados.add({
            'rut': rut,
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
            'estado': estadoReal,
            'ultimo_viaje': ultimoViajeTexto,
          });
        }

        setState(() {
          _datosOriginales = datosMapeados;
          _trabajadores = List<TrabajadorItem>.from(_datosOriginales);
          _isLoading = false;
        });
        _aplicarFiltrosYOrden();
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

  Future<void> _abrirFormularioEdicion(TrabajadorItem item) async {
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

  Future<void> _eliminarTrabajador(TrabajadorItem trabajador) async {
    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
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

      // Si la BD no borró ninguna fila (normalmente por RLS), no lo sacamos de la lista.
      if (resultado.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'No se eliminó: la base de datos no borró ninguna fila (revisa la política RLS de DELETE en "conductores").'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Elimina también el usuario de acceso en Supabase Auth.
      String? avisoAuth;
      final authId = (trabajador['auth_id'] ?? '').toString();
      if (authId.isNotEmpty) {
        try {
          await Supabase.instance.client.functions.invoke(
            'eliminar_conductor',
            body: {'auth_id': authId},
          );
        } on FunctionException catch (e) {
          debugPrint('eliminar_conductor: status=${e.status} details=${e.details}');
          avisoAuth = 'Se eliminó el trabajador, pero no su usuario de acceso: ${e.details ?? e.reasonPhrase}';
        } catch (e) {
          debugPrint('eliminar_conductor error: $e');
          avisoAuth = 'Se eliminó el trabajador, pero no su usuario de acceso: $e';
        }
      }

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
            content: Text(avisoAuth ?? 'Trabajador ${trabajador['nombre']} eliminado correctamente.'),
            backgroundColor: avisoAuth == null ? AppColors.textPrimary : Colors.orange.shade800,
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

  void _aplicarFiltrosYOrden() {
    final query = _searchController.text.toLowerCase().trim();
    final queryRutLimpio = query.replaceAll(RegExp(r'[.-]'), '');
    final queryTelefono = query.replaceAll(RegExp(r'[\s+-]'), '');

    final filtrados = _datosOriginales.where((t) {
      // Filtro por estado
      if (_filtroEstado != 'todos' &&
          t['estado'].toString().toLowerCase().trim() != _filtroEstado) {
        return false;
      }

      if (query.isEmpty) return true;
      final nombre = t['nombre'].toString().toLowerCase();
      final rut = t['rut'].toString().toLowerCase();
      final rutLimpio = rut.replaceAll(RegExp(r'[.-]'), '');
      final telefono = t['telefono'].toString().replaceAll(RegExp(r'[\s+-]'), '');

      final coincideNombre = nombre.contains(query);
      final coincideRut = rut.contains(query) ||
          (queryRutLimpio.isNotEmpty && rutLimpio.contains(queryRutLimpio));
      final coincideTelefono = queryTelefono.isNotEmpty && telefono.contains(queryTelefono);

      return coincideNombre || coincideRut || coincideTelefono;
    }).toList();

    filtrados.sort((a, b) {
      final nombreA = a['nombre'].toString().toLowerCase();
      final nombreB = b['nombre'].toString().toLowerCase();
      return _ordenAscendente ? nombreA.compareTo(nombreB) : nombreB.compareTo(nombreA);
    });

    setState(() {
      _trabajadores = filtrados;
      if (_paginaActual > _totalPaginas) {
        _paginaActual = _totalPaginas;
      }
    });
  }

  void _filtrarTrabajadores(String query) {
    _paginaActual = 1;
    _aplicarFiltrosYOrden();
  }

  /// Resuelve la URL del documento desde el bucket "documentos_identidad"
  Future<String?> _resolverUrlDocumento(String rawPath) async {
    final limpia = rawPath.trim();
    if (limpia.isEmpty || limpia.toLowerCase() == 'null') return null;
    if (limpia.startsWith('http://') || limpia.startsWith('https://')) {
      return limpia;
    }

    final storage = Supabase.instance.client.storage;
    try {
      return await storage.from(_bucketDocumentos).createSignedUrl(limpia, 3600);
    } catch (_) {
      return storage.from(_bucketDocumentos).getPublicUrl(limpia);
    }
  }

  Future<void> _abrirModalDocumento({
    required String tituloDocumento,
    required String nombreConductor,
    required String rutConductor,
    required String? rutaArchivo,
  }) async {
    final rutaLimpia = (rutaArchivo ?? '').trim();

    if (rutaLimpia.isEmpty || rutaLimpia.toLowerCase() == 'null') {
      showDialog(
        context: context,
        builder: (alertCtx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Row(
            children: [
              Icon(Icons.image_not_supported_outlined, color: AppColors.warning, size: 22),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Documento no adjuntado',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
          content: Text(
            'El trabajador $nombreConductor no tiene una fotografía adjuntada para: $tituloDocumento.',
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(alertCtx).pop(),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('Cerrar', style: TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ],
        ),
      );
      return;
    }

    final urlResuelta = await _resolverUrlDocumento(rutaLimpia);
    if (!mounted) return;

    if (urlResuelta == null || urlResuelta.isEmpty) {
      showDialog(
        context: context,
        builder: (alertCtx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Row(
            children: [
              Icon(Icons.error_outline, color: Colors.red, size: 22),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'No se pudo obtener el archivo',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
          content: const Text(
            'No fue posible generar el enlace de visualización desde el almacenamiento.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(alertCtx).pop(),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('Cerrar', style: TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (imgCtx) {
        final screenWidth = MediaQuery.of(imgCtx).size.width;
        final isMobileModal = screenWidth < 600;

        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: Colors.white,
          insetPadding: EdgeInsets.symmetric(
            horizontal: isMobileModal ? 12 : 24,
            vertical: 24,
          ),
          child: Container(
            width: 660,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(imgCtx).size.height * 0.88,
            ),
            padding: EdgeInsets.all(isMobileModal ? 16 : 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.badge_outlined, color: AppColors.primary, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tituloDocumento,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '$nombreConductor • RUT: $rutConductor',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppColors.textSecondary, size: 20),
                      tooltip: 'Cerrar',
                      onPressed: () => Navigator.of(imgCtx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Flexible(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(minHeight: 240),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: InteractiveViewer(
                        minScale: 0.8,
                        maxScale: 4.0,
                        child: Image.network(
                          urlResuelta,
                          fit: BoxFit.contain,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return SizedBox(
                              height: 300,
                              child: Center(
                                child: CircularProgressIndicator(
                                  value: loadingProgress.expectedTotalBytes != null
                                      ? loadingProgress.cumulativeBytesLoaded /
                                          loadingProgress.expectedTotalBytes!
                                      : null,
                                  color: Colors.white,
                                ),
                              ),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return const SizedBox(
                              height: 240,
                              child: Center(
                                child: Padding(
                                  padding: EdgeInsets.all(20.0),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.broken_image_outlined, color: Colors.white54, size: 42),
                                      SizedBox(height: 10),
                                      Text(
                                        'No se pudo cargar la imagen del documento desde el servidor.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(color: Colors.white70, fontSize: 13),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Deslice o pellizque para ampliar el documento',
                  style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _abrirFiltros() async {
    final r = await mostrarFiltroDialog<String>(
      context,
      descripcion: 'Filtrar trabajadores por estado:',
      actual: _filtroEstado,
      valorLimpiar: 'todos',
      opciones: const <OpcionFiltro<String>>[
        OpcionFiltro(
          valor: 'todos',
          titulo: 'Todos los trabajadores',
          subtitulo: 'Muestra el personal completo sin restricción',
        ),
        OpcionFiltro(
          valor: 'activo',
          titulo: 'Activo',
          subtitulo: 'Personal con entrada registrada',
          color: AppColors.success,
        ),
        OpcionFiltro(
          valor: 'en ruta',
          titulo: 'En Ruta',
          subtitulo: 'Conductores con un viaje en curso',
          color: Color(0xFFD97706),
        ),
        OpcionFiltro(
          valor: 'inactivo',
          titulo: 'Inactivo',
          subtitulo: 'Personal sin jornada activa',
          color: Color(0xFF991B1B),
        ),
      ],
    );
    if (r == null) return;
    _filtroEstado = r;
    _paginaActual = 1;
    _aplicarFiltrosYOrden();
  }

  String? get _textoFiltroActivo {
    switch (_filtroEstado) {
      case 'activo':
        return 'Filtro: Activo';
      case 'en ruta':
        return 'Filtro: En Ruta';
      case 'inactivo':
        return 'Filtro: Inactivo';
      default:
        return null;
    }
  }

  EstadoTipo _tipoEstado(String estado) {
    switch (estado.toLowerCase().trim()) {
      case 'activo':
        return EstadoTipo.ok;
      case 'en ruta':
        return EstadoTipo.alerta;
      default:
        return EstadoTipo.peligro;
    }
  }

  void _verDetalle(TrabajadorItem item) {
    final String nombre = item['nombre'].toString();
    final String rut = item['rut'].toString();
    final String estado = (item['estado'] ?? 'Inactivo').toString();

    mostrarDetalleDialog(
      context,
      icono: Icons.person_outline,
      titulo: nombre,
      estado: EstadoBadge(texto: estado, tipo: _tipoEstado(estado)),
      filas: [
        DetalleFila('RUT', rut),
        DetalleFila('Teléfono', item['telefono'].toString()),
        DetalleFila('Correo', item['email'].toString()),
        DetalleFila('Último viaje', item['ultimo_viaje'].toString()),
      ],
      extra: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              _abrirModalDocumento(
                tituloDocumento: 'Cédula de Identidad',
                nombreConductor: nombre,
                rutConductor: rut,
                rutaArchivo: (item['url_cedula_identidad'] ?? '').toString(),
              );
            },
            icon: const Icon(Icons.badge_outlined, size: 16),
            label: const Text('Carnet', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              _abrirModalDocumento(
                tituloDocumento: 'Licencia de Conducir',
                nombreConductor: nombre,
                rutConductor: rut,
                rutaArchivo: (item['url_licencia_conducir'] ?? '').toString(),
              );
            },
            icon: const Icon(Icons.drive_eta_outlined, size: 16),
            label: const Text('Licencia', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
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
            icon: Icons.groups_outlined,
            watermarkIcon: Icons.engineering,
            title: 'Lista de Trabajadores',
            subtitle: 'Gestiona el personal de la empresa y sus roles en el sistema.',
          ),
          const SizedBox(height: 20),

          ListToolbar(
            controller: _searchController,
            hint: 'Buscar por nombre, RUT o teléfono...',
            onChanged: _filtrarTrabajadores,
            onFiltros: _abrirFiltros,
            filtroActivoTexto: _textoFiltroActivo,
            labelAgregar: 'Agregar Trabajador',
            iconoAgregar: Icons.person_add_alt_1,
            onAgregar: () async {
              await Navigator.of(context).push(
                PageRouteBuilder(
                  pageBuilder: (_, __, ___) => const TrabajadorFormScreen(),
                  transitionDuration: Duration.zero,
                  reverseTransitionDuration: Duration.zero,
                ),
              );
              _cargarTrabajadoresDesdeSupabase();
            },
          ),
          const SizedBox(height: 28),

          ListSectionHeader(
            titulo: 'Total de Trabajadores',
            contador: '${_trabajadores.length}',
            orden: SortDropdown<bool>(
              etiqueta: 'Ordenar:',
              valor: _ordenAscendente,
              opciones: const {true: 'A - Z', false: 'Z - A'},
              onChanged: (v) {
                _ordenAscendente = v;
                _paginaActual = 1;
                _aplicarFiltrosYOrden();
              },
            ),
            acciones: [
              ListIconButton(
                icono: Icons.download_outlined,
                tooltip: 'Exportar CSV',
                onPressed: _exportarCsvTrabajadores,
              ),
              ListIconButton(
                icono: Icons.refresh,
                tooltip: 'Refrescar trabajadores',
                onPressed: _cargarTrabajadoresDesdeSupabase,
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
          else if (_trabajadores.isEmpty)
            const ListEmptyState(
              icono: Icons.person_off_outlined,
              titulo: 'No se encontraron trabajadores registrados',
              mensaje: 'No hay personal en la base de datos o el criterio de búsqueda no arrojó resultados.',
            )
          else
            EntityGrid(
              itemCount: _trabajadoresPaginados.length,
              anchoMinimo: 460,
              maxColumnas: 2,
              altoItem: 112,
              itemBuilder: (context, index) {
                final item = _trabajadoresPaginados[index];
                final String estado = (item['estado'] ?? 'Inactivo').toString();
                return EntityListCard(
                  leading: CardAvatar.iniciales(item['iniciales'].toString()),
                  titulo: item['nombre'].toString(),
                  estado: EstadoBadge(texto: estado, tipo: _tipoEstado(estado)),
                  detalles: [
                    CardInfoLine(texto: 'RUT: ${item['rut']}', destacado: true),
                    CardInfoLine(icono: Icons.call_outlined, texto: item['telefono'].toString()),
                  ],
                  tooltipVer: 'Ver trabajador',
                  onVer: () => _verDetalle(item),
                  acciones: [
                    EntityCardAction(
                      label: 'Modificar Trabajador',
                      icono: Icons.edit_outlined,
                      onTap: () => _abrirFormularioEdicion(item),
                    ),
                    EntityCardAction(
                      label: 'Eliminar Trabajador',
                      icono: Icons.delete_outline,
                      destructiva: true,
                      onTap: () => _eliminarTrabajador(item),
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
      'Último Viaje (Cliente -> Consignatario)',
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