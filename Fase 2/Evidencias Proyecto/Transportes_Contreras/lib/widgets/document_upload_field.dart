import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/app_colors.dart';

/// Tarjeta de carga de un documento (carnet de identidad, licencia de
/// conducir, etc). Sólo maneja la selección del archivo en memoria; la
/// subida real a Supabase Storage se conectará más adelante.
class DocumentUploadField extends StatefulWidget {
  const DocumentUploadField({
    super.key,
    required this.label,
    this.helperText = 'PNG, JPG hasta 10MB',
    this.onFileSelected,
  });

  final String label;
  final String helperText;
  final ValueChanged<XFile>? onFileSelected;

  @override
  State<DocumentUploadField> createState() => _DocumentUploadFieldState();
}

class _DocumentUploadFieldState extends State<DocumentUploadField> {
  XFile? _file;
  Uint8List? _preview;

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      _file = picked;
      _preview = bytes;
    });
    widget.onFileSelected?.call(picked);
  }

  @override
  Widget build(BuildContext context) {
    final hasFile = _file != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: _pickImage,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: hasFile ? AppColors.success : AppColors.border,
                style: BorderStyle.solid,
              ),
            ),
            child: hasFile
                ? Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.memory(_preview!, height: 64, fit: BoxFit.cover),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _file!.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      TextButton.icon(
                        onPressed: _pickImage,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Cambiar archivo'),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      const Icon(Icons.file_upload_outlined, color: AppColors.textSecondary),
                      const SizedBox(height: 8),
                      const Text(
                        'Sube una foto clara del documento',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.helperText,
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}