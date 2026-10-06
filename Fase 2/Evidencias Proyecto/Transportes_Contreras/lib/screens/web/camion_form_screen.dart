import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/camion.dart';
import '../../repositories/camiones_repository.dart';
import '../../repositories/repository_exception.dart';
import '../../theme/app_colors.dart';
import '../../widgets/admin_shell.dart';
import '../../widgets/document_upload_field.dart';
import '../../widgets/form_section_card.dart';
import '../../widgets/confirm_dialog.dart';

class CamionFormScreen extends StatefulWidget {
  const CamionFormScreen({super.key, this.onGuardar});

  final ValueChanged<Camion>? onGuardar;

  @override
  State<CamionFormScreen> createState() => _CamionFormScreenState();
}

class _CamionFormScreenState extends State<CamionFormScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controladores de Texto
  final _marcaCtrl = TextEditingController();
  final _modeloCtrl = TextEditingController();
  // NOTA: tipo_camion queda como texto libre por ahora; se convertirá en un
  // select cuando exista el catálogo de tipos de camión en Supabase (mismo
  // caso que comuna/región en el form de Consignatario). No se envía a la
  // base de datos todavía.
  final _tipoCtrl = TextEditingController();
  final _anioCtrl = TextEditingController();
  final _patenteCtrl = TextEditingController();

  // Controladores y Fechas para Documentos
  final _revTecnicaFechaCtrl = TextEditingController();
  final _permisoFechaCtrl = TextEditingController();
  final _soapFechaCtrl = TextEditingController();
  final _padronFechaCtrl = TextEditingController();

  DateTime? _vencRevision;
  DateTime? _vencPermiso;
  DateTime? _vencSoap;
  DateTime? _vencPadron;

  final _repo = CamionesRepository();

  XFile? _revisionFile;
  XFile? _permisoFile;
  XFile? _soapFile;
  XFile? _padronFile;

  bool _guardando = false;
  int _formVersion = 0; // cambia al limpiar, para reiniciar los campos de documentos

  @override
  void dispose() {
    _marcaCtrl.dispose();
    _modeloCtrl.dispose();
    _tipoCtrl.dispose();
    _anioCtrl.dispose();
    _patenteCtrl.dispose();
    _revTecnicaFechaCtrl.dispose();
    _permisoFechaCtrl.dispose();
    _soapFechaCtrl.dispose();
    _padronFechaCtrl.dispose();
    super.dispose();
  }

  /// Selector directo de solo Año usando YearPicker
  Future<void> _seleccionarAnio(BuildContext context) async {
    final now = DateTime.now();

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text(
            'Selecciona el Año de Fabricación',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: 300,
            height: 300,
            child: YearPicker(
              firstDate: DateTime(1980),
              lastDate: DateTime(now.year + 1),
              selectedDate: _anioCtrl.text.isNotEmpty
                  ? DateTime(int.tryParse(_anioCtrl.text) ?? now.year)
                  : now,
              onChanged: (DateTime dateTime) {
                setState(() {
                  _anioCtrl.text = dateTime.year.toString();
                });
                Navigator.pop(context);
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _seleccionarFecha(
    BuildContext context,
    TextEditingController controller,
    Function(DateTime) onSelected,
  ) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 10),
      helpText: 'Selecciona fecha de vencimiento',
      cancelText: 'CANCELAR',
      confirmText: 'ACEPTAR',
      locale: const Locale('es', 'CL'),
    );
    if (picked != null) {
      setState(() {
        onSelected(picked);
        controller.text =
            '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}';
      });
    }
  }

  void _mostrarMensaje(String texto, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(texto), backgroundColor: color),
    );
  }

  void _limpiarFormulario() {
    _formKey.currentState?.reset();
    _marcaCtrl.clear();
    _modeloCtrl.clear();
    _tipoCtrl.clear();
    _anioCtrl.clear();
    _patenteCtrl.clear();
    _revTecnicaFechaCtrl.clear();
    _permisoFechaCtrl.clear();
    _soapFechaCtrl.clear();
    _padronFechaCtrl.clear();
    setState(() {
      _vencRevision = null;
      _vencPermiso = null;
      _vencSoap = null;
      _vencPadron = null;
      _revisionFile = null;
      _permisoFile = null;
      _soapFile = null;
      _padronFile = null;
      _formVersion++;
    });
  }

  Future<void> _guardar() async {
    if (_guardando) return;
    if (!_formKey.currentState!.validate()) return;

    final camion = Camion(
      patente: _patenteCtrl.text.trim().toUpperCase(),
      marca: _marcaCtrl.text.trim(),
      modelo: _modeloCtrl.text.trim(),
      anio: int.parse(_anioCtrl.text.trim()),
    );

    final confirmado = await mostrarDialogoConfirmacion(
      context,
      titulo: 'Confirmar Registro de Camión',
      mensaje: 'Verifique los datos del vehículo antes de guardar.',
      resumen: {
        'Patente': camion.patente,
        'Marca': camion.marca,
        'Modelo': camion.modelo,
        'Tipo': _tipoCtrl.text.trim(),
        'Año': camion.anio.toString(),
        'Estado': camion.estado,
        'Rev. Técnica': _revisionFile != null ? 'Adjunta' : 'Sin adjuntar',
        'Permiso Circ.': _permisoFile != null ? 'Adjunto' : 'Sin adjuntar',
        'SOAP': _soapFile != null ? 'Adjunto' : 'Sin adjuntar',
        'Padrón': _padronFile != null ? 'Adjunto' : 'Sin adjuntar',
      },
      icono: Icons.local_shipping_outlined,
    );

    if (!confirmado || !mounted) return;

    setState(() => _guardando = true);
    try {
      await _repo.crear(
        camion,
        revisionTecnica: _revisionFile,
        permisoCirculacion: _permisoFile,
        seguroSoap: _soapFile,
        padron: _padronFile,
      );
      if (!mounted) return;
      widget.onGuardar?.call(camion);
      _mostrarMensaje('Camión patente "${camion.patente}" guardado correctamente', AppColors.success);
      _limpiarFormulario();
    } on RepositoryException catch (e) {
      if (!mounted) return;
      _mostrarMensaje(e.mensaje, Colors.red.shade700);
    } catch (_) {
      if (!mounted) return;
      _mostrarMensaje(
        'No se pudo guardar el camión. Revisa tu conexión e inténtalo de nuevo.',
        Colors.red.shade700,
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      selectedIndex: 10, // O el índice que uses para Camiones
      showBackButton: true, // <--- HABILITA LA FLECHA DE VOLVER
      title: 'Gestión de Flota: Registro de Camión',
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Banner superior de instrucciones
                  _buildInstruccionesBanner(),
                  const SizedBox(height: 20),

                  // Header con banner del vehículo y panel lateral de estado
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth > 860;
                      final heroBanner = _buildHeroBanner();
                      final sideCard = _buildSideCard();

                      if (isWide) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 2, child: heroBanner),
                            const SizedBox(width: 24),
                            SizedBox(width: 320, child: sideCard),
                          ],
                        );
                      }
                      return Column(
                        children: [
                          heroBanner,
                          const SizedBox(height: 20),
                          sideCard,
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 24),

                  // Información Técnica del Vehículo
                  FormSectionCard(
                    icon: Icons.build_outlined,
                    title: 'Información Técnica del Vehículo',
                    child: Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: LabeledTextField(
                                label: 'Marca',
                                controller: _marcaCtrl,
                                hint: 'Ej: Volvo',
                                icon: Icons.minor_crash_outlined,
                                validator: (v) => v == null || v.isEmpty ? 'Requerido' : null,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: LabeledTextField(
                                label: 'Modelo',
                                controller: _modeloCtrl,
                                hint: 'Ej: FH16',
                                icon: Icons.local_shipping_outlined,
                                validator: (v) => v == null || v.isEmpty ? 'Requerido' : null,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: LabeledTextField(
                                label: 'Tipo de Camión',
                                controller: _tipoCtrl,
                                hint: 'Ej: Articulado',
                                icon: Icons.category_outlined,
                                validator: (v) => v == null || v.isEmpty ? 'Requerido' : null,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: LabeledTextField(
                                label: 'Patente (PPU)',
                                controller: _patenteCtrl,
                                hint: 'Ej: ABCD-12',
                                icon: Icons.subtitles_outlined,
                                validator: (v) => v == null || v.isEmpty ? 'Ingresa la patente' : null,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: LabeledTextField(
                                label: 'Año de Fabricación',
                                controller: _anioCtrl,
                                hint: 'aaaa',
                                icon: Icons.calendar_today_outlined,
                                readOnly: true,
                                onTap: () => _seleccionarAnio(context),
                                validator: (v) => v == null || v.isEmpty ? 'Requerido' : null,
                              ),
                            ),
                            const SizedBox(width: 16),
                            // Espacio para equilibrar la fila de 3 columnas
                            const Expanded(child: SizedBox()),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Gestión de Documentación
                  FormSectionCard(
                    icon: Icons.folder_open_outlined,
                    title: 'Gestión de Documentación',
                    subtitle: 'Los conductores asignados podrán ver estos documentos en sus dispositivos.',
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isDesktop = constraints.maxWidth > 900;
                        final docs = [
                          _buildDocItem(
                            title: 'Revisión Técnica',
                            docKey: 'revision',
                            dateCtrl: _revTecnicaFechaCtrl,
                            onDateTap: () => _seleccionarFecha(context, _revTecnicaFechaCtrl, (d) => _vencRevision = d),
                            onFileSelected: (f) => setState(() => _revisionFile = f),
                          ),
                          _buildDocItem(
                            title: 'Permiso de Circulación',
                            docKey: 'permiso',
                            dateCtrl: _permisoFechaCtrl,
                            onDateTap: () => _seleccionarFecha(context, _permisoFechaCtrl, (d) => _vencPermiso = d),
                            onFileSelected: (f) => setState(() => _permisoFile = f),
                          ),
                          _buildDocItem(
                            title: 'Seguro SOAP',
                            docKey: 'soap',
                            dateCtrl: _soapFechaCtrl,
                            onDateTap: () => _seleccionarFecha(context, _soapFechaCtrl, (d) => _vencSoap = d),
                            onFileSelected: (f) => setState(() => _soapFile = f),
                          ),
                          _buildDocItem(
                            title: 'Padrón',
                            docKey: 'padron',
                            dateCtrl: _padronFechaCtrl,
                            onDateTap: () => _seleccionarFecha(context, _padronFechaCtrl, (d) => _vencPadron = d),
                            onFileSelected: (f) => setState(() => _padronFile = f),
                          ),
                        ];

                        if (isDesktop) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: docs.map((doc) => Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                child: doc,
                              ),
                            )).toList(),
                          );
                        }
                        return Column(
                          children: docs.map((doc) => Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: doc,
                          )).toList(),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Bloque de Confirmación Final
                  _buildBottomActionSection(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInstruccionesBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, color: AppColors.textSecondary, size: 20),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'INSTRUCCIONES DE REGISTRO',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: AppColors.textPrimary),
                ),
                SizedBox(height: 2),
                Text(
                  'Ingrese los datos técnicos y legales del vehículo. Asegúrese de que la patente y los documentos estén al día para la correcta asignación de servicios logísticos.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroBanner() {
    return Container(
      height: 200,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E293B), Color(0xFF334155)],
        ),
      ),
      child: Stack(
        children: [
          // Ícono decorativo de fondo (sin depender de internet, a
          // diferencia de una imagen de red: el proyecto es offline-first).
          Positioned(
            right: -10,
            bottom: -20,
            child: Icon(
              Icons.local_shipping_rounded,
              size: 160,
              color: Colors.white.withOpacity(0.08),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration:
                          BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(6)),
                      child: const Icon(Icons.local_shipping, color: Colors.white, size: 18),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'DATOS GENERALES',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Actualice la información técnica base del vehículo para monitoreo en tiempo real.',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSideCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.verified_user_outlined, size: 20, color: AppColors.primary),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'VERIFICACIÓN DE REGISTRO',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Todos los campos son obligatorios para el cumplimiento normativo de Transportes Contreras.',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _guardando ? null : _guardar,
            icon: _guardando
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.save_outlined, size: 16),
            label: Text(_guardando ? 'GUARDANDO...' : 'GUARDAR CAMIÓN'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _guardando ? null : () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close, size: 16),
            label: const Text('CANCELAR Y VOLVER'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.border),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocItem({
    required String title,
    required String docKey,
    required TextEditingController dateCtrl,
    required VoidCallback onDateTap,
    required ValueChanged<XFile> onFileSelected,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 14),
          LabeledTextField(
            label: 'Vencimiento',
            controller: dateCtrl,
            hint: 'dd/mm/aaaa',
            icon: Icons.calendar_today_outlined,
            readOnly: true,
            onTap: onDateTap,
          ),
          const SizedBox(height: 14),
          DocumentUploadField(
            key: ValueKey('$docKey-$_formVersion'),
            label: 'Documento',
            onFileSelected: onFileSelected,
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActionSection() {
    return Center(
      child: Column(
        children: [
          const Icon(Icons.verified_outlined, color: AppColors.textSecondary, size: 28),
          const SizedBox(height: 8),
          const Text(
            'REVISIÓN DE SEGURIDAD',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 4),
          const Text(
            'Al guardar estos datos, confirma que la información es verídica y que los\ndocumentos adjuntos son legibles. El sistema auditará las fechas de vencimiento automáticamente.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _guardando ? null : _guardar,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: _guardando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('GUARDAR Y CONFIRMAR REGISTRO', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}