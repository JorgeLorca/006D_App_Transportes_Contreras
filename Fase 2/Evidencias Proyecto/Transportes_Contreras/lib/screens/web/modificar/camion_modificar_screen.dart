import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../models/camion.dart';
import '../../../repositories/camiones_repository.dart';
import '../../../repositories/repository_exception.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/admin_shell.dart';
import '../../../widgets/confirm_dialog.dart';
import '../../../widgets/document_upload_field.dart';
import '../../../widgets/form_section_card.dart';

/// Screen dedicada a **modificar** un camión ya existente de la flota de
/// Transportes Contreras.
///
/// Es una screen separada de [CamionFormScreen] (que solo crea camiones
/// nuevos) para no mezclar la lógica de alta con la de edición. Aquí:
/// - La **patente no se puede editar**: además de ser el identificador
///   natural del vehículo, define la carpeta de sus documentos en Storage.
/// - Los documentos (revisión técnica, permiso de circulación, SOAP,
///   padrón) son opcionales de reemplazar: si no se elige un archivo
///   nuevo para alguno, el que ya existía queda intacto.
///
/// Al confirmar, hace un `UPDATE` sobre la fila (por [Camion.patente]) con
/// [CamionesRepository.actualizar] y vuelve al listado
/// (`Navigator.pop(true)`) para que se recarguen los datos.
class CamionModificarScreen extends StatefulWidget {
  const CamionModificarScreen({super.key, required this.camion, this.onActualizar});

  /// El camión a editar. Debe traer [Camion.patente] (viene de Supabase).
  final Camion camion;

  /// Callback opcional que recibe el camión ya actualizado.
  final ValueChanged<Camion>? onActualizar;

  @override
  State<CamionModificarScreen> createState() => _CamionModificarScreenState();
}

class _CamionModificarScreenState extends State<CamionModificarScreen> {
  final _formKey = GlobalKey<FormState>();

  late final _marcaCtrl = TextEditingController(text: widget.camion.marca);
  late final _modeloCtrl = TextEditingController(text: widget.camion.modelo);
  late final _patenteCtrl = TextEditingController(text: widget.camion.patente);
  late final _anioCtrl = TextEditingController(text: widget.camion.anio.toString());

  final _repo = CamionesRepository();

  // "disponible" (o "activo") se trata como disponible; cualquier otro
  // valor, como no disponible. Mismo criterio que usa el listado.
  late bool _disponible =
      widget.camion.estado.toLowerCase() == 'disponible' || widget.camion.estado.toLowerCase() == 'activo';

  // Solo se llenan si el usuario decide reemplazar el documento existente.
  XFile? _revisionFile;
  XFile? _permisoFile;
  XFile? _soapFile;
  XFile? _padronFile;

  bool _guardando = false;

  @override
  void dispose() {
    _marcaCtrl.dispose();
    _modeloCtrl.dispose();
    _patenteCtrl.dispose();
    _anioCtrl.dispose();
    super.dispose();
  }

