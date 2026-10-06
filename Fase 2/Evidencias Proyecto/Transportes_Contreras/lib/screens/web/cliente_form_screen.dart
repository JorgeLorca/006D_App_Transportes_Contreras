import 'package:flutter/material.dart';

import '../../models/cliente.dart';
import '../../models/comuna.dart';
import '../../models/region.dart';
import '../../repositories/clientes_repository.dart';
import '../../repositories/repository_exception.dart';
import '../../repositories/ubicaciones_repository.dart';
import '../../theme/app_colors.dart';
import '../../utils/formato.dart';
import '../../widgets/admin_shell.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/form_section_card.dart';

/// Formulario de alta de un cliente (socio logístico) para el panel admin
/// web de Transportes Contreras.
///
/// Cada cliente define dos juegos de tarifas, uno por tipo de camión que se
/// le puede asignar a un viaje (camión simple o camión rampla); al asignar
/// el viaje se cobra el juego de tarifas que corresponda según el camión
/// usado.
///
/// Región y Comuna son tablas de referencia en Supabase
/// (`regiones`/`comunas`), igual que en Consignatario: se cargan
/// dinámicamente, las regiones al abrir el formulario y las comunas de la
/// región elegida cada vez que cambia el Dropdown de Región.
///
/// Al guardar, [ClientesRepository] inserta el cliente en la tabla `clientes`
/// de Supabase.
class ClienteFormScreen extends StatefulWidget {
  const ClienteFormScreen({super.key, this.onGuardar});

  /// Callback opcional que recibe el cliente guardado.
  final ValueChanged<Cliente>? onGuardar;

  @override
  State<ClienteFormScreen> createState() => _ClienteFormScreenState();
}

