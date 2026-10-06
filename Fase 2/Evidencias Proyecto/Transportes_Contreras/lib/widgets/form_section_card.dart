import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';

/// Tarjeta con encabezado (icono + título, opcionalmente subtítulo) usada
/// para agrupar campos relacionados dentro de un formulario (ej: "Nombre y
/// identificación", "Información de contacto"). Reutilizable en los
/// formularios de trabajadores, clientes y camiones.
class FormSectionCard extends StatelessWidget {
  const FormSectionCard({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: const BoxDecoration(
              color: AppColors.surfaceMuted,
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: AppColors.textPrimary),
                const SizedBox(width: 8),
                Text(
                  title.toUpperCase(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    letterSpacing: 0.3,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      subtitle!,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: child,
          ),
        ],
      ),
    );
  }
}

/// Campo de texto con estilo consistente (etiqueta arriba, icono a la
/// izquierda) para los formularios del panel admin.
class LabeledTextField extends StatelessWidget {
  const LabeledTextField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.icon,
    this.keyboardType,
    this.obscureText = false,
    this.suffixIcon,
    this.validator,
    this.helperText,
    this.inputFormatters,
    this.readOnly = false,
    this.onTap,
    this.focusNode,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final IconData? icon;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;
  final String? helperText;
  final List<TextInputFormatter>? inputFormatters;
  final bool readOnly;
  final VoidCallback? onTap;
  final FocusNode? focusNode;

  /// Número de líneas visibles. Usar >1 (ej: 3 o 4) para un textarea, como
  /// la "Nota del administrador" del form de asignar viaje.
  final int maxLines;
  final int? minLines;
  final int? maxLength;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: keyboardType,
          obscureText: obscureText,
          validator: validator,
          readOnly: readOnly,
          onTap: onTap,
          inputFormatters: inputFormatters,
          maxLength: maxLength,
          maxLines: maxLines,
          minLines: minLines,
          style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
          decoration: InputDecoration(
            counterText: '', // oculta el contador "x/y" bajo el campo
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
            prefixIcon: icon != null ? Icon(icon, size: 18, color: AppColors.textSecondary) : null,
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: AppColors.surfaceMuted,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.redAccent),
            ),
          ),
        ),
        if (helperText != null) ...[
          const SizedBox(height: 6),
          Text(
            helperText!,
            style: const TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

/// Campo de teléfono con un recuadro fijo "+56" a la izquierda (Chile) y el
/// input restringido a 9 dígitos (formato celular: 9 1234 5678).
class LabeledPhoneField extends StatelessWidget {
  const LabeledPhoneField({
    super.key,
    required this.label,
    required this.controller,
    this.hint = '9 1234 5678',
    this.validator,
    this.helperText,
    this.focusNode,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final String? Function(String?)? validator;
  final String? helperText;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Recuadro fijo con el prefijo del país. No es editable.
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(8),
                    bottomLeft: Radius.circular(8),
                  ),
                  border: Border(
                    top: BorderSide(color: AppColors.border),
                    left: BorderSide(color: AppColors.border),
                    bottom: BorderSide(color: AppColors.border),
                  ),
                ),
                child: const Text(
                  '+56',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary),
                ),
              ),
              Expanded(
                child: TextFormField(
                  controller: controller,
                  focusNode: focusNode,
                  keyboardType: TextInputType.phone,
                  maxLength: 9,
                  validator: validator,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(9),
                  ],
                  style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: hint,
                    hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
                    filled: true,
                    fillColor: AppColors.surfaceMuted,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(8),
                        bottomRight: Radius.circular(8),
                      ),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(8),
                        bottomRight: Radius.circular(8),
                      ),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(8),
                        bottomRight: Radius.circular(8),
                      ),
                      borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(8),
                        bottomRight: Radius.circular(8),
                      ),
                      borderSide: const BorderSide(color: Colors.redAccent),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (helperText != null) ...[
          const SizedBox(height: 6),
          Text(
            helperText!,
            style: const TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

/// Tarjeta con una barra de acento naranja + icono + título (y descripción
/// opcional), usada en el form de clientes ("Datos Generales",
/// "Configuración de Tarifas"). Es una variante más liviana de
/// [FormSectionCard] (sin la franja de encabezado gris).
class AccentHeaderCard extends StatelessWidget {
  const AccentHeaderCard({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String? description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 4, height: 20, color: AppColors.primary),
              const SizedBox(width: 10),
              Icon(icon, size: 18, color: AppColors.textPrimary),
              const SizedBox(width: 8),
              Text(
                title.toUpperCase(),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  letterSpacing: 0.3,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          if (description != null) ...[
            const SizedBox(height: 8),
            Text(description!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          ],
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

/// Campo numérico con un prefijo (icono + etiqueta, ej. "🚚 CLP") dentro del
/// mismo recuadro, separado por una pequeña línea vertical. Pensado para
/// montos en pesos chilenos (tarifas, valores de viaje, etc), reutilizable
/// en clientes y camiones.
class LabeledCurrencyField extends StatelessWidget {
  const LabeledCurrencyField({
    super.key,
    required this.label,
    required this.controller,
    required this.prefixIcon,
    this.prefixLabel = 'CLP',
    this.hint = '0.00',
    this.validator,
  });

  final String label;
  final TextEditingController controller;
  final IconData prefixIcon;
  final String prefixLabel;
  final String hint;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: validator,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
            prefix: Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(prefixIcon, size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Text(prefixLabel, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(width: 10),
                  Container(width: 1, height: 16, color: AppColors.border),
                ],
              ),
            ),
            filled: true,
            fillColor: AppColors.surfaceMuted,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.redAccent),
            ),
          ),
        ),
      ],
    );
  }
}
/// Una opción de [LabeledDropdownField]: un id (lo que realmente se guarda,
/// ej. el uuid de una región) y una etiqueta legible para mostrar en la
/// lista (ej. "Metropolitana").
class DropdownOption {
  const DropdownOption(this.id, this.label);