  /// Selector directo de solo Año usando YearPicker (igual que en el
  /// formulario de creación).
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
                setState(() => _anioCtrl.text = dateTime.year.toString());
                Navigator.pop(context);
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _actualizar() async {
    if (_guardando) return;
    if (!_formKey.currentState!.validate()) return;

    final camionActualizado = Camion(
      id: widget.camion.id,
      patente: widget.camion.patente, // no editable
      marca: _marcaCtrl.text.trim(),
      modelo: _modeloCtrl.text.trim(),
      anio: int.parse(_anioCtrl.text.trim()),
      estado: _disponible ? 'disponible' : 'no_disponible',
      urlRevisionTecnica: widget.camion.urlRevisionTecnica,
      urlPermisoCirculacion: widget.camion.urlPermisoCirculacion,
      urlSeguroSoap: widget.camion.urlSeguroSoap,
      urlPadron: widget.camion.urlPadron,
      creadoEn: widget.camion.creadoEn,
    );

    final confirmado = await mostrarDialogoConfirmacion(
      context,
      titulo: 'Confirmar actualización de camión',
      mensaje: 'Verifique los datos del vehículo antes de guardar los cambios.',
      resumen: {
        'Patente': camionActualizado.patente,
        'Marca': camionActualizado.marca,
        'Modelo': camionActualizado.modelo,
        'Año': camionActualizado.anio.toString(),
        'Estado': _disponible ? 'Disponible' : 'No disponible',
        'Rev. Técnica': _revisionFile != null ? 'Se reemplazará' : 'Sin cambios',
        'Permiso Circ.': _permisoFile != null ? 'Se reemplazará' : 'Sin cambios',
        'SOAP': _soapFile != null ? 'Se reemplazará' : 'Sin cambios',
        'Padrón': _padronFile != null ? 'Se reemplazará' : 'Sin cambios',
      },
      icono: Icons.edit_outlined,
      textoConfirmar: 'CONFIRMAR Y ACTUALIZAR',
    );
    if (!confirmado || !mounted) return;

    setState(() => _guardando = true);
    try {
      await _repo.actualizar(
        camionActualizado,
        revisionTecnica: _revisionFile,
        permisoCirculacion: _permisoFile,
        seguroSoap: _soapFile,
        padron: _padronFile,
      );
      if (!mounted) return;
      widget.onActualizar?.call(camionActualizado);
      _mostrarMensaje(
        'Camión patente "${camionActualizado.patente}" actualizado correctamente',
        AppColors.success,
      );
      // Vuelve al listado para que se recarguen los datos.
      Navigator.of(context).pop(true);
    } on RepositoryException catch (e) {
      if (!mounted) return;
      _mostrarMensaje(e.mensaje, Colors.red.shade700);
    } catch (_) {
      if (!mounted) return;
      _mostrarMensaje(
        'No se pudo actualizar el camión. Revisa tu conexión e inténtalo de nuevo.',
        Colors.red.shade700,
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  void _mostrarMensaje(String texto, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(texto), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      selectedIndex: 10,
      showBackButton: true, // <--- HABILITA LA FLECHA DE VOLVER
      title: 'Gestión de Flota: Modificar Camión',
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
                  _buildAvisoEdicion(),
                  const SizedBox(height: 20),

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
                                icon: Icons.subtitles_outlined,
                                readOnly: true,
                                helperText: 'La patente no se puede modificar.',
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
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildSwitchDisponible(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  FormSectionCard(
                    icon: Icons.folder_open_outlined,
                    title: 'Gestión de Documentación',
                    subtitle: 'Opcional: solo si quieres reemplazar alguno de los documentos actuales.',
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isDesktop = constraints.maxWidth > 900;
                        final docs = [
                          _buildDocItem(
                            title: 'Revisión Técnica',
                            cargado: widget.camion.urlRevisionTecnica != null,
                            onFileSelected: (f) => setState(() => _revisionFile = f),
                          ),
                          _buildDocItem(
                            title: 'Permiso de Circulación',
                            cargado: widget.camion.urlPermisoCirculacion != null,
                            onFileSelected: (f) => setState(() => _permisoFile = f),
                          ),
                          _buildDocItem(
                            title: 'Seguro SOAP',
                            cargado: widget.camion.urlSeguroSoap != null,
                            onFileSelected: (f) => setState(() => _soapFile = f),
                          ),
                          _buildDocItem(
                            title: 'Padrón',
                            cargado: widget.camion.urlPadron != null,
                            onFileSelected: (f) => setState(() => _padronFile = f),
                          ),
                        ];

                        if (isDesktop) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: docs
                                .map((doc) => Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 6),
                                        child: doc,
                                      ),
                                    ))
                                .toList(),
                          );
                        }
                        return Column(
                          children: docs
                              .map((doc) => Padding(
                                    padding: const EdgeInsets.only(bottom: 16),
                                    child: doc,
                                  ))
                              .toList(),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),

                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: _guardando ? null : _actualizar,
                          icon: _guardando
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.save_outlined, size: 18),
                          label: Text(_guardando ? 'ACTUALIZANDO...' : 'ACTUALIZAR CAMIÓN'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            textStyle: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.3),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.close, size: 18),
                          label: const Text('CANCELAR Y VOLVER'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textPrimary,
                            side: const BorderSide(color: AppColors.border),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvisoEdicion() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.infoBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.infoBorder),
      ),
      child: const Row(
        children: [
          Icon(Icons.edit_outlined, color: AppColors.primary, size: 20),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'EDICIÓN DE REGISTRO',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: AppColors.textPrimary),
                ),
                SizedBox(height: 2),
                Text(
                  'Estás modificando un camión existente. La patente no se puede cambiar.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchDisponible() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(
            _disponible ? Icons.check_circle_outline : Icons.block_outlined,
            size: 18,
            color: _disponible ? AppColors.success : AppColors.textSecondary,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Disponible para asignación', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          Switch(
            value: _disponible,
            activeColor: AppColors.success,
            onChanged: (v) => setState(() => _disponible = v),
          ),
        ],
      ),
    );
  }

  Widget _buildDocItem({
    required String title,
    required bool cargado,
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
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                cargado ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 14,
                color: cargado ? AppColors.success : AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  cargado ? 'Documento ya cargado' : 'Sin documento cargado',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          DocumentUploadField(
            label: 'Reemplazar documento',
            onFileSelected: onFileSelected,
          ),
        ],
      ),
    );
  }
}