class _ClienteFormScreenState extends State<ClienteFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nombreEmpresaCtrl = TextEditingController();
  final _contactoCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();

  // Tarifas — camión simple.
  final _valorViajeCtrl = TextEditingController();
  final _tarifaNocturnaCtrl = TextEditingController();
  final _peonetaCtrl = TextEditingController();

  // Tarifas — camión rampla.
  final _valorViajeRamplaCtrl = TextEditingController();
  final _tarifaNocturnaRamplaCtrl = TextEditingController();
  final _peonetaRamplaCtrl = TextEditingController();

  final _repo = ClientesRepository();
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

  Future<void> _guardar() async {
    if (_guardando) return;
    if (!_formKey.currentState!.validate()) return;

    final cliente = Cliente(
      nombreEmpresa: _nombreEmpresaCtrl.text.trim(),
      nombreContacto: _contactoCtrl.text.trim(),
      telefono: '+56 ${_telefonoCtrl.text.trim()}',
      direccion: _direccionCtrl.text.trim(),
      comunaId: _selectedComunaId!,
      regionId: _selectedRegionId!,
      valorViajeCamion: double.parse(_valorViajeCtrl.text.trim()),
      tarifaNocturnaCamion: double.parse(_tarifaNocturnaCtrl.text.trim()),
      valorPeonetaCamion: double.parse(_peonetaCtrl.text.trim()),
      valorViajeRampla: double.parse(_valorViajeRamplaCtrl.text.trim()),
      tarifaNocturnaRampla: double.parse(_tarifaNocturnaRamplaCtrl.text.trim()),
      valorPeonetaRampla: double.parse(_peonetaRamplaCtrl.text.trim()),
    );

    // Nombres legibles para el resumen del diálogo (los ids no le dicen
    // nada al usuario).
    final regionNombre = _regiones
        .firstWhere((r) => r.id == _selectedRegionId, orElse: () => const Region(id: '', nombre: '—'))
        .nombre;
    final comunaNombre = _comunas
        .firstWhere((c) => c.id == _selectedComunaId, orElse: () => const Comuna(id: '', nombre: '—', regionId: ''))
        .nombre;

    final confirmado = await mostrarDialogoConfirmacion(
      context,
      titulo: 'Confirmar registro de cliente',
      mensaje: 'Revisa los datos antes de guardar. Estas tarifas se usarán para la liquidación de servicios '
          'según el tipo de camión que se asigne a cada viaje.',
      resumen: {
        'Empresa': cliente.nombreEmpresa,
        'Contacto': cliente.nombreContacto,
        'Teléfono': cliente.telefono,
        'Dirección': cliente.direccion,
        'Región': regionNombre,
        'Comuna': comunaNombre,
        'Viaje (camión simple)': formatearClp(cliente.valorViajeCamion),
        'Nocturna (camión simple)': formatearClp(cliente.tarifaNocturnaCamion),
        'Peoneta (camión simple)': formatearClp(cliente.valorPeonetaCamion),
        'Viaje (camión rampla)': formatearClp(cliente.valorViajeRampla),
        'Nocturna (camión rampla)': formatearClp(cliente.tarifaNocturnaRampla),
        'Peoneta (camión rampla)': formatearClp(cliente.valorPeonetaRampla),
      },
      icono: Icons.apartment_outlined,
    );
    if (!confirmado || !mounted) return;

    setState(() => _guardando = true);
    try {
      await _repo.crear(cliente);
      if (!mounted) return;
      widget.onGuardar?.call(cliente);
      _mostrarMensaje('Cliente "${cliente.nombreEmpresa}" creado correctamente', AppColors.success);
      _limpiarFormulario();
    } on RepositoryException catch (e) {
      if (!mounted) return;
      _mostrarMensaje(e.mensaje, Colors.red.shade700);
    } catch (_) {
      if (!mounted) return;
      _mostrarMensaje('No se pudo guardar el cliente. Revisa tu conexión e inténtalo de nuevo.',
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
    _nombreEmpresaCtrl.clear();
    _contactoCtrl.clear();
    _telefonoCtrl.clear();
    _direccionCtrl.clear();
    _valorViajeCtrl.clear();
    _tarifaNocturnaCtrl.clear();
    _peonetaCtrl.clear();
    _valorViajeRamplaCtrl.clear();
    _tarifaNocturnaRamplaCtrl.clear();
    _peonetaRamplaCtrl.clear();
    setState(() {
      _selectedRegionId = null;
      _selectedComunaId = null;
      _comunas = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      selectedIndex: 11,
      showBackButton: true, // <--- HABILITA LA FLECHA DE VOLVER
      title: 'Registro de Cliente',
      subtitle: 'Alta de nuevos socios logísticos en la plataforma',
      actions: [
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.close, size: 16),
          label: const Text('CANCELAR Y VOLVER'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            side: const BorderSide(color: AppColors.border),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        ElevatedButton.icon(
          onPressed: _guardando ? null : _guardar,
          icon: _guardando
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.save_outlined, size: 16),
          label: Text(_guardando ? 'GUARDANDO...' : 'GUARDAR REGISTRO'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 0.3),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ],
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
                  _buildAvisoSeguridad(),
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvisoSeguridad() {
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
            child: const Icon(Icons.verified_user_outlined, size: 18, color: AppColors.textPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Aviso de Seguridad',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary)),
                const SizedBox(height: 4),
                RichText(
                  text: const TextSpan(
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
                    children: [
                      TextSpan(text: 'Formulario de registro oficial para administración de '),
                      TextSpan(
                        text: 'Transportes Contreras',
                        style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                      ),
                      TextSpan(
                        text: '. Toda la información ingresada será auditada y se utilizará para la '
                            'liquidación automática de servicios.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
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

              // Región y Comuna en selects independientes, cargados desde
              // Supabase (misma lógica que en Consignatario).
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
                  'finalizar el registro.',
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

  /// Dos juegos de tarifas, uno por tipo de camión. Al asignar un viaje se
  /// cobra el juego que corresponda según el camión usado.
  Widget _buildTarifas() {
    return AccentHeaderCard(
      icon: Icons.attach_money,
      title: 'Configuración de Tarifas',
      description: 'Defina las tarifas para cada tipo de camión que se le puede asignar a este cliente. '
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

  /// Chip/etiqueta que separa visualmente el bloque de tarifas de cada tipo
  /// de camión dentro de la tarjeta de "Configuración de Tarifas".
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