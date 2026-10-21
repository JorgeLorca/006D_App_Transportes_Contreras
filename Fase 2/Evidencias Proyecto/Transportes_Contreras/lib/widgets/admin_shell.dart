import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'app_sidebar.dart';
import '../screens/web/lista_camiones_screen.dart';
import '../screens/web/lista_clientes_screen.dart';
import '../screens/web/lista_trabajadores_screen.dart';
import '../screens/web/admin_home_screen.dart';
import '../screens/web/lista_consignatarios_screen.dart';
import '../screens/web/asignar_viaje_screen.dart';

class AdminShell extends StatefulWidget {
  const AdminShell({
    super.key,
    this.selectedIndex,
    this.title,
    this.child,
    this.showBackButton = false,
    this.initiallyOpen = false,
    this.subtitle,
    this.actions,
    this.eyebrow,
    this.eyebrowIcon,
    this.initialIndex = 10,
  });

  final int? selectedIndex;
  final Widget? child;
  final String? title;
  final String? subtitle;
  final bool showBackButton;
  final bool initiallyOpen;
  final List<Widget>? actions;
  final String? eyebrow;
  final IconData? eyebrowIcon;
  final int initialIndex;

  static const double sidebarWidth = 260;

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  late bool _isSidebarOpen;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _isSidebarOpen = widget.initiallyOpen;
    _currentIndex = widget.selectedIndex ?? widget.initialIndex;
  }

  void _toggleSidebar() => setState(() => _isSidebarOpen = !_isSidebarOpen);

  void _closeSidebar() {
    if (_isSidebarOpen) {
      setState(() => _isSidebarOpen = false);
    }
  }

  void _onMenuTap(int index) {
    _closeSidebar();

    // Si pulsamos Inicio (0), redirigimos a AdminHomeScreen directamente
    // evitando meterla dentro de AdminShell para no duplicar su TopBar.
    if (index == 0) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => const AdminHomeScreen(),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
      );
      return;
    }

    // 14 = Cargas > Asignar Viaje
    if (index == 14) {
      if (_currentIndex == 14) return;
      Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => const AsignarViajeScreen(),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
      );
      return;
    }

    if ((index > 0 && index < 10) || index > 14) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Módulo $index en construcción.')),
      );
      return;
    }

    if (widget.child != null) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => AdminShell(
            initialIndex: index,
            initiallyOpen: false,
          ),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
      );
      return;
    }

    setState(() {
      _currentIndex = index;
    });
  }

  String get _currentTitle {
    if (widget.title != null) return widget.title!;
    switch (_currentIndex) {
      case 10:
        return 'Inventario de Flota';
      case 11:
        return 'Cartera de Clientes';
      case 12:
        return 'Nómina de Trabajadores';
      case 13:
        return 'Recepción y Destinos';
      default:
        return 'Panel de Administración';
    }
  }

  String? get _currentSubtitle {
    if (widget.subtitle != null) return widget.subtitle;
    switch (_currentIndex) {
      case 10:
        return 'Administre las unidades de su flota y su estado operativo.';
      case 11:
        return 'Gestione las relaciones corporativas y detalles de contacto de su cartera logística.';
      case 12:
        return 'Gestione el equipo de conductores y personal de ruta registrado.';
      case 13:
        return 'Gestione los consignatarios y bodegas autorizadas para recepción.';
      default:
        return null;
    }
  }

  IconData? get _currentEyebrowIcon {
    if (widget.eyebrowIcon != null) return widget.eyebrowIcon;
    switch (_currentIndex) {
      case 10:
        return Icons.local_shipping_outlined;
      case 11:
        return Icons.business_center_outlined;
      case 12:
        return Icons.badge_outlined;
      default:
        return Icons.dashboard_outlined;
    }
  }

  Widget _buildBody() {
    if (widget.child != null) return widget.child!;

    switch (_currentIndex) {
      case 10:
        return const ListaCamionesScreen();
      case 11:
        return const ListaClientesScreen();
      case 12:
        return const ListaTrabajadoresScreen();
      case 13:
        return const ListaConsignatariosScreen();
      default:
        return const ListaCamionesScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // 1. Contenido Principal a pantalla completa (nunca se corre ni se deforma)
          Positioned.fill(
            child: Column(
              children: [
                _TopBar(
                  title: _currentTitle,
                  subtitle: _currentSubtitle,
                  showBackButton: widget.showBackButton,
                  eyebrow: widget.eyebrow ?? 'GESTIÓN ADMINISTRATIVA',
                  eyebrowIcon: _currentEyebrowIcon,
                  onMenuTap: _toggleSidebar,
                  actions: widget.actions,
                ),
                Expanded(
                  child: KeyedSubtree(
                    key: ValueKey('${widget.child != null ? "form" : "list"}-$_currentIndex'),
                    child: _buildBody(),
                  ),
                ),
              ],
            ),
          ),

          // 2. Fondo Oscurecido (Overlay Scrim)
          IgnorePointer(
            ignoring: !_isSidebarOpen,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              opacity: _isSidebarOpen ? 1.0 : 0.0,
              child: GestureDetector(
                onTap: _closeSidebar,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  color: Colors.black.withOpacity(0.55),
                ),
              ),
            ),
          ),

          // 3. Sidebar Flotante que se desliza por encima tanto en PC como en móvil
          AnimatedPositioned(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            top: 0,
            bottom: 0,
            left: _isSidebarOpen ? 0 : -AdminShell.sidebarWidth,
            width: AdminShell.sidebarWidth,
            child: Material(
              elevation: 16,
              color: Colors.transparent,
              child: AppSidebar(
                selectedIndex: _currentIndex,
                onItemSelected: _onMenuTap,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    this.subtitle,
    required this.showBackButton,
    required this.eyebrow,
    this.eyebrowIcon,
    required this.onMenuTap,
    this.actions,
  });

  final String title;
  final String? subtitle;
  final bool showBackButton;
  final String eyebrow;
  final IconData? eyebrowIcon;
  final VoidCallback onMenuTap;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 68),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.menu),
            tooltip: 'Mostrar/ocultar menú',
            onPressed: onMenuTap,
          ),
          if (showBackButton)
            IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Volver',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (eyebrowIcon != null) ...[
                      Icon(eyebrowIcon, size: 13, color: AppColors.primary),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      eyebrow,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.textPrimary),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
              ],
            ),
          ),
          if (actions != null) ...[
            for (final action in actions!) Padding(padding: const EdgeInsets.only(left: 8), child: action),
            const SizedBox(width: 12),
          ] else
            const SizedBox(width: 48),
        ],
      ),
    );
  }
}