import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'providers/device_provider.dart';
import 'providers/irrigation_provider.dart';
import 'providers/notification_provider.dart';
import 'providers/schedule_provider.dart';
import 'providers/scheduler_service.dart';
import 'providers/zone_provider.dart';
import 'video_splash.dart';

/// Avisos que llegan con la app en segundo plano o cerrada. Android muestra
/// la notificación por sí mismo; aquí solo se inicializa Firebase.
@pragma('vm:entry-point')
Future<void> _onBackgroundMessage(RemoteMessage message) async {
  await Firebase.initializeApp();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppTheme.navBg,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const AquaControlApp());
}

class AquaControlApp extends StatefulWidget {
  const AquaControlApp({super.key});

  @override
  State<AquaControlApp> createState() => _AquaControlAppState();
}

class _AquaControlAppState extends State<AquaControlApp>
    with WidgetsBindingObserver {
  final _deviceProvider     = DeviceProvider();
  final _irrigationProvider = IrrigationProvider();
  final _scheduleProvider   = ScheduleProvider();
  final _scheduler          = SchedulerService();
  final _messengerKey       = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Conectar IrrigationProvider con DeviceProvider para que envíe HTTP
    _irrigationProvider.setDeviceProvider(_deviceProvider);

    // Cuando ScheduleProvider termine de cargar, arrancar scheduler
    // y empujar las programaciones al ESP32
    _scheduleProvider.addListener(_onSchedulesReady);
    _scheduleProvider.addListener(_syncSchedulesToDevice);

    // Avisos con la app abierta: Android no los muestra solo, así que
    // se presentan como un mensaje en pantalla.
    FirebaseMessaging.onMessage.listen((message) {
      final n = message.notification;
      if (n == null) return;
      final isFailure = message.data['type'] == 'fail';
      _messengerKey.currentState?.showSnackBar(SnackBar(
        backgroundColor: isFailure ? AppTheme.danger : AppTheme.bgCardLight,
        content: Text('${n.title ?? 'AquaControl'}\n${n.body ?? ''}'),
      ));
    });
  }

  void _onSchedulesReady() {
    if (!_scheduleProvider.loading) {
      _scheduleProvider.removeListener(_onSchedulesReady);
      _scheduler.init(_irrigationProvider, _scheduleProvider);
    }
  }

  // Cada vez que cambian las programaciones, sincronizar al ESP32
  void _syncSchedulesToDevice() {
    if (_scheduleProvider.loading) return;
    if (!_deviceProvider.isConnected) return;

    final list = _scheduleProvider.schedules.map((s) => {
      'id':          s.id,
      'active':      s.isActive,
      'days':        _daysToBitmask(s.days),
      'startHour':   s.startHour,
      'startMinute': s.startMinute,
      'duration':    s.durationMinutes,
      'zone':        s.zone,
    }).toList();

    _deviceProvider.syncSchedules(list);
  }

  // Convierte [0,2,4] (Lun, Mié, Vie) a bitmask 0b00010101 = 21
  int _daysToBitmask(List<int> days) {
    int mask = 0;
    for (final d in days) { mask |= (1 << d); }
    return mask;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // Al volver al primer plano, verificar conexión con el ESP
      _deviceProvider.checkConnection();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scheduler.dispose();
    _scheduleProvider.removeListener(_syncSchedulesToDevice);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider.value(value: _deviceProvider),
        ChangeNotifierProvider.value(value: _irrigationProvider),
        ChangeNotifierProvider.value(value: _scheduleProvider),
        ChangeNotifierProvider(create: (_) => ZoneProvider()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(
        title: 'AquaControl',
        scaffoldMessengerKey: _messengerKey,
        theme: AppTheme.darkTheme,
        home: VideoSplash(),
        debugShowCheckedModeBanner: false,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.noScaling),
          child: child!,
        ),
      ),
    );
  }
}
