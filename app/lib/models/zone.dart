/// Zonas de riego que controla el programador (una válvula por zona).
class Zones {
  /// Debe coincidir con ZONE_COUNT del firmware.
  static const int count = 2;

  /// Longitud máxima del nombre (igual que en las reglas de Firestore).
  static const int maxNameLength = 30;

  static List<int> get ids => List.generate(count, (i) => i + 1);

  static bool isValid(int id) => id >= 1 && id <= count;

  static String defaultName(int id) => 'Zona $id';

  /// Devuelve un mensaje de error o null si el nombre es válido.
  static String? validateName(String name) {
    final value = name.trim();
    if (value.isEmpty) return 'Escribe un nombre para la zona';
    if (value.length > maxNameLength) {
      return 'Máximo $maxNameLength caracteres';
    }
    return null;
  }
}

/// Estado de una zona tal como lo reporta el ESP32 en GET /status.
class ZoneStatus {
  final int id;
  final bool valveOpen;
  final bool manual;
  final bool fault;
  final String? stopAt;

  const ZoneStatus({
    required this.id,
    required this.valveOpen,
    this.manual = false,
    this.fault = false,
    this.stopAt,
  });

  /// Lee el arreglo "zones" de /status. Si el firmware es anterior a la
  /// versión multizona (sin "zones"), toma "valve" como el estado de la zona 1.
  static List<ZoneStatus> listFromStatus(Map<String, dynamic> status) {
    final byId = {
      for (final id in Zones.ids) id: ZoneStatus(id: id, valveOpen: false),
    };

    final raw = status['zones'];
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;
        final id = item['id'];
        if (id is! int || !Zones.isValid(id)) continue;
        byId[id] = ZoneStatus(
          id: id,
          valveOpen: item['valve'] == true,
          manual: item['manual'] == true,
          fault: item['fault'] == true,
          stopAt: item['stopAt'] as String?,
        );
      }
    } else {
      byId[1] = ZoneStatus(
        id: 1,
        valveOpen: status['valve'] == true,
        manual: status['manual'] == true,
        stopAt: status['stopAt'] as String?,
      );
    }
    return byId.values.toList();
  }
}
