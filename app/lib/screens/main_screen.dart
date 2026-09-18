import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/auth_provider.dart';
import 'home/home_tab.dart';
import 'programs/programs_tab.dart';
import 'reports/reports_tab.dart';
import 'profile/profile_drawer.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  static const _tabs = [HomeTab(), ProgramsTab(), ReportsTab()];

  void openDrawer() => _scaffoldKey.currentState?.openDrawer();

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: AppTheme.navBg,
      ),
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: AppTheme.bgPrimary,
        drawer: const ProfileDrawer(),
        // Pasar el callback para abrir drawer a las tabs que lo necesiten
        body: _TabsWrapper(
          currentIndex: _currentIndex,
          tabs: _tabs,
          onAvatarTap: openDrawer,
        ),
        bottomNavigationBar: _BottomNav(
          currentIndex: _currentIndex,
          onTap: (i) => setState(() => _currentIndex = i),
        ),
      ),
    );
  }
}

// Wrapper que inyecta el callback de avatar vía InheritedWidget ligero
class _TabsWrapper extends StatelessWidget {
  final int currentIndex;
  final List<Widget> tabs;
  final VoidCallback onAvatarTap;

  const _TabsWrapper({
    required this.currentIndex,
    required this.tabs,
    required this.onAvatarTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppDrawerCallback(
      onOpen: onAvatarTap,
      child: IndexedStack(index: currentIndex, children: tabs),
    );
  }
}

/// InheritedWidget para que las tabs puedan abrir el drawer
/// sin conocer el Scaffold directamente.
class AppDrawerCallback extends InheritedWidget {
  final VoidCallback onOpen;
  const AppDrawerCallback({super.key, required this.onOpen, required super.child});

  static AppDrawerCallback? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppDrawerCallback>();

  @override
  bool updateShouldNotify(AppDrawerCallback old) => onOpen != old.onOpen;
}

// ══════════════════════════════════════════════════════════════════════════════
// Bottom Navigation Bar estilo Spotify
// ══════════════════════════════════════════════════════════════════════════════

class _BottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _BottomNav({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.navBg,
        border: Border(top: BorderSide(color: AppTheme.divider, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavItem(
                icon: Icons.water_drop_outlined,
                activeIcon: Icons.water_drop_rounded,
                label: 'Inicio',
                index: 0,
                currentIndex: currentIndex,
                onTap: onTap,
              ),
              _NavItem(
                icon: Icons.calendar_month_outlined,
                activeIcon: Icons.calendar_month_rounded,
                label: 'Programas',
                index: 1,
                currentIndex: currentIndex,
                onTap: onTap,
              ),
              _NavItem(
                icon: Icons.bar_chart_outlined,
                activeIcon: Icons.bar_chart_rounded,
                label: 'Reportes',
                index: 2,
                currentIndex: currentIndex,
                onTap: onTap,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int index;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.index,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = currentIndex == index;

    return GestureDetector(
      onTap: () => onTap(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? AppTheme.primary.withOpacity(0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isActive ? activeIcon : icon,
              color: isActive ? AppTheme.primary : AppTheme.textMuted,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isActive ? AppTheme.primary : AppTheme.textMuted,
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
