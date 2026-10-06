import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../models/trabajador.dart';
import '../../../repositories/repository_exception.dart';
import '../../../repositories/trabajadores_repository.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/admin_shell.dart';
import '../../../widgets/confirm_dialog.dart';
import '../../../widgets/document_upload_field.dart';
import '../../../widgets/form_section_card.dart';

/// Screen dedicada a **modificar** un trabajador (conductor) ya existente
/// del panel admin web de Transportes Contreras.
///
/// Es una screen separada de [TrabajadorFormScreen] (que solo crea
/// trabajadores nuevos, incluyendo sus credenciales de Auth) para no
/// mezclar esa lógica con la de edición. Aquí:
/// - El RUT **no se puede editar**: es la llave primaria de `conductores`
///   y además identifica la carpeta de documentos en Storage.
/// - No se tocan las credenciales de Auth (contraseña); eso quedaría para
///   un flujo de "restablecer contraseña" aparte.
/// - Los documentos (carnet/licencia) son opcionales de reemplazar: si no
///   se elige un archivo nuevo, los que ya existían quedan intactos.
///
/// Al confirmar, hace un `UPDATE` sobre la fila (por [Trabajador.rut]) con
/// [TrabajadoresRepository.actualizar] y vuelve al listado
/// (`Navigator.pop(true)`) para que se recarguen los datos.
class TrabajadorModificarScreen extends StatefulWidget {
  const TrabajadorModificarScreen({super.key, required this.trabajador, this.onActualizar});

  /// El trabajador a editar. Debe traer [Trabajador.rut] (viene de Supabase).
  final Trabajador trabajador;

  /// Callback opcional que recibe el trabajador ya actualizado.
  final ValueChanged<Trabajador>? onActualizar;

  @override
  State<TrabajadorModificarScreen> createState() => _TrabajadorModificarScreenState();
}

class _TrabajadorModificarScreenState extends State<TrabajadorModificarScreen> {
  final _formKey = GlobalKey<FormState>();

  late final _nombreCtrl = TextEditingController(text: widget.trabajador.nombreCompleto);
  late final _correoCtrl = TextEditingController(text: widget.trabajador.correo);
  // El campo solo edita los 9 dígitos; el "+56 " es fijo en la UI.
  late final _telefonoCtrl =
      TextEditingController(text: widget.trabajador.telefono.replaceFirst('+56 ', '').trim());
  late final _fechaCtrl = TextEditingController(text: _formatearFecha(widget.trabajador.fechaNacimiento));
  late final _rutCtrl = TextEditingController(text: widget.trabajador.rut);

  late DateTime? _fechaNacimiento = widget.trabajador.fechaNacimiento;

  final _repo = TrabajadoresRepository();

  // Solo se llenan si el usuario decide reemplazar el documento existente.
  XFile? _carnetFile;
  XFile? _licenciaFile;

  bool _guardando = false;

  static String _formatearFecha(DateTime? fecha) {
    if (fecha == null) return '';
    return '${fecha.day.toString().padLeft(2, '0')}/'
        '${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _correoCtrl.dispose();
    _telefonoCtrl.dispose();
    _fechaCtrl.dispose();
    _rutCtrl.dispose();
    super.dispose();
  }

