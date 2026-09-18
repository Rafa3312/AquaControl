import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/auth_provider.dart';
import 'auth/login_screen.dart';
import 'auth/device_setup_screen.dart';
import 'main_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _logoCtrl;
  late AnimationController _textCtrl;
  late Animation<double>   _logoScale;
  late Animation<double>   _logoOpacity;
  late Animation<double>   _textOpacity;
  late Animation<Offset>   _textSlide;

  @override
  void initState() {
    super.initState();

    _logoCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _textCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));

    _logoScale   = Tween<double>(begin: 0.4, end: 1.0).animate(
        CurvedAnimation(parent: _logoCtrl, curve: Curves.elasticOut));
    _logoOpacity = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _logoCtrl,
            curve: const Interval(0, 0.5)));
    _textOpacity = Tween<double>(begin: 0, end: 1).animate(_textCtrl);
    _textSlide   = Tween<Offset>(
        begin: const Offset(0, 0.3), end: Offset.zero).animate(
        CurvedAnimation(parent: _textCtrl, curve: Curves.easeOut));

    _startSequence();
  }

  Future<void> _startSequence() async {
    await Future.delayed(const Duration(milliseconds: 200));
    _logoCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 600));
    _textCtrl.forward();

    // Esperar al menos 2 s de splash Y a que AuthProvider termine de cargar
    await Future.wait([
      Future.delayed(const Duration(milliseconds: 1800)),
      _waitForAuth(),
    ]);

    if (mounted) _navigate();
  }

  Future<void> _waitForAuth() async {
    // Esperar a que AuthProvider.loading sea false
    final auth = context.read<AuthProvider>();
    while (auth.loading) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  void _navigate() {
    final auth = context.read<AuthProvider>();

    Widget destination;
    if (!auth.isLoggedIn) {
      destination = const LoginScreen();
    } else if (!auth.hasLinkedDevice) {
      destination = const DeviceSetupScreen(isOnboarding: true);
    } else {
      destination = const MainScreen();
    }

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, a, __) => destination,
        transitionsBuilder: (_, a, __, child) =>
            FadeTransition(opacity: a, child: child),
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  @override
  void dispose() {
    _logoCtrl.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: _logoScale,
              child: FadeTransition(
                opacity: _logoOpacity,
                child: Container(
                  width: 110, height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(
                        colors: [AppTheme.accent, AppTheme.primary]),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primary.withOpacity(0.4),
                        blurRadius: 40, spreadRadius: 10,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.water_drop_rounded,
                      size: 56, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 28),

            FadeTransition(
              opacity: _textOpacity,
              child: SlideTransition(
                position: _textSlide,
                child: Column(
                  children: [
                    const Text('AquaControl',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        )),
                    const SizedBox(height: 6),
                    Text('Riego inteligente',
                        style: TextStyle(
                          color: AppTheme.primary.withOpacity(0.85),
                          fontSize: 15,
                          letterSpacing: 1.5,
                        )),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 80),

            FadeTransition(
              opacity: _textOpacity,
              child: SizedBox(
                width: 36, height: 36,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation(
                      AppTheme.primary.withOpacity(0.6)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
