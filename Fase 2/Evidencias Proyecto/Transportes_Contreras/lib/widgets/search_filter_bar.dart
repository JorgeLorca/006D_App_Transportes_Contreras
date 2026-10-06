import 'package:flutter/material.dart';

class SearchFilterBar extends StatelessWidget {
  final String hintText;
  final ValueChanged<String>? onSearchChanged;
  final VoidCallback? onFilterPressed;

  const SearchFilterBar({
    super.key,
    required this.hintText,
    this.onSearchChanged,
    this.onFilterPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: TextField(
              onChanged: onSearchChanged,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF94A3B8)),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: onFilterPressed ?? () {},
          icon: const Icon(Icons.filter_list, size: 16, color: Color(0xFF475569)),
          label: const Text(
            'Filtros Avanzados',
            style: TextStyle(fontSize: 12, color: Color(0xFF475569), fontWeight: FontWeight.w600),
          ),
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.white,
            side: const BorderSide(color: Color(0xFFE2E8F0)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }
}