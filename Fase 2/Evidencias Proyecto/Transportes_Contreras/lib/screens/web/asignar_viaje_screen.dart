import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/opcion_viaje.dart';
import '../../models/region.dart';
import '../../models/viaje.dart';
import '../../repositories/camiones_repository.dart';
import '../../repositories/clientes_repository.dart';
import '../../repositories/consignatarios_repository.dart';
import '../../repositories/repository_exception.dart';
import '../../repositories/trabajadores_repository.dart';
import '../../repositories/ubicaciones_repository.dart';
import '../../repositories/viajes_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/admin_shell.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/form_section_card.dart';

/// Formulario de asignación de un viaje a un conductor para el panel admin
/// web de Transportes Contreras.
class AsignarViajeScreen extends StatefulWidget {
  const AsignarViajeScreen({super.key, this.onAsignar});

  final ValueChanged<Viaje>? onAsignar;

  @override
  State<AsignarViajeScreen> createState() => _AsignarViajeScreenState();
}

class _AsignarViajeScreenState extends State<AsignarViajeScreen> {
  final _formKey = GlobalKey<FormState>();

  final _palletsCtrl = TextEditingController();
  final _direccionOrigenCtrl = TextEditingController();
  final _direccionDestinoCtrl = TextEditingController();
  final _fechaCtrl = TextEditingController();
  final _horaCargaCtrl = TextEditingController();
  final _horaDescargaCtrl = TextEditingController();
  final _observacionesCtrl = TextEditingController();

  DateTime? _fechaProgramada;
  TimeOfDay? _horaCarga;
  TimeOfDay? _horaDescarga;

  // Valores seleccionados (ids; en conductor, el RUT).
  String? _clienteId;
  String? _consignatarioId;
  String? _regionId;
  String? _conductorRut;
  String? _camionId;

  final _clientesRepo = ClientesRepository();
  final _consignatariosRepo = ConsignatariosRepository();
  final _trabajadoresRepo = TrabajadoresRepository();
  final _camionesRepo = CamionesRepository();
  final _ubicacionesRepo = UbicacionesRepository();
  final _viajesRepo = ViajesRepository();

  List<OpcionViaje> _clientes = [];
  List<OpcionViaje> _consignatarios = [];
  List<OpcionViaje> _conductores = [];
  List<OpcionViaje> _camiones = [];
  List<Region> _regiones = [];

