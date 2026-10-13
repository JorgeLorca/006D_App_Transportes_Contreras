import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
// Importa tu pantalla de Login (ajusta la ruta según la ubicación de tu archivo si difiere):
import '../screens/web/admin_login_screen.dart';

class SidebarMenuItem {
  const SidebarMenuItem({required this.icon, required this.label, this.routeIndex});

  final IconData icon;
  final String label;
  final int? routeIndex;
}

const List<SidebarMenuItem> kAdminMenuItems = [
  SidebarMenuItem(icon: Icons.grid_view_rounded, label: 'Inicio', routeIndex: 0),
  SidebarMenuItem(icon: Icons.inventory_2_outlined, label: 'Cargas', routeIndex: 1),
  SidebarMenuItem(icon: Icons.payments_outlined, label: 'Rendiciones', routeIndex: 2),
  SidebarMenuItem(icon: Icons.more_horiz_rounded, label: 'Configuración', routeIndex: 3),
];

class AppSidebar extends StatefulWidget {
  const AppSidebar({
    super.key,
    required this.selectedIndex,
    this.onItemSelected,
    this.userName = 'Admin Sistema',
    this.userRole = 'OPERACIONES',
  });

  final int selectedIndex;
  final ValueChanged<int>? onItemSelected;
  final String userName;
  final String userRole;

  static const Color background = Color(0xFF1E293B);
  static const Color inactiveText = Color(0xFF94A3B8);

  @override
  State<AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends State<AppSidebar> {
  bool _gestionExpandida = true;
  bool _cargasExpandida = true;

  Future<void> _confirmarCerrarSesion(BuildContext context) async {
    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: const [
            Icon(Icons.logout, color: Colors.red, size: 22),
            SizedBox(width: 8),
            Text(
              'Cerrar Sesión',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
          ],
        ),
        content: const Text(
          '¿Estás seguro de que deseas salir del panel administrativo?',
          style: TextStyle(fontSize: 13, color: Color(0xFF475569)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text(
              'Cerrar Sesión',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmar == true && context.mounted) {
      try {
        // 1. Invalidar token y sesión en Supabase
        await Supabase.instance.client.auth.signOut();

        if (!context.mounted) return;

        // 2. Notificación visual
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sesión cerrada correctamente.'),
            backgroundColor: Color(0xFF0F172A),
          ),
        );

        // 3. Redirigir al Login y vaciar la pila de rutas
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const AdminLoginScreen()),
          (route) => false,
        );
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cerrar sesión: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppSidebar.background,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildLogo(),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _SidebarButton(
                    item: kAdminMenuItems[0],
                    isSelected: widget.selectedIndex == 0,
                    onTap: () => widget.onItemSelected?.call(0),
                  ),

                  // Grupo colapsable: Cargas
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    child: Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        initiallyExpanded: _cargasExpandida,
                        onExpansionChanged: (exp) => setState(() => _cargasExpandida = exp),
                        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                        leading: Icon(kAdminMenuItems[1].icon, size: 19, color: AppSidebar.inactiveText),
                        title: Text(
                          kAdminMenuItems[1].label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        trailing: Icon(
                          _cargasExpandida ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                          color: AppSidebar.inactiveText,
                          size: 18,
                        ),
                        children: [
                          _buildSubmenuItem(
                            label: 'Asignar Viaje',
                            icon: Icons.assignment_ind_outlined,
                            isSelected: widget.selectedIndex == 14,
                            onTap: () => widget.onItemSelected?.call(14),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Grupo colapsable: Gestión Administrativa
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    child: Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        initiallyExpanded: _gestionExpandida,
                        onExpansionChanged: (exp) => setState(() => _gestionExpandida = exp),
                        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                        leading: const Icon(Icons.admin_panel_settings_outlined, size: 19, color: AppSidebar.inactiveText),
                        title: const Text(
                          'Gestión Administrativa',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        trailing: Icon(
                          _gestionExpandida ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                          color: AppSidebar.inactiveText,
                          size: 18,
                        ),
                        children: [
                          _buildSubmenuItem(
                            label: 'Lista de Camiones',
                            icon: Icons.local_shipping_outlined,
                            isSelected: widget.selectedIndex == 10,
                            onTap: () => widget.onItemSelected?.call(10),
                          ),
                          _buildSubmenuItem(
                            label: 'Lista de Clientes',
                            icon: Icons.business_center_outlined,
                            isSelected: widget.selectedIndex == 11,
                            onTap: () => widget.onItemSelected?.call(11),
                          ),
                          _buildSubmenuItem(
                            label: 'Lista de Trabajadores',
                            icon: Icons.badge_outlined,
                            isSelected: widget.selectedIndex == 12,
                            onTap: () => widget.onItemSelected?.call(12),
                          ),
                          _buildSubmenuItem(
                            label: 'Lista de Consignatarios',
                            icon: Icons.apartment_outlined,
                            isSelected: widget.selectedIndex == 13,
                            onTap: () => widget.onItemSelected?.call(13),
                          ),
                        ],
                      ),
                    ),
                  ),

                  _SidebarButton(
                    item: kAdminMenuItems[2],
                    isSelected: widget.selectedIndex == 2,
                    onTap: () => widget.onItemSelected?.call(2),
                  ),
                  _SidebarButton(
                    item: kAdminMenuItems[3],
                    isSelected: widget.selectedIndex == 3,
                    onTap: () => widget.onItemSelected?.call(3),
                  ),
                ],
              ),
            ),
            _buildUserCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildSubmenuItem({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 4, top: 2, bottom: 2),
      child: Material(
        color: isSelected ? AppColors.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(icon, size: 16, color: isSelected ? Colors.white : AppSidebar.inactiveText),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: isSelected ? Colors.white : AppSidebar.inactiveText,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.local_shipping_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Transportes Contreras',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w800,
                fontSize: 15,
                height: 1.1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserCard() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 17,
              backgroundColor: Colors.white24,
              child: Icon(Icons.person, color: Colors.white70, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.userName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  Text(
                    widget.userRole,
                    style: const TextStyle(
                      color: AppSidebar.inactiveText,
                      fontWeight: FontWeight.w600,
                      fontSize: 10,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Cerrar sesión',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: const Icon(
                Icons.logout,
                size: 18,
                color: AppSidebar.inactiveText,
              ),
              hoverColor: Colors.red.withOpacity(0.15),
              onPressed: () => _confirmarCerrarSesion(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarButton extends StatelessWidget {
  const _SidebarButton({required this.item, required this.isSelected, required this.onTap});

  final SidebarMenuItem item;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: isSelected ? AppColors.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(
                  item.icon,
                  size: 19,
                  color: isSelected ? Colors.white : AppSidebar.inactiveText,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.label,
                    style: TextStyle(
                      color: isSelected ? Colors.white : AppSidebar.inactiveText,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 13.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}