import 'package:flutter/material.dart';

import '../../../models/comuna.dart';
import '../../../models/consignatario.dart';
import '../../../models/region.dart';
import '../../../repositories/consignatarios_repository.dart';
import '../../../repositories/repository_exception.dart';
import '../../../repositories/ubicaciones_repository.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/admin_shell.dart';
import '../../../widgets/confirm_dialog.dart';
import '../../../widgets/form_section_card.dart';

import '../../../utils/formato.dart';

/// Screen dedicada a **modificar** un consignatario ya existente.
class ConsignatarioModificarScreen extends StatefulWidget {
  const ConsignatarioModificarScreen({super.key, required this.consignatario, this.onActualizar});

  final Consignatario consignatario;
  final ValueChanged<Consignatario>? onActualizar;

  @override
  State<ConsignatarioModificarScreen> createState() => _ConsignatarioModificarScreenState();
}

class _ConsignatarioModificarScreenState extends State<ConsignatarioModificarScreen> {
  final _formKey = GlobalKey<FormState>();

  late final _nombreEmpresaCtrl = TextEditingController(text: widget.consignatario.nombreEmpresa);
  late final _direccionCtrl = TextEditingController(text: widget.consignatario.direccion);

  final _repo = ConsignatariosRepository();
  final _ubicacionesRepo = UbicacionesRepository();

  List<Region> _regiones = [];
  List<Comuna> _comunas = [];

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
      await _preseleccionarUbicacion();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cargandoRegiones = false;
        _errorRegiones = 'No se pudieron cargar las regiones. Revisa tu conexión e inténtalo de nuevo.';
      });
    }
  }

  Future<void> _preseleccionarUbicacion() async {
    final regionExiste = _regiones.any((r) => r.id == widget.consignatario.regionId);
    if (!regionExiste) return;

    setState(() => _selectedRegionId = widget.consignatario.regionId);
    await _cargarComunas(widget.consignatario.regionId);
    if (!mounted) return;

    final comunaExiste = _comunas.any((c) => c.id == widget.consignatario.comunaId);
    if (comunaExiste) {
      setState(() => _selectedComunaId = widget.consignatario.comunaId);
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
      _selectedComunaId = null;
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

  Future<void> _actualizar() async {
    if (_guardando) return;
    if (!_formKey.currentState!.validate()) return;

    final consignatarioActualizado = Consignatario(
      id: widget.consignatario.id,
      nombreEmpresa: capitalizarTexto(_nombreEmpresaCtrl.text),
      direccion: capitalizarTexto(_direccionCtrl.text),
      comunaId: _selectedComunaId!,
      regionId: _selectedRegionId!,
      creadoEn: widget.consignatario.creadoEn,
    );

    final regionNombre = _regiones
        .firstWhere((r) => r.id == _selectedRegionId, orElse: () => const Region(id: '', nombre: '—'))
        .nombre;
    final comunaNombre = _comunas
        .firstWhere((c) => c.id == _selectedComunaId, orElse: () => const Comuna(id: '', nombre: '—', regionId: ''))
        .nombre;

    final confirmado = await mostrarDialogoConfirmacion(
      context,
      titulo: 'Confirmar actualización de consignatario',
      mensaje: 'Revisa los datos antes de guardar los cambios.',
      resumen: {
        'Empresa': consignatarioActualizado.nombreEmpresa,
        'Dirección': consignatarioActualizado.direccion,
        'Región': regionNombre,
        'Comuna': comunaNombre,
      },
      icono: Icons.edit_outlined,
      textoConfirmar: 'CONFIRMAR Y ACTUALIZAR',
    );
    if (!confirmado || !mounted) return;

    setState(() => _guardando = true);
    try {
      await _repo.actualizar(consignatarioActualizado);
      if (!mounted) return;
      widget.onActualizar?.call(consignatarioActualizado);
      _mostrarMensaje(
        'Consignatario "${consignatarioActualizado.nombreEmpresa}" actualizado correctamente',
        AppColors.success,
      );
      Navigator.of(context).pop(true);
    } on RepositoryException catch (e) {
      if (!mounted) return;
      _mostrarMensaje(e.mensaje, Colors.red.shade700);
    } catch (_) {
      if (!mounted) return;
      _mostrarMensaje(
        'No se pudo actualizar el consignatario. Revisa tu conexión e inténtalo de nuevo.',
        Colors.red.shade700,
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final double anchoPantalla = MediaQuery.of(context).size.width;
    final bool esPantallaPequena = anchoPantalla < 750;

    return AdminShell(
      selectedIndex: 13,
      showBackButton: true, // Flecha estándar unificada
      title: 'Modificar Consignatario',
      subtitle: 'Actualice la información legal y de ubicación de la empresa receptora de la mercancía.',
      eyebrow: 'GESTIÓN DE CARGAS',
      eyebrowIcon: Icons.local_shipping_outlined,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: EdgeInsets.all(esPantallaPequena ? 16.0 : 24.0),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FormSectionCard(
                    icon: Icons.apartment_outlined,
                    title: 'Datos del Consignatario',
                    subtitle: 'Estás modificando un consignatario existente.',
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

                        // Región y Comuna responsivos
                        if (_errorRegiones == null)
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final bool esAncho = constraints.maxWidth > 550;

                              final campoRegion = LabeledDropdownField(
                                label: 'Región',
                                value: _selectedRegionId,
                                items: _regiones.map((r) => DropdownOption(r.id, r.nombre)).toList(),
                                icon: Icons.public_outlined,
                                hint: 'Selecciona región',
                                loading: _cargandoRegiones,
                                onChanged: _onRegionChanged,
                                validator: (v) => v == null ? 'Selecciona una región' : null,
                              );

                              final campoComuna = LabeledDropdownField(
                                label: 'Comuna',
                                value: _selectedComunaId,
                                items: _comunas.map((c) => DropdownOption(c.id, c.nombre)).toList(),
                                icon: Icons.location_on_outlined,
                                hint: _selectedRegionId == null ? 'Primero elige región' : 'Selecciona comuna',
                                enabled: _selectedRegionId != null,
                                loading: _cargandoComunas,
                                onChanged: (v) => setState(() => _selectedComunaId = v),
                                validator: (v) => v == null ? 'Selecciona una comuna' : null,
                              );

                              if (esAncho) {
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: campoRegion),
                                    const SizedBox(width: 16),
                                    Expanded(child: campoComuna),
                                  ],
                                );
                              }

                              return Column(
                                children: [
                                  campoRegion,
                                  const SizedBox(height: 16),
                                  campoComuna,
                                ],
                              );
                            },
                          ),

                        const SizedBox(height: 24),
                        const Divider(color: AppColors.border),
                        const SizedBox(height: 18),

                        // Botón de actualizar (sin botón redundante de volver)
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final bool esCelular = constraints.maxWidth < 450;
                            final botonActualizar = ElevatedButton.icon(
                              onPressed: _guardando ? null : _actualizar,
                              icon: _guardando
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.save_outlined, size: 16),
                              label: Text(_guardando ? 'ACTUALIZANDO...' : 'ACTUALIZAR CONSIGNATARIO'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                                textStyle: const TextStyle(fontWeight: FontWeight.w700),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            );

                            if (esCelular) {
                              return SizedBox(
                                width: double.infinity,
                                child: botonActualizar,
                              );
                            }

                            return Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                botonActualizar,
                              ],
                            );
                          },
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