  bool _cargandoOpciones = true;
  String? _errorOpciones;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargarOpciones();
  }

  @override
  void dispose() {
    _palletsCtrl.dispose();
    _direccionOrigenCtrl.dispose();
    _direccionDestinoCtrl.dispose();
    _fechaCtrl.dispose();
    _horaCargaCtrl.dispose();
    _horaDescargaCtrl.dispose();
    _observacionesCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarOpciones() async {
    setState(() {
      _cargandoOpciones = true;
      _errorOpciones = null;
    });
    try {
      final resultados = await Future.wait<dynamic>([
        _clientesRepo.obtenerOpcionesViaje(),
        _consignatariosRepo.obtenerOpcionesViaje(),
        _trabajadoresRepo.obtenerOpcionesViaje(),
        _camionesRepo.obtenerOpcionesViaje(),
        _ubicacionesRepo.obtenerRegiones(),
      ]);
      if (!mounted) return;
      setState(() {
        _clientes = resultados[0] as List<OpcionViaje>;
        _consignatarios = resultados[1] as List<OpcionViaje>;
        _conductores = resultados[2] as List<OpcionViaje>;
        _camiones = resultados[3] as List<OpcionViaje>;
        _regiones = resultados[4] as List<Region>;
        _cargandoOpciones = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cargandoOpciones = false;
        _errorOpciones =
            'No se pudieron cargar clientes, consignatarios, conductores, camiones y regiones. Revisa tu conexión e inténtalo de nuevo.';
      });
    }
  }

  List<DropdownOption> _opciones(List<OpcionViaje> lista) =>
      lista.map((o) => DropdownOption(o.id, o.nombre)).toList();

  OpcionViaje? _buscar(List<OpcionViaje> lista, String? id) {
    if (id == null) return null;
    for (final o in lista) {
      if (o.id == id) return o;
    }
    return null;
  }

  String _nombreDe(List<OpcionViaje> lista, String? id) => _buscar(lista, id)?.nombre ?? '—';

  String _hintSelect(String normal, String sinRegistros, bool vacio) =>
      (!_cargandoOpciones && _errorOpciones == null && vacio) ? sinRegistros : normal;

  void _onClienteChanged(String? id) {
    setState(() {
      _clienteId = id;
      _direccionOrigenCtrl.text = _buscar(_clientes, id)?.direccion ?? '';
    });
  }

  void _onConsignatarioChanged(String? id) {
    setState(() {
      _consignatarioId = id;
      _direccionDestinoCtrl.text = _buscar(_consignatarios, id)?.direccion ?? '';
    });
  }

  String? _requerido(String? v, String mensaje) {
    if (v == null || v.trim().isEmpty) return mensaje;
    return null;
  }

  String? _validarPallets(String? v) {
    if (v == null || v.trim().isEmpty) return 'Ingresa la cantidad de pallets';
    final n = int.tryParse(v.trim());
    if (n == null || n < 0) return 'Cantidad inválida';
    return null;
  }

  void _mostrarMensaje(String texto, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(texto), backgroundColor: color),
    );
  }

  Future<void> _seleccionarFecha() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _fechaProgramada ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Fecha programada',
      cancelText: 'CANCELAR',
      confirmText: 'ACEPTAR',
      locale: const Locale('es', 'CL'),
    );
    if (picked != null) {
      setState(() {
        _fechaProgramada = picked;
        _fechaCtrl.text = '${picked.day.toString().padLeft(2, '0')}/'
            '${picked.month.toString().padLeft(2, '0')}/${picked.year}';
      });
    }
  }

  Future<void> _seleccionarHora(TextEditingController controller, ValueChanged<TimeOfDay> onPicked) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      helpText: 'Seleccionar hora',
      cancelText: 'CANCELAR',
      confirmText: 'ACEPTAR',
    );
    if (picked != null) {
      setState(() {
        onPicked(picked);
        controller.text = picked.format(context);
      });
    }
  }

  void _limpiarFormulario() {
    _formKey.currentState?.reset();
    _palletsCtrl.clear();
    _direccionOrigenCtrl.clear();
    _direccionDestinoCtrl.clear();
    _fechaCtrl.clear();
    _horaCargaCtrl.clear();
    _horaDescargaCtrl.clear();
    _observacionesCtrl.clear();
    setState(() {
      _fechaProgramada = null;
      _horaCarga = null;
      _horaDescarga = null;
      _clienteId = null;
      _consignatarioId = null;
      _regionId = null;
      _conductorRut = null;
      _camionId = null;
    });
  }

  Future<void> _asignar() async {
    if (_guardando) return;
    if (!_formKey.currentState!.validate()) return;
    if (_fechaProgramada == null || _horaCarga == null || _horaDescarga == null) {
      _mostrarMensaje('Completa la fecha y los horarios de carga y descarga.', Colors.red.shade700);
      return;
    }

    final observaciones = _observacionesCtrl.text.trim();
    final viaje = Viaje(
      conductorRut: _conductorRut!,
      camionId: _camionId!,
      clienteId: _clienteId!,
      consignatarioId: _consignatarioId!,
      regionId: _regionId!,
      fechaViaje: _fechaProgramada!,
      horaCarga: _horaCarga!,
      horaDescarga: _horaDescarga!,
      pallets: int.parse(_palletsCtrl.text.trim()),
      observacionesAdmin: observaciones.isEmpty ? null : observaciones,
    );

    final regionNombre = _regiones
        .firstWhere((r) => r.id == _regionId, orElse: () => const Region(id: '', nombre: '—'))
        .nombre;
    final conductorNombre = _nombreDe(_conductores, _conductorRut);
    final patente = _nombreDe(_camiones, _camionId);

    final confirmado = await mostrarDialogoConfirmacion(
      context,
      titulo: 'Confirmar asignación de viaje',
      mensaje: 'Revisa los datos antes de asignar el viaje.',
      resumen: {
        'Cliente (origen)': _nombreDe(_clientes, _clienteId),
        'Dirección origen': _direccionOrigenCtrl.text,
        'Destino': _nombreDe(_consignatarios, _consignatarioId),
        'Dirección destino': _direccionDestinoCtrl.text,
        'Región': regionNombre,
        'Pallets': viaje.pallets.toString(),
        'Fecha': _fechaCtrl.text,
        'Hora de carga': _horaCargaCtrl.text,
        'Hora de descarga': _horaDescargaCtrl.text,
        'Conductor': conductorNombre,
        'Patente': patente,
        if (viaje.observacionesAdmin != null) 'Observaciones': viaje.observacionesAdmin!,
      },
      textoConfirmar: 'CONFIRMAR Y ASIGNAR',
      icono: Icons.local_shipping_outlined,
    );
    if (!confirmado || !mounted) return;

    setState(() => _guardando = true);
    try {
      await _viajesRepo.crear(viaje);
      if (!mounted) return;
      widget.onAsignar?.call(viaje);
      _mostrarMensaje('Viaje asignado a $conductorNombre correctamente', AppColors.success);
      _limpiarFormulario();
    } on RepositoryException catch (e) {
      if (!mounted) return;
      _mostrarMensaje(e.mensaje, Colors.red.shade700);
    } catch (_) {
      if (!mounted) return;
      _mostrarMensaje(
        'No se pudo asignar el viaje. Revisa tu conexión e inténtalo de nuevo.',
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
      selectedIndex: 14,
      showBackButton: false,
      title: 'Asignar Viaje a Trabajador',
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
                  _buildHero(esPantallaPequena),
                  const SizedBox(height: 20),
                  if (_errorOpciones != null) ...[
                    _buildErrorOpciones(),
                    const SizedBox(height: 20),
                  ],
                  _buildDetallesCliente(esPantallaPequena),
                  const SizedBox(height: 20),
                  _buildRutaYHorario(esPantallaPequena),
                  const SizedBox(height: 20),
                  _buildAsignacionRecursos(esPantallaPequena),
                  const SizedBox(height: 20),
                  _buildObservaciones(),
                  const SizedBox(height: 20),
                  _buildFooterAcciones(esPantallaPequena),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHero(bool esPantallaPequena) {
    final badgeSistema = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.success.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 7, color: Color(0xFF4ADE80)),
          SizedBox(width: 6),
          Text(
            'SISTEMA OPERATIVO',
            style: TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.w700, fontSize: 10.5),
          ),
        ],
      ),
    );

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -20,
            bottom: -30,
            child: Icon(Icons.local_shipping_rounded, size: 200, color: Colors.white.withOpacity(0.06)),
          ),
          Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!esPantallaPequena)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.business_center_outlined, size: 12, color: Colors.white),
                            SizedBox(width: 5),
                            Text(
                              'OPERACIONES LOGÍSTICAS',
                              style: TextStyle(
                                  color: Colors.white, fontWeight: FontWeight.w800, fontSize: 10, letterSpacing: 0.4),
                            ),
                          ],
                        ),
                      ),
                      badgeSistema,
                    ],
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.business_center_outlined, size: 12, color: Colors.white),
                        SizedBox(width: 5),
                        Text(
                          'OPERACIONES LOGÍSTICAS',
                          style: TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w800, fontSize: 10, letterSpacing: 0.4),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                RichText(
                  text: const TextSpan(
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 30, height: 1.15),
                    children: [
                      TextSpan(text: 'Asignar Viaje\n', style: TextStyle(color: Colors.white)),
                      TextSpan(text: 'a Trabajador', style: TextStyle(color: AppColors.primary)),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Configure los detalles operativos de la ruta y asigne el personal '
                  'calificado para la ejecución del servicio.',
                  style: TextStyle(color: Colors.white70, fontSize: 13.5, height: 1.4),
                ),
                if (esPantallaPequena) ...[
                  const SizedBox(height: 18),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: badgeSistema,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorOpciones() {
    return Container(
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
            child: Text(_errorOpciones!, style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
          ),
          TextButton(
            onPressed: _cargandoOpciones ? null : _cargarOpciones,
            child: const Text('REINTENTAR'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetallesCliente(bool esPantallaPequena) {
    final campoCliente = LabeledDropdownField(
      label: 'Cliente (origen)',
      value: _clienteId,
      items: _opciones(_clientes),
      hint: _hintSelect('Seleccione un cliente...', 'No hay clientes registrados', _clientes.isEmpty),
      icon: Icons.apartment_outlined,
      loading: _cargandoOpciones,
      onChanged: _onClienteChanged,
      validator: (v) => v == null ? 'Selecciona un cliente' : null,
    );

    final campoPallets = LabeledTextField(
      label: 'Pallets (cantidad)',
      controller: _palletsCtrl,
      hint: '0',
      icon: Icons.info_outline,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      validator: _validarPallets,
    );

    return FormSectionCard(
      icon: Icons.inventory_2_outlined,
      title: 'Detalles del Cliente',
      child: Column(
        children: [
          if (!esPantallaPequena)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: campoCliente),
                const SizedBox(width: 16),
                Expanded(child: campoPallets),
              ],
            )
          else ...[
            campoCliente,
            const SizedBox(height: 16),
            campoPallets,
          ],
          const SizedBox(height: 16),
          LabeledTextField(
            label: 'Dirección de origen',
            controller: _direccionOrigenCtrl,
            hint: 'Se completa al elegir el cliente',
            icon: Icons.location_on_outlined,
            readOnly: true,
          ),
        ],
      ),
    );
  }

  Widget _buildRutaYHorario(bool esPantallaPequena) {
    final campoRegion = LabeledDropdownField(
      label: 'Región operativa',
      value: _regionId,
      items: _regiones.map((r) => DropdownOption(r.id, r.nombre)).toList(),
      hint: _hintSelect('Seleccione una región...', 'No hay regiones registradas', _regiones.isEmpty),
      icon: Icons.public_outlined,
      loading: _cargandoOpciones,
      onChanged: (v) => setState(() => _regionId = v),
      validator: (v) => v == null ? 'Selecciona una región' : null,
    );

    final campoConsignatario = LabeledDropdownField(
      label: 'Destino (consignatario)',
      value: _consignatarioId,
      items: _opciones(_consignatarios),
      hint: _hintSelect(
          'Seleccione el consignatario...', 'No hay consignatarios registrados', _consignatarios.isEmpty),
      icon: Icons.near_me_outlined,
      loading: _cargandoOpciones,
      onChanged: _onConsignatarioChanged,
      validator: (v) => v == null ? 'Selecciona el consignatario de destino' : null,
    );

    final campoFecha = LabeledTextField(
      label: 'Fecha programada',
      controller: _fechaCtrl,
      hint: 'dd/mm/aaaa',
      icon: Icons.calendar_today_outlined,
      readOnly: true,
      onTap: _seleccionarFecha,
      validator: (v) => _requerido(v, 'Elige la fecha'),
    );

    final campoHoraCarga = LabeledTextField(
      label: 'Hora de carga',
      controller: _horaCargaCtrl,
      hint: '--:--',
      icon: Icons.access_time,
      readOnly: true,
      onTap: () => _seleccionarHora(_horaCargaCtrl, (t) => _horaCarga = t),
      validator: (v) => _requerido(v, 'Elige la hora'),
    );

    final campoHoraDescarga = LabeledTextField(
      label: 'Hora de descarga',
      controller: _horaDescargaCtrl,
      hint: '--:--',
      icon: Icons.access_time,
      readOnly: true,
      onTap: () => _seleccionarHora(_horaDescargaCtrl, (t) => _horaDescarga = t),
      validator: (v) => _requerido(v, 'Elige la hora'),
    );

    return FormSectionCard(
      icon: Icons.location_on_outlined,
      title: 'Ruta y Horario',
      child: Column(
        children: [
          if (!esPantallaPequena)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: campoRegion),
                const SizedBox(width: 16),
                Expanded(child: campoConsignatario),
              ],
            )
          else ...[
            campoRegion,
            const SizedBox(height: 16),
            campoConsignatario,
          ],
          const SizedBox(height: 16),
          LabeledTextField(
            label: 'Dirección de destino',
            controller: _direccionDestinoCtrl,
            hint: 'Se completa al elegir el consignatario',
            icon: Icons.location_on_outlined,
            readOnly: true,
          ),
          const SizedBox(height: 16),
          if (!esPantallaPequena)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: campoFecha),
                const SizedBox(width: 16),
                Expanded(child: campoHoraCarga),
                const SizedBox(width: 16),
                Expanded(child: campoHoraDescarga),
              ],
            )
          else ...[
            campoFecha,
            const SizedBox(height: 16),
            // Horas de carga y descarga juntas en la misma fila en celular
            Row(
              children: [
                Expanded(child: campoHoraCarga),
                const SizedBox(width: 12),
                Expanded(child: campoHoraDescarga),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAsignacionRecursos(bool esPantallaPequena) {
    final campoConductor = LabeledDropdownField(
      label: 'Seleccionar conductor',
      value: _conductorRut,
      items: _opciones(_conductores),
      hint: _hintSelect('Buscar por nombre...', 'No hay conductores registrados', _conductores.isEmpty),
      icon: Icons.person_outline,
      loading: _cargandoOpciones,
      onChanged: (v) => setState(() => _conductorRut = v),
      validator: (v) => v == null ? 'Selecciona un conductor' : null,
    );

    final campoPatente = LabeledDropdownField(
      label: 'Seleccionar patente',
      value: _camionId,
      items: _opciones(_camiones),
      hint: _hintSelect('ABCD-12...', 'No hay camiones registrados', _camiones.isEmpty),
      icon: Icons.local_shipping_outlined,
      loading: _cargandoOpciones,
      onChanged: (v) => setState(() => _camionId = v),
      validator: (v) => v == null ? 'Selecciona una patente' : null,
    );

    return FormSectionCard(
      icon: Icons.local_shipping_outlined,
      title: 'Asignación de Recursos',
      child: esPantallaPequena
          ? Column(
              children: [
                campoConductor,
                const SizedBox(height: 16),
                campoPatente,
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: campoConductor),
                const SizedBox(width: 16),
                Expanded(child: campoPatente),
              ],
            ),
    );
  }

  Widget _buildObservaciones() {
    return FormSectionCard(
      icon: Icons.chat_bubble_outline,
      title: 'Observaciones',
      child: LabeledTextField(
        label: 'Nota del administrador',
        controller: _observacionesCtrl,
        hint: 'Ingrese instrucciones especiales, requerimientos de EPP, o detalles críticos para el conductor...',
        maxLines: 4,
      ),
    );
  }

  Widget _buildFooterAcciones(bool esPantallaPequena) {
    final aviso = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.infoBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.infoBorder),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: Colors.blueAccent),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Al confirmar, el viaje quedará asignado al conductor, quien podrá verlo en su '
              'aplicación, iniciarlo y completar los datos al finalizar.',
              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );

    final botonAsignar = ElevatedButton.icon(
      onPressed: (_guardando || _cargandoOpciones) ? null : _asignar,
      icon: _guardando
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : const Icon(Icons.save_outlined, size: 16),
      label: Text(_guardando ? 'ASIGNANDO...' : 'ASIGNAR VIAJE'),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );

    if (!esPantallaPequena) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: aviso),
          const SizedBox(width: 16),
          botonAsignar,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        aviso,
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: botonAsignar,
        ),
      ],
    );
  }
}