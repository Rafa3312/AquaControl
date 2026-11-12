import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/irrigation_record.dart';
import '../models/water_stats.dart';
import '../models/zone.dart';

/// Historial de riegos y estadísticas de consumo (Sprint 8, HU-14 y HU-16).
///
/// - Historial: lee users/{uid}/history (un documento por riego), que escribe
///   la Cloud Function deviceHistory con lo que guarda el ESP32.
/// - Estadísticas: lee users/{uid}/dailyStats (un resumen por día). Así un año
///   son ~365 lecturas y no miles de riegos.
/// - Litros: son una estimación (minutos × caudal de la zona). El caudal de
///   cada zona se guarda en users/{uid}/zones/{id}.flowLpm y se puede ajustar.
class HistoryProvider extends ChangeNotifier {
  /// Máximo de riegos que se cargan en la lista del historial.
  static const int listLimit = 200;

  final FirebaseFirestore _firestore;
  final DateTime Function() _clock;

  HistoryPeriod _period = HistoryPeriod.week;
  int? _zone;
  String? _uid;
  bool _loading = false;
  String? _error;

  List<IrrigationRecord> _records = [];
  List<DailyStat> _days = [];
  final Map<int, double> _flows = {};

  StreamSubscription<String?>? _authSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _historySub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _dailySub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _zonesSub;

  /// [firestore], [uidChanges] y [clock] se inyectan en las pruebas; en la
  /// app se usan Firestore, la sesión de Firebase Auth y la hora del teléfono.
  HistoryProvider({
    FirebaseFirestore? firestore,
    Stream<String?>? uidChanges,
    DateTime Function()? clock,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _clock = clock ?? DateTime.now {
    _authSub = (uidChanges ??
            FirebaseAuth.instance.authStateChanges().map((u) => u?.uid))
        .listen(_onUser);
  }

  HistoryPeriod get period => _period;
  int? get zoneFilter => _zone;
  bool get loading => _loading;
  String? get error => _error;
  bool get signedIn => _uid != null;

  /// Riegos del periodo (y de la zona elegida), del más reciente al más antiguo.
  List<IrrigationRecord> get records => List.unmodifiable(
        _records.where((r) => _zone == null || r.zone == _zone),
      );

  /// Si la lista llegó al límite: puede haber riegos más antiguos sin mostrar.
  bool get truncated => _records.length >= listLimit;

  /// Caudal (L/min) de una zona: el ajustado o el nominal.
  double flowOf(int zone) => _flows[zone] ?? Zones.defaultFlowLpm;

  /// Estadísticas del periodo y la zona elegidos.
  WaterStats get stats => WaterStats.compute(
        period: _period,
        now: _clock(),
        days: _days,
        flowLpm: {for (final z in Zones.ids) z: flowOf(z)},
        zone: _zone,
      );

  void setPeriod(HistoryPeriod period) {
    if (period == _period) return;
    _period = period;
    _subscribe();
    notifyListeners();
  }

  void setZone(int? zone) {
    if (zone == _zone) return;
    _zone = zone;
    notifyListeners();
  }

  /// Guarda el caudal medido de una zona. Devuelve un mensaje de error o null.
  Future<String?> setFlow(int zone, double? flow) async {
    final error = Zones.validateFlow(flow);
    if (error != null) return error;
    if (!Zones.isValid(zone)) return 'Zona inválida';
    final uid = _uid;
    if (uid == null) return 'No hay sesión activa';
    try {
      await _firestore.doc('users/$uid/zones/$zone').set({
        'flowLpm': flow,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      return 'No se pudo guardar el caudal. Revisa tu conexión.';
    }
    _flows[zone] = flow!;
    notifyListeners();
    return null;
  }

  Future<void> _onUser(String? uid) async {
    await _zonesSub?.cancel();
    _uid = uid;
    _records = [];
    _days = [];
    _flows.clear();
    _error = null;
    notifyListeners();
    if (uid == null) {
      await _historySub?.cancel();
      await _dailySub?.cancel();
      _loading = false;
      return;
    }

    _zonesSub = _firestore.collection('users/$uid/zones').snapshots().listen(
      (snap) {
        _flows.clear();
        for (final doc in snap.docs) {
          final id = int.tryParse(doc.id);
          final flow = doc.data()['flowLpm'];
          if (id != null && Zones.isValid(id) && flow is num && Zones.validateFlow(flow.toDouble()) == null) {
            _flows[id] = flow.toDouble();
          }
        }
        notifyListeners();
      },
      onError: (e) => debugPrint('[Historial] Error al leer los caudales: $e'),
    );
    _subscribe();
  }

  /// (Re)suscribe el historial y los resúmenes al periodo elegido.
  void _subscribe() {
    final uid = _uid;
    _historySub?.cancel();
    _dailySub?.cancel();
    if (uid == null) return;

    final range = _period.range(_clock());
    _loading = true;
    _error = null;

    _historySub = _firestore
        .collection('users/$uid/history')
        .where('startAt', isGreaterThanOrEqualTo: Timestamp.fromDate(range.startInstant))
        .orderBy('startAt', descending: true)
        .limit(listLimit)
        .snapshots()
        .listen(
          (snap) {
            _records = [
              for (final d in snap.docs)
                if (IrrigationRecord.tryParse(d.id, d.data()) case final r?) r,
            ];
            _loading = false;
            notifyListeners();
          },
          onError: _onError,
        );

    _dailySub = _firestore
        .collection('users/$uid/dailyStats')
        .where('date', isGreaterThanOrEqualTo: range.firstKey)
        .where('date', isLessThanOrEqualTo: range.lastKey)
        .snapshots()
        .listen(
          (snap) {
            _days = [
              for (final d in snap.docs)
                if (DailyStat.tryParse(d.id, d.data()) case final s?) s,
            ];
            notifyListeners();
          },
          onError: _onError,
        );
  }

  void _onError(Object e) {
    debugPrint('[Historial] Error al leer el historial: $e');
    _loading = false;
    _error = 'No se pudo cargar el historial. Revisa tu conexión.';
    notifyListeners();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _historySub?.cancel();
    _dailySub?.cancel();
    _zonesSub?.cancel();
    super.dispose();
  }
}
