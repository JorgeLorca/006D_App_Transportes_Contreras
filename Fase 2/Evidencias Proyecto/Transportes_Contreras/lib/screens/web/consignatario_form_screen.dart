import 'package:flutter/material.dart';

import '../../models/comuna.dart';
import '../../models/consignatario.dart';
import '../../models/region.dart';
import '../../repositories/consignatarios_repository.dart';
import '../../repositories/repository_exception.dart';
import '../../repositories/ubicaciones_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/admin_shell.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/form_section_card.dart';

/// Formulario de alta de un consignatario (empresa receptora de la
/// mercancía) para el panel admin web de Transportes Contreras.
///
/// Región y Comuna ahora son tablas de referencia en Supabase
/// (`regiones`/`comunas`), así que se cargan dinámicamente: las regiones al
/// abrir el formulario, y las comunas de la región elegida cada vez que
/// cambia el Dropdown de Región.
///
/// Al guardar, [ConsignatariosRepository] inserta el consignatario en la
/// tabla `consignatarios` de Supabase (con `region_id`/`comuna_id`).
class ConsignatarioFormScreen extends StatefulWidget {
  const ConsignatarioFormScreen({super.key, this.onGuardar});

  final ValueChanged<Consignatario>? onGuardar;

  @override
  State<ConsignatarioFormScreen> createState() => _ConsignatarioFormScreenState();
}

