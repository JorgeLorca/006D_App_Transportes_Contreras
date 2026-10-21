import 'package:flutter/material.dart';

import '../../../models/cliente.dart';
import '../../../models/comuna.dart';
import '../../../models/region.dart';
import '../../../repositories/clientes_repository.dart';
import '../../../repositories/repository_exception.dart';
import '../../../repositories/ubicaciones_repository.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/formato.dart';
import '../../../widgets/admin_shell.dart';
import '../../../widgets/confirm_dialog.dart';
import '../../../widgets/form_section_card.dart';

/// Screen dedicada a **modificar** un cliente ya existente (socio
/// logístico) del panel admin web de Transportes Contreras.
class ClienteModificarScreen extends StatefulWidget {
  const ClienteModificarScreen({super.key, required this.cliente, this.onActualizar});

  final Cliente cliente;
  final ValueChanged<Cliente>? onActualizar;

  @override
  State<ClienteModificarScreen> createState() => _ClienteModificarScreenState();
}

class _ClienteModificarScreenState extends State<ClienteModificarScreen> {
  final _formKey = GlobalKey<FormState>();

  late final _nombreEmpresaCtrl =
      TextEditingController(text: widget.cliente.nombreEmpresa);
  late final _contactoCtrl =
      TextEditingController(text: widget.cliente.nombreContacto);
  late final _telefonoCtrl =
      TextEditingController(text: widget.cliente.telefono.replaceFirst('+56 ', '').trim());
  late final _direccionCtrl =
      TextEditingController(text: widget.cliente.direccion);

  // Tarifas — camión simple.
  late final _valorViajeCtrl =
      TextEditingController(text: _numeroParaCampo(widget.cliente.valorViajeCamion));
  late final _tarifaNocturnaCtrl =
      TextEditingController(text: _numeroParaCampo(widget.cliente.tarifaNocturnaCamion));
  late final _peonetaCtrl =
      TextEditingController(text: _numeroParaCampo(widget.cliente.valorPeonetaCamion));

  // Tarifas — camión rampla.
  late final _valorViajeRamplaCtrl =
      TextEditingController(text: _numeroParaCampo(widget.cliente.valorViajeRampla));
  late final _tarifaNocturnaRamplaCtrl =
      TextEditingController(text: _numeroParaCampo(widget.cliente.tarifaNocturnaRampla));
  late final _peonetaRamplaCtrl =
      TextEditingController(text: _numeroParaCampo(widget.cliente.valorPeonetaRampla));