  Future<void> _seleccionarFecha() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _fechaNacimiento ?? DateTime(now.year - 25),
      firstDate: DateTime(now.year - 80),
      lastDate: now,
      helpText: 'Fecha de nacimiento',
      cancelText: 'CANCELAR',
      confirmText: 'ACEPTAR',
      locale: const Locale('es', 'CL'),
    );
    if (picked != null) {
      setState(() {
        _fechaNacimiento = picked;
        _fechaCtrl.text = _formatearFecha(picked);
      });
    }
  }

  String? _validarNombre(String? v) {
    if (v == null || v.trim().isEmpty) return 'Ingresa el nombre completo';
    if (v.trim().split(' ').length < 2) return 'Ingresa nombre y apellido';
    return null;
  }

  String? _validarCorreo(String? v) {
    if (v == null || v.trim().isEmpty) return 'Ingresa el correo electrónico';
    final regex = RegExp(r'^[\w\.-]+@[\w\.-]+\.\w+$');
    if (!regex.hasMatch(v.trim())) return 'Correo inválido';
    return null;
  }

  String? _validarTelefono(String? v) {
    if (v == null || v.trim().isEmpty) return 'Ingresa el teléfono de contacto';
    if (v.trim().length != 9) return 'Debe tener 9 dígitos';
    return null;
  }

  Future<void> _actualizar() async {
    if (_guardando) return;
    if (!_formKey.currentState!.validate()) return;

    final trabajadorActualizado = Trabajador(
      rut: widget.trabajador.rut, // no editable
      authId: widget.trabajador.authId,
      nombreCompleto: _nombreCtrl.text.trim(),
      fechaNacimiento: _fechaNacimiento,
      correo: _correoCtrl.text.trim(),
      telefono: '+56 ${_telefonoCtrl.text.trim()}',
      urlCedulaIdentidad: widget.trabajador.urlCedulaIdentidad,
      urlLicenciaConducir: widget.trabajador.urlLicenciaConducir,
      creadoEn: widget.trabajador.creadoEn,
    );

    final confirmado = await mostrarDialogoConfirmacion(
      context,
      titulo: 'Confirmar actualización de trabajador',
      mensaje: 'Revisa los datos antes de guardar los cambios.',
      resumen: {
        'Nombre': trabajadorActualizado.nombreCompleto,
        'RUT': trabajadorActualizado.rut,
        'Fecha de nacimiento': _fechaCtrl.text.isEmpty ? 'Sin registrar' : _fechaCtrl.text,
        'Correo': trabajadorActualizado.correo,
        'Teléfono': trabajadorActualizado.telefono,
        'Carnet': _carnetFile != null ? 'Se reemplazará' : 'Sin cambios',
        'Licencia': _licenciaFile != null ? 'Se reemplazará' : 'Sin cambios',
      },
      icono: Icons.edit_outlined,
      textoConfirmar: 'CONFIRMAR Y ACTUALIZAR',
    );
    if (!confirmado || !mounted) return;

    setState(() => _guardando = true);
    try {
      await _repo.actualizar(trabajadorActualizado, carnet: _carnetFile, licencia: _licenciaFile);
      if (!mounted) return;
      widget.onActualizar?.call(trabajadorActualizado);
      _mostrarMensaje(
        'Trabajador "${trabajadorActualizado.nombreCompleto}" actualizado correctamente',
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
        'No se pudo actualizar el trabajador. Revisa tu conexión e inténtalo de nuevo.',
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
      selectedIndex: 12,
      showBackButton: true, // <--- HABILITA LA FLECHA DE VOLVER
      title: 'Modificar Trabajador',
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 860;

                  final formColumn = _buildFormColumn();
                  final sideColumn = _buildSideColumn();

                  if (isWide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 2, child: formColumn),
                        const SizedBox(width: 24),
                        SizedBox(width: 340, child: sideColumn),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      formColumn,
                      const SizedBox(height: 24),
                      sideColumn,
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(Icons.edit_outlined, color: AppColors.textPrimary),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Edición de Trabajador',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  Text('Los cambios se guardan sobre el mismo registro existente.',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        FormSectionCard(
          icon: Icons.person_outline,
          title: 'Nombre y identificación',
          child: Column(
            children: [
              LabeledTextField(
                label: 'Nombre completo',
                controller: _nombreCtrl,
                hint: 'Ej: Juan Pérez González',
                icon: Icons.person_outline,
                validator: _validarNombre,
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: LabeledTextField(
                      label: 'RUT',
                      controller: _rutCtrl,
                      icon: Icons.badge_outlined,
                      readOnly: true,
                      helperText: 'El RUT no se puede modificar.',
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: LabeledTextField(
                      label: 'Fecha de nacimiento',
                      controller: _fechaCtrl,
                      hint: 'dd/mm/aaaa',
                      icon: Icons.calendar_today_outlined,
                      readOnly: true,
                      onTap: _seleccionarFecha,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        FormSectionCard(
          icon: Icons.mail_outline,
          title: 'Información de contacto',
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: LabeledTextField(
                      label: 'Correo electrónico',
                      controller: _correoCtrl,
                      hint: 'ejemplo@transcontreras.cl',
                      icon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                      validator: _validarCorreo,
                      helperText: 'Cambiarlo aquí no modifica las credenciales de inicio de sesión del trabajador.',
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: LabeledPhoneField(
                      label: 'Teléfono de contacto',
                      controller: _telefonoCtrl,
                      validator: _validarTelefono,
                    ),
                  ),
                ],
              ),
            ],
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
                label: Text(_guardando ? 'ACTUALIZANDO...' : 'ACTUALIZAR TRABAJADOR'),
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
    );
  }

  Widget _buildSideColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.infoBg,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.edit_outlined, size: 16, color: AppColors.primary),
              SizedBox(width: 6),
              Text('Editando registro existente',
                  style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              const CircleAvatar(
                radius: 36,
                backgroundColor: AppColors.surfaceMuted,
                child: Icon(Icons.person, size: 36, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              Text(
                widget.trabajador.nombreCompleto.toUpperCase(),
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              Text('RUT: ${widget.trabajador.rut}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FormSectionCard(
          icon: Icons.description_outlined,
          title: 'Documentación',
          subtitle: 'Opcional: solo si quieres reemplazarlos',
          child: Column(
            children: [
              _buildEstadoDocumentoActual(
                etiqueta: 'Carnet de identidad',
                cargado: widget.trabajador.urlCedulaIdentidad != null,
              ),
              const SizedBox(height: 8),
              DocumentUploadField(
                label: 'Reemplazar carnet de identidad',
                onFileSelected: (f) => setState(() => _carnetFile = f),
              ),
              const SizedBox(height: 16),
              _buildEstadoDocumentoActual(
                etiqueta: 'Licencia de conducir',
                cargado: widget.trabajador.urlLicenciaConducir != null,
              ),
              const SizedBox(height: 8),
              DocumentUploadField(
                label: 'Reemplazar licencia de conducir',
                onFileSelected: (f) => setState(() => _licenciaFile = f),
              ),
              const SizedBox(height: 12),
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 14, color: AppColors.textSecondary),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Si no seleccionas un archivo nuevo, el documento que ya tenía cargado el trabajador '
                      'se mantiene sin cambios.',
                      style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEstadoDocumentoActual({required String etiqueta, required bool cargado}) {
    return Row(
      children: [
        Icon(
          cargado ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 14,
          color: cargado ? AppColors.success : AppColors.textSecondary,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '$etiqueta: ${cargado ? 'ya cargado' : 'sin documento'}',
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }
}