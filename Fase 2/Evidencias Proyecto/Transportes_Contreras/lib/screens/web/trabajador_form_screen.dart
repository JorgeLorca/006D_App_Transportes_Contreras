import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/trabajador.dart';
import '../../repositories/repository_exception.dart';
import '../../repositories/trabajadores_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/admin_shell.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/document_upload_field.dart';
import '../../widgets/form_section_card.dart';

/// Formulario de alta de un trabajador (conductor) para el panel admin web
/// de Transportes Contreras.
///
/// Al guardar, [TrabajadoresRepository] inserta el trabajador en la tabla
/// `conductores` de Supabase. Por ahora SIN Auth: la contraseña se captura
/// en el formulario pero todavía no se envía a ningún lado. Los documentos
/// (carnet y licencia) se suben al bucket `documentos_identidad` y sus rutas
/// se guardan en la fila del trabajador.
class TrabajadorFormScreen extends StatefulWidget {
  const TrabajadorFormScreen({super.key, this.onGuardar});

  /// Callback opcional que recibe el trabajador guardado.
  final ValueChanged<Trabajador>? onGuardar;

  @override
  State<TrabajadorFormScreen> createState() => _TrabajadorFormScreenState();
}

class _TrabajadorFormScreenState extends State<TrabajadorFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nombreCtrl = TextEditingController();
  final _rutCtrl = TextEditingController();
  final _fechaCtrl = TextEditingController();
  final _correoCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();

  final _rutFocusNode = FocusNode();
  final _repo = TrabajadoresRepository();

  DateTime? _fechaNacimiento;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _carnetCargado = false;
  bool _licenciaCargada = false;
  XFile? _carnetFile;
  XFile? _licenciaFile;
  bool _guardando = false;
  int _formVersion = 0; // cambia al limpiar, para reiniciar los campos de documentos

  @override
  void initState() {
    super.initState();
    _rutFocusNode.addListener(_onRutFocusChange);
  }

  /// Mientras el campo tiene el foco se edita en "crudo" (solo dígitos y,
  /// opcionalmente, una "k" al final para el verificador; sin puntos ni
  /// guion) para no pelear con el cursor; al salir del campo se formatea
  /// completo, con puntos de miles en el cuerpo y el guion antes del
  /// verificador (ej: 212675883 -> 21.267.588-3, o 2348393k -> 2.348.393-K).
  void _onRutFocusChange() {
    if (_rutFocusNode.hasFocus) {
      final crudo = _rutCtrl.text.replaceAll(RegExp(r'[.-]'), '');
      _rutCtrl.value = TextEditingValue(
        text: crudo,
        selection: TextSelection.collapsed(offset: crudo.length),
      );
    } else {
      _formatearRut();
    }
  }

  void _formatearRut() {
    final limpio = _rutCtrl.text.replaceAll(RegExp(r'[^0-9kK]'), '');
    if (limpio.length < 2) return; // no alcanza para separar verificador
    final cuerpo = limpio.substring(0, limpio.length - 1);
    final verificador = limpio.substring(limpio.length - 1).toUpperCase();
    setState(() => _rutCtrl.text = '${_conPuntosDeMiles(cuerpo)}-$verificador');
  }

  /// Inserta puntos cada 3 dígitos contados desde la derecha (miles).
  /// Ej: "21267588" -> "21.267.588".
  String _conPuntosDeMiles(String digitos) {
    final invertido = digitos.split('').reversed.join();
    final bloques = <String>[];
    for (var i = 0; i < invertido.length; i += 3) {
      final fin = (i + 3 < invertido.length) ? i + 3 : invertido.length;
      bloques.add(invertido.substring(i, fin));
    }
    return bloques.join('.').split('').reversed.join();
  }

  @override
  void dispose() {
    _rutFocusNode.dispose();
    _nombreCtrl.dispose();
    _rutCtrl.dispose();
    _fechaCtrl.dispose();
    _correoCtrl.dispose();
    _telefonoCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  bool get _datosBasicosOk =>
      _nombreCtrl.text.trim().isNotEmpty &&
      _rutCtrl.text.trim().isNotEmpty &&
      _correoCtrl.text.trim().isNotEmpty;

  bool get _docsPendientes => !_carnetCargado || !_licenciaCargada;

  Future<void> _seleccionarFecha() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 25),
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
        _fechaCtrl.text = '${picked.day.toString().padLeft(2, '0')}/'
            '${picked.month.toString().padLeft(2, '0')}/${picked.year}';
      });
    }
  }

  String? _validarNombre(String? v) {
    if (v == null || v.trim().isEmpty) return 'Ingresa el nombre completo';
    if (v.trim().split(' ').length < 2) return 'Ingresa nombre y apellido';
    return null;
  }

  String? _validarRut(String? v) {
    if (v == null || v.trim().isEmpty) return 'Ingresa el RUT';
    // Formato esperado tras el auto-formateo: puntos de miles en el cuerpo
    // (7 u 8 dígitos) + "-" + dígito verificador (0-9 o K).
    final regex = RegExp(r'^\d{1,2}\.\d{3}\.\d{3}-[\dkK]$');
    if (!regex.hasMatch(v.trim())) return 'Formato inválido (ej: 21.267.588-3 o 2.348.393-K)';
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

  String? _validarPassword(String? v) {
    if (v == null || v.isEmpty) return 'Ingresa una contraseña';
    if (v.length < 8) return 'Mínimo 8 caracteres';
    return null;
  }

  String? _validarConfirmPassword(String? v) {
    if (v != _passwordCtrl.text) return 'Las contraseñas no coinciden';
    return null;
  }

 Future<void> _guardar() async {
    if (_guardando) return;
    if (!_formKey.currentState!.validate()) return;

    final confirmado = await mostrarDialogoConfirmacion(
      context,
      titulo: 'Confirmar registro de trabajador',
      mensaje: 'Revisa los datos antes de guardar.',
      resumen: {
        'Nombre': _nombreCtrl.text.trim(),
        'RUT': _rutCtrl.text.trim(),
        'Fecha de nacimiento': _fechaCtrl.text,
        'Correo': _correoCtrl.text.trim(),
        'Teléfono': '+56 ${_telefonoCtrl.text.trim()}',
        'Carnet': _carnetFile != null ? 'Adjunto' : 'Sin adjuntar',
        'Licencia': _licenciaFile != null ? 'Adjunta' : 'Sin adjuntar',
      },
      icono: Icons.badge_outlined,
    );
    if (!confirmado || !mounted) return;

    setState(() => _guardando = true);
    
    try {
      // 1. Llamamos a la Edge Function para crear las credenciales
      // 1. Llamamos a la Edge Function
final authResponse = await Supabase.instance.client.functions.invoke(
  'crear_conductor',
  body: {
    'email': _correoCtrl.text.trim(),
    'password': _passwordCtrl.text,
  },
);

// 2. Extraemos el UUID de forma segura casteando la respuesta
final responseData = authResponse.data as Map<String, dynamic>;
final String? authId = responseData['auth_id'];

// 3. Construimos el modelo (asegúrate de que el nombre del parámetro sea 'authId' como en tu modelo)
final trabajador = Trabajador(
  authId: authId, // Aquí se lo pasamos al modelo
  nombreCompleto: _nombreCtrl.text.trim(),
  rut: _rutCtrl.text.trim(),
  fechaNacimiento: _fechaNacimiento,
  correo: _correoCtrl.text.trim(),
  telefono: '+56 ${_telefonoCtrl.text.trim()}',
);

      // 3. Tu repositorio sigue haciendo el trabajo pesado (INSERT en tabla y subida de archivos)
      await _repo.crear(trabajador, carnet: _carnetFile, licencia: _licenciaFile);
      
      if (!mounted) return;
      widget.onGuardar?.call(trabajador);
      _mostrarMensaje('Trabajador "${trabajador.nombreCompleto}" creado correctamente', AppColors.success);
      _limpiarFormulario();
      
    } on FunctionException catch (e) {
      if (!mounted) return;
      _mostrarMensaje('Error al crear credenciales de Auth: ${e.reasonPhrase}', Colors.red.shade700);
    } on RepositoryException catch (e) {
      if (!mounted) return;
      _mostrarMensaje(e.mensaje, Colors.red.shade700);
    } catch (_) {
      if (!mounted) return;
      _mostrarMensaje('No se pudo guardar el trabajador. Revisa tu conexión e inténtalo de nuevo.',
          Colors.red.shade700);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
}

  void _mostrarMensaje(String texto, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(texto), backgroundColor: color),
    );
  }

  void _limpiarFormulario() {
    _formKey.currentState?.reset();
    _nombreCtrl.clear();
    _rutCtrl.clear();
    _fechaCtrl.clear();
    _correoCtrl.clear();
    _telefonoCtrl.clear();
    _passwordCtrl.clear();
    _confirmPasswordCtrl.clear();
    setState(() {
      _fechaNacimiento = null;
      _carnetCargado = false;
      _licenciaCargada = false;
      _carnetFile = null;
      _licenciaFile = null;
      _formVersion++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      selectedIndex: 12,
      showBackButton: true, // <--- HABILITA LA FLECHA DE VOLVER
      title: 'Registro de Trabajador',
      child: Form(
        key: _formKey,
        onChanged: () => setState(() {}),
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
              child: const Icon(Icons.badge_outlined, color: AppColors.textPrimary),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Datos del Personal',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  Text('Complete todos los campos requeridos para el alta en el sistema.',
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
                      focusNode: _rutFocusNode,
                      hint: 'Ej: 21.267.588-3',
                      icon: Icons.badge_outlined,
                      keyboardType: TextInputType.text,
                      validator: _validarRut,
                      maxLength: 9, // 8 dígitos del cuerpo + 1 verificador
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9kK]'))],
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
                      helperText: 'Se utilizará para iniciar sesión en la plataforma.',
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
        const SizedBox(height: 20),
        FormSectionCard(
          icon: Icons.fingerprint,
          title: 'Acceso a la app',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.infoBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.infoBorder),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: Colors.blueAccent),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Estas credenciales permitirán al trabajador iniciar sesión en la aplicación móvil de Transportes Contreras.',
                        style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: LabeledTextField(
                      label: 'Contraseña',
                      controller: _passwordCtrl,
                      icon: Icons.lock_outline,
                      obscureText: _obscurePassword,
                      validator: _validarPassword,
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            size: 18),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: LabeledTextField(
                      label: 'Confirmar contraseña',
                      controller: _confirmPasswordCtrl,
                      icon: Icons.lock_outline,
                      obscureText: _obscureConfirm,
                      validator: _validarConfirmPassword,
                      suffixIcon: IconButton(
                        icon: Icon(_obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            size: 18),
                        onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                      ),
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
                onPressed: _guardando ? null : _guardar,
                icon: _guardando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save_outlined, size: 18),
                label: Text(_guardando ? 'GUARDANDO...' : 'GUARDAR REGISTRO'),
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
            color: AppColors.successBg,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.verified_user_outlined, size: 16, color: AppColors.success),
              SizedBox(width: 6),
              Text('Formulario de Seguridad Verificado',
                  style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w600, fontSize: 12)),
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
                _nombreCtrl.text.trim().isEmpty ? 'NUEVO TRABAJADOR' : _nombreCtrl.text.trim().toUpperCase(),
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              const Text('ID Pendiente', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              const SizedBox(height: 12),
              const Divider(color: AppColors.border),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _EstadoChip(
                    icon: _datosBasicosOk ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: _datosBasicosOk ? AppColors.success : AppColors.textSecondary,
                    label: 'Datos OK',
                  ),
                  _EstadoChip(
                    icon: Icons.error_outline,
                    color: _docsPendientes ? AppColors.warning : AppColors.success,
                    label: _docsPendientes ? 'Docs Pendientes' : 'Docs OK',
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FormSectionCard(
          icon: Icons.description_outlined,
          title: 'Documentación',
          child: Column(
            children: [
              DocumentUploadField(
                key: ValueKey('carnet-$_formVersion'),
                label: 'Carnet de identidad',
                onFileSelected: (f) => setState(() {
                  _carnetFile = f;
                  _carnetCargado = true;
                }),
              ),
              const SizedBox(height: 16),
              DocumentUploadField(
                key: ValueKey('licencia-$_formVersion'),
                label: 'Licencia de conducir',
                onFileSelected: (f) => setState(() {
                  _licenciaFile = f;
                  _licenciaCargada = true;
                }),
              ),
              const SizedBox(height: 12),
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 14, color: AppColors.textSecondary),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'La revisión de documentos será realizada por el departamento de recursos humanos en un plazo de 24hs hábiles.',
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
}

class _EstadoChip extends StatelessWidget {
  const _EstadoChip({required this.icon, required this.color, required this.label});

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
      ],
    );
  }
}