  final _repo = ClientesRepository();
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
    _contactoCtrl.dispose();
    _telefonoCtrl.dispose();
    _direccionCtrl.dispose();
    _valorViajeCtrl.dispose();
    _tarifaNocturnaCtrl.dispose();
    _peonetaCtrl.dispose();
    _valorViajeRamplaCtrl.dispose();
    _tarifaNocturnaRamplaCtrl.dispose();
    _peonetaRamplaCtrl.dispose();
    super.dispose();
  }

  static String _numeroParaCampo(double valor) {
    return valor == valor.roundToDouble() ? valor.toStringAsFixed(0) : valor.toString();
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
    final regionExiste = _regiones.any((r) => r.id == widget.cliente.regionId);
    if (!regionExiste) return;

    setState(() => _selectedRegionId = widget.cliente.regionId);
    await _cargarComunas(widget.cliente.regionId);
    if (!mounted) return;

    final comunaExiste = _comunas.any((c) => c.id == widget.cliente.comunaId);
    if (comunaExiste) {
      setState(() => _selectedComunaId = widget.cliente.comunaId);
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

  String? _validarTelefono(String? v) {
    if (v == null || v.trim().isEmpty) return 'Ingresa el teléfono de contacto';
    if (v.trim().length != 9) return 'Debe tener 9 dígitos';
    return null;
  }

  String? _validarMonto(String? v) {
    if (v == null || v.trim().isEmpty) return 'Ingresa un monto';
    final monto = double.tryParse(v.trim());
    if (monto == null || monto < 0) return 'Monto inválido';
    return null;
  }

  Future<void> _actualizar() async {
    if (_guardando) return;
    if (!_formKey.currentState!.validate()) return;

    final clienteActualizado = Cliente(
      id: widget.cliente.id,
      nombreEmpresa: capitalizarTexto(_nombreEmpresaCtrl.text),
      nombreContacto: capitalizarTexto(_contactoCtrl.text),
      telefono: '+56 ${_telefonoCtrl.text.trim()}',
      direccion: capitalizarTexto(_direccionCtrl.text),
      comunaId: _selectedComunaId!,
      regionId: _selectedRegionId!,
      valorViajeCamion: double.parse(_valorViajeCtrl.text.trim()),
      tarifaNocturnaCamion: double.parse(_tarifaNocturnaCtrl.text.trim()),
      valorPeonetaCamion: double.parse(_peonetaCtrl.text.trim()),
      valorViajeRampla: double.parse(_valorViajeRamplaCtrl.text.trim()),
      tarifaNocturnaRampla: double.parse(_tarifaNocturnaRamplaCtrl.text.trim()),
      valorPeonetaRampla: double.parse(_peonetaRamplaCtrl.text.trim()),
    );

    final regionNombre = _regiones
        .firstWhere((r) => r.id == _selectedRegionId, orElse: () => const Region(id: '', nombre: '—'))
        .nombre;
    final comunaNombre = _comunas
        .firstWhere((c) => c.id == _selectedComunaId, orElse: () => const Comuna(id: '', nombre: '—', regionId: ''))
        .nombre;

    final confirmado = await mostrarDialogoConfirmacion(
      context,
      titulo: 'Confirmar actualización de cliente',
      mensaje: 'Revisa los datos antes de guardar los cambios. Estas tarifas se usarán para la liquidación '
          'de servicios según el tipo de camión que se asigne a cada viaje.',
      resumen: {
        'Empresa': clienteActualizado.nombreEmpresa,
        'Contacto': clienteActualizado.nombreContacto,
        'Teléfono': clienteActualizado.telefono,
        'Dirección': clienteActualizado.direccion,
        'Región': regionNombre,
        'Comuna': comunaNombre,
        'Viaje (camión simple)': formatearClp(clienteActualizado.valorViajeCamion),
        'Nocturna (camión simple)': formatearClp(clienteActualizado.tarifaNocturnaCamion),
        'Peoneta (camión simple)': formatearClp(clienteActualizado.valorPeonetaCamion),
        'Viaje (camión rampla)': formatearClp(clienteActualizado.valorViajeRampla),
        'Nocturna (camión rampla)': formatearClp(clienteActualizado.tarifaNocturnaRampla),
        'Peoneta (camión rampla)': formatearClp(clienteActualizado.valorPeonetaRampla),
      },
      icono: Icons.edit_outlined,
      textoConfirmar: 'CONFIRMAR Y ACTUALIZAR',
    );
    if (!confirmado || !mounted) return;

    setState(() => _guardando = true);
    try {
      await _repo.actualizar(clienteActualizado);
      if (!mounted) return;
      widget.onActualizar?.call(clienteActualizado);
      _mostrarMensaje(
        'Cliente "${clienteActualizado.nombreEmpresa}" actualizado correctamente',
        AppColors.success,
      );
      Navigator.of(context).pop(true);
    } on RepositoryException catch (e) {
      if (!mounted) return;
      _mostrarMensaje(e.mensaje, Colors.red.shade700);
    } catch (_) {
      if (!mounted) return;
      _mostrarMensaje(
        'No se pudo actualizar el cliente. Revisa tu conexión e inténtalo de nuevo.',
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

  Widget _buildBotonActualizar({bool expandido = false}) {
    final boton = ElevatedButton.icon(
      onPressed: _guardando ? null : _actualizar,
      icon: _guardando
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : const Icon(Icons.save_outlined, size: 16),
      label: Text(_guardando ? 'ACTUALIZANDO...' : 'ACTUALIZAR CLIENTE'),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 0.3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );

    if (expandido) {
      return SizedBox(
        width: double.infinity,
        child: boton,
      );
    }
    return boton;
  }

  @override
  Widget build(BuildContext context) {
    final double anchoPantalla = MediaQuery.of(context).size.width;
    final bool esPantallaPequena = anchoPantalla < 750;

    return AdminShell(
      selectedIndex: 11,
      showBackButton: true,
      title: 'Modificar Cliente',
      subtitle: 'Actualice la información del socio logístico.',
      // En celular se oculta de la barra superior para no tapar los títulos
      actions: esPantallaPequena ? null : [_buildBotonActualizar(expandido: false)],
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: EdgeInsets.all(esPantallaPequena ? 16.0 : 24.0),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildAvisoEdicion(esPantallaPequena),
                  const SizedBox(height: 20),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth > 860;

                      final datosGenerales = _buildDatosGenerales();
                      final tarifas = _buildTarifas();

                      if (isWide) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 3, child: datosGenerales),
                            const SizedBox(width: 20),
                            Expanded(flex: 2, child: tarifas),
                          ],
                        );
                      }
                      return Column(
                        children: [
                          datosGenerales,
                          const SizedBox(height: 20),
                          tarifas,
                        ],
                      );
                    },
                  ),

                  // Botón ACTUALIZAR al final de la pantalla para celulares
                  if (esPantallaPequena) ...[
                    const SizedBox(height: 24),
                    _buildBotonActualizar(expandido: true),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvisoEdicion(bool esPantallaPequena) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.infoBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.infoBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(8)),
            alignment: Alignment.center,
            child: const Icon(Icons.edit_outlined, size: 18, color: AppColors.textPrimary),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Edición de Registro',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary)),
                SizedBox(height: 4),
                Text(
                  'Estás modificando un cliente existente. Los cambios se guardan sobre el mismo '
                  'registro y se reflejarán de inmediato en las liquidaciones futuras.',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
                ),
              ],
            ),
          ),
          if (!esPantallaPequena) ...[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.infoBorder),
              ),
              child: const Text('Versión Web 4.0',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDatosGenerales() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AccentHeaderCard(
          icon: Icons.apartment_outlined,
          title: 'Datos Generales',
          description: 'Información legal, de contacto y ubicación de la organización.',
          child: Column(
            children: [
              LabeledTextField(
                label: 'Nombre empresa / razón social',
                controller: _nombreEmpresaCtrl,
                hint: 'Ej: Logística Continental S.A.',
                icon: Icons.apartment_outlined,
                validator: (v) => _requerido(v, 'Ingresa el nombre de la empresa'),
              ),
              const SizedBox(height: 16),
              LabeledTextField(
                label: 'Contacto (persona responsable)',
                controller: _contactoCtrl,
                hint: 'Ej: Juan Pérez',
                icon: Icons.person_outline,
                validator: (v) => _requerido(v, 'Ingresa el contacto responsable'),
              ),
              const SizedBox(height: 16),
              LabeledPhoneField(
                label: 'Teléfono de contacto',
                controller: _telefonoCtrl,
                validator: _validarTelefono,
              ),
              const SizedBox(height: 16),
              LabeledTextField(
                label: 'Dirección legal / operativa',
                controller: _direccionCtrl,
                hint: 'Calle, Número',
                icon: Icons.location_on_outlined,
                validator: (v) => _requerido(v, 'Ingresa la dirección'),
              ),
              const SizedBox(height: 16),

              if (_errorRegiones != null) _buildErrorRegiones(),

              // Región y Comuna: 2 columnas en PC y 1 columna por fila en móvil
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
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 16, color: AppColors.textSecondary),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Los valores ingresados se utilizarán como base para la liquidación de servicios '
                  'automáticos. Asegúrese de verificar las tarifas contractuales vigentes antes de '
                  'guardar los cambios.',
                  style: TextStyle(fontSize: 12.5, fontStyle: FontStyle.italic, color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ],
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

  Widget _buildTarifas() {
    return AccentHeaderCard(
      icon: Icons.attach_money,
      title: 'Configuración de Tarifas',
      description: 'Ajuste las tarifas para cada tipo de camión que se le puede asignar a este cliente. '
          'El viaje se cobra con el juego de tarifas que corresponda al camión usado.',
      child: Column(
        children: [
          _buildEtiquetaTipoCamion(
            icono: Icons.local_shipping_outlined,
            texto: 'Camión simple',
          ),
          const SizedBox(height: 14),
          LabeledCurrencyField(
            label: 'Valor viaje estándar (CLP)',
            controller: _valorViajeCtrl,
            prefixIcon: Icons.local_shipping_outlined,
            validator: _validarMonto,
          ),
          const SizedBox(height: 16),
          LabeledCurrencyField(
            label: 'Tarifa nocturna / recargo (CLP)',
            controller: _tarifaNocturnaCtrl,
            prefixIcon: Icons.nightlight_outlined,
            validator: _validarMonto,
          ),
          const SizedBox(height: 16),
          LabeledCurrencyField(
            label: 'Peoneta (CLP)',
            controller: _peonetaCtrl,
            prefixIcon: Icons.groups_outlined,
            validator: _validarMonto,
          ),
          const SizedBox(height: 22),
          const Divider(color: AppColors.border),
          const SizedBox(height: 18),
          _buildEtiquetaTipoCamion(
            icono: Icons.rv_hookup_outlined,
            texto: 'Camión rampla',
          ),
          const SizedBox(height: 14),
          LabeledCurrencyField(
            label: 'Valor viaje rampla (CLP)',
            controller: _valorViajeRamplaCtrl,
            prefixIcon: Icons.local_shipping_outlined,
            validator: _validarMonto,
          ),
          const SizedBox(height: 16),
          LabeledCurrencyField(
            label: 'Tarifa nocturna rampla (CLP)',
            controller: _tarifaNocturnaRamplaCtrl,
            prefixIcon: Icons.nightlight_outlined,
            validator: _validarMonto,
          ),
          const SizedBox(height: 16),
          LabeledCurrencyField(
            label: 'Peoneta rampla (CLP)',
            controller: _peonetaRamplaCtrl,
            prefixIcon: Icons.groups_outlined,
            validator: _validarMonto,
          ),
        ],
      ),
    );
  }

  Widget _buildEtiquetaTipoCamion({required IconData icono, required String texto}) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 14, color: AppColors.textPrimary),
            const SizedBox(width: 6),
            Text(
              texto.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}