  final String id;
  final String label;
}

/// Campo de selección (dropdown) con el mismo estilo visual que
/// [LabeledTextField]. Pensado para listas que vienen de una tabla de
/// Supabase (ej: regiones, comunas, conductores) en vez de texto libre.
///
/// [value] y los `id` de [items] son lo que se guarda (ej. un uuid);
/// [DropdownOption.label] es lo que ve el usuario. Si [loading] es `true`,
/// se muestra un spinner en vez del ícono y el campo queda deshabilitado
/// mientras carga (ej: comunas cargándose después de elegir una región).
class LabeledDropdownField extends StatelessWidget {
  const LabeledDropdownField({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint = 'Selecciona una opción',
    this.icon,
    this.validator,
    this.enabled = true,
    this.loading = false,
  });

  final String label;
  final String? value;
  final List<DropdownOption> items;
  final ValueChanged<String?>? onChanged;
  final String hint;
  final IconData? icon;
  final String? Function(String?)? validator;

  /// Si es `false`, se muestra deshabilitado (útil para un select que
  /// depende de otro, ej: comuna deshabilitada hasta elegir región).
  final bool enabled;

  /// Muestra un spinner en el ícono y deshabilita el campo mientras se
  /// cargan las opciones (ej: comunas de la región recién elegida).
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final habilitado = enabled && !loading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: value,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
          onChanged: habilitado ? onChanged : null,
          validator: validator,
          style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
          items: items
              .map((item) => DropdownMenuItem(
                    value: item.id,
                    child: Text(item.label, overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
            prefixIcon: loading
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : (icon != null ? Icon(icon, size: 18, color: AppColors.textSecondary) : null),
            filled: true,
            fillColor: habilitado ? AppColors.surfaceMuted : AppColors.border.withOpacity(0.3),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.redAccent),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.border),
            ),
          ),
        ),
      ],
    );
  }
}