class _ConsignatarioFormScreenState extends State<ConsignatarioFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nombreEmpresaCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();

  final _repo = ConsignatariosRepository();
  final _ubicacionesRepo = UbicacionesRepository();

  // Datos cargados desde Supabase.
  List<Region> _regiones = [];
  List<Comuna> _comunas = [];

  // Valores seleccionados de los Dropdowns (ids, no texto).
  String? _selectedRegionId;
  String? _selectedComunaId;

  bool _cargandoRegiones = true;
  bool _cargandoComunas = false;
  String? _errorRegiones;

  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargarRegiones();
  }

  @override
  void dispose() {
    _nombreEmpresaCtrl.dispose();
    _direccionCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarRegiones() async {
    setState(() {
      _cargandoRegiones = true;
      _errorRegiones = null;
    });
    try {
      final regiones = await _ubicacionesRepo.obtenerRegiones();
      if (!mounted) return;
      setState(() {
        _regiones = regiones;
        _cargandoRegiones = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cargandoRegiones = false;
        _errorRegiones = 'No se pudieron cargar las regiones. Revisa tu conexión e inténtalo de nuevo.';
      });
    }
  }

  Future<void> _cargarComunas(String regionId) async {
    setState(() => _cargandoComunas = true);
    try {
      final comunas = await _ubicacionesRepo.obtenerComunasPorRegion(regionId);
      if (!mounted) return;
      setState(() {
        _comunas = comunas;
        _cargandoComunas = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cargandoComunas = false);
      _mostrarMensaje('No se pudieron cargar las comunas de esa región.', Colors.red.shade700);
    }
  }

  void _onRegionChanged(String? regionId) {
    setState(() {
      _selectedRegionId = regionId;
      _selectedComunaId = null; // Resetea la comuna al cambiar de región
      _comunas = [];
    });
    if (regionId != null) _cargarComunas(regionId);
  }

  String? _requerido(String? v, String mensaje) {
    if (v == null || v.trim().isEmpty) return mensaje;
    return null;
  }

  void _mostrarMensaje(String texto, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(texto), backgroundColor: color),
    );
  }

  void _limpiarFormulario() {
    _formKey.currentState?.reset();
    _nombreEmpresaCtrl.clear();
    _direccionCtrl.clear();
    setState(() {
      _selectedRegionId = null;
      _selectedComunaId = null;
      _comunas = [];
    });
  }

  Future<void> _guardar() async {
    if (_guardando) return;
    if (!_formKey.currentState!.validate()) return;

    final consignatario = Consignatario(
      nombreEmpresa: _nombreEmpresaCtrl.text.trim(),
      direccion: _direccionCtrl.text.trim(),
      comunaId: _selectedComunaId!,
      regionId: _selectedRegionId!,
    );

    // Nombres legibles para el resumen del diálogo (los ids no le dicen
    // nada al usuario).
    final regionNombre = _regiones
        .firstWhere((r) => r.id == _selectedRegionId, orElse: () => const Region(id: '', nombre: '—'))
        .nombre;
    final comunaNombre = _comunas
        .firstWhere((c) => c.id == _selectedComunaId, orElse: () => const Comuna(id: '', nombre: '—', regionId: ''))
        .nombre;

    // Diálogo de confirmación consistente con Cliente y Trabajador
    final confirmado = await mostrarDialogoConfirmacion(
      context,
      titulo: 'Confirmar Registro de Consignatario',
      mensaje: 'Revisa los datos antes de guardar.',
      resumen: {
        'Empresa': consignatario.nombreEmpresa,
        'Dirección': consignatario.direccion,
        'Región': regionNombre,
        'Comuna': comunaNombre,
      },
      icono: Icons.apartment_outlined,
    );

    if (!confirmado || !mounted) return;

    setState(() => _guardando = true);
    try {
      await _repo.crear(consignatario);
      if (!mounted) return;
      widget.onGuardar?.call(consignatario);
      _mostrarMensaje(
        'Consignatario "${consignatario.nombreEmpresa}" guardado correctamente',
        AppColors.success,
      );
      _limpiarFormulario();
    } on RepositoryException catch (e) {
      if (!mounted) return;
      _mostrarMensaje(e.mensaje, Colors.red.shade700);
    } catch (_) {
      if (!mounted) return;
      _mostrarMensaje(
        'No se pudo guardar el consignatario. Revisa tu conexión e inténtalo de nuevo.',
        Colors.red.shade700,
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      selectedIndex: 1, // "Cargas" en kAdminMenuItems
      title: 'Formulario de Consignatario',
      subtitle: 'Ingrese la información legal y de ubicación de la empresa receptora de la mercancía.',
      eyebrow: 'GESTIÓN DE CARGAS',
      eyebrowIcon: Icons.local_shipping_outlined,
      actions: [
        TextButton.icon(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back, size: 15),
          label: const Text('Volver al listado'),
          style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
        ),
      ],
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FormSectionCard(
                  icon: Icons.apartment_outlined,
                  title: 'Datos del Consignatario',
                  subtitle: 'Campos obligatorios para la emisión del manifiesto de carga.',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LabeledTextField(
                        label: 'Nombre empresa',
                        controller: _nombreEmpresaCtrl,
                        hint: 'Ej: Distribuidora Nacional de Alimentos S.A.',
                        icon: Icons.apartment_outlined,
                        validator: (v) => _requerido(v, 'Ingresa el nombre de la empresa'),
                      ),
                      const SizedBox(height: 16),
                      LabeledTextField(
                        label: 'Dirección (Calle y Número)',
                        controller: _direccionCtrl,
                        hint: 'Ej: Av. Américo Vespucio 1234, Of. 201',
                        icon: Icons.location_on_outlined,
                        validator: (v) => _requerido(v, 'Ingresa la dirección'),
                      ),
                      const SizedBox(height: 16),

                      if (_errorRegiones != null) _buildErrorRegiones(),

                      // Región y Comuna en selects independientes, cargados
                      // desde Supabase.
                      if (_errorRegiones == null)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: LabeledDropdownField(
                                label: 'Región',
                                value: _selectedRegionId,
                                items: _regiones.map((r) => DropdownOption(r.id, r.nombre)).toList(),
                                icon: Icons.public_outlined,
                                hint: 'Selecciona región',
                                loading: _cargandoRegiones,
                                onChanged: _onRegionChanged,
                                validator: (v) => v == null ? 'Selecciona una región' : null,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: LabeledDropdownField(
                                label: 'Comuna',
                                value: _selectedComunaId,
                                items: _comunas.map((c) => DropdownOption(c.id, c.nombre)).toList(),
                                icon: Icons.location_on_outlined,
                                hint: _selectedRegionId == null ? 'Primero elige región' : 'Selecciona comuna',
                                enabled: _selectedRegionId != null,
                                loading: _cargandoComunas,
                                onChanged: (v) => setState(() => _selectedComunaId = v),
                                validator: (v) => v == null ? 'Selecciona una comuna' : null,
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 20),
                      const Divider(color: AppColors.border),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _guardando ? null : () => Navigator.of(context).maybePop(),
                            icon: const Icon(Icons.close, size: 16),
                            label: const Text('Cancelar/Volver'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.textPrimary,
                              side: const BorderSide(color: AppColors.border),
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: _guardando ? null : _guardar,
                            icon: _guardando
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.save_outlined, size: 16),
                            label: Text(_guardando ? 'GUARDANDO...' : 'GUARDAR'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                              textStyle: const TextStyle(fontWeight: FontWeight.w700),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.apartment_outlined, size: 18, color: AppColors.textSecondary),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Asegúrese de que el nombre de la empresa coincida exactamente con la razón '
                          'social registrada ante el Servicio de Impuestos Internos (SII) para evitar '
                          'demoras en los procesos de despacho y recepción.',
                          style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorRegiones() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(_errorRegiones!, style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
          ),
          TextButton(
            onPressed: _cargandoRegiones ? null : _cargarRegiones,
            child: const Text('REINTENTAR'),
          ),
        ],
      ),
    );
  }

}