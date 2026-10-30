import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irrigation_app/providers/device_provider.dart';
import 'package:irrigation_app/providers/irrigation_provider.dart';

/// DeviceProvider falso: no usa red ni Firebase y guarda los comandos que
/// recibe, para revisar qué zona se mandó al ESP32.
class FakeDevice extends ChangeNotifier implements DeviceProvider {
  Map<String, dynamic>? status;
  bool commandsOk = true;
  bool connected = true;
  final List<String> commands = [];

  @override
  bool get isConnected => connected;

  @override
  Future<Map<String, dynamic>?> getStatus() async => status;

  @override
  Future<bool> turnOn({int zone = 1, int durationMinutes = 0}) async {
    commands.add('on:$zone:$durationMinutes');
    return commandsOk;
  }

  @override
  Future<bool> turnOff({int? zone}) async {
    commands.add('off:${zone ?? 'todas'}');
    return commandsOk;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Pruebas del control de riego por zona (Sprint 5, HU-7) con patrón AAA.
void main() {
  late IrrigationProvider irrigation;
  late FakeDevice device;

  setUp(() {
    irrigation = IrrigationProvider();
    device = FakeDevice();
  });

  tearDown(() => irrigation.dispose());

  test('arranca con las zonas en reposo y la zona 1 seleccionada', () {
    // Arrange: provider recién creado, sin dispositivo

    // Act
    final zones = irrigation.zones;

    // Assert
    expect(zones.map((z) => z.id), [1, 2]);
    expect(irrigation.selectedZone, 1);
    expect(irrigation.statusLabel, 'En reposo');
    expect(irrigation.elapsedTime, '00:00');
    expect(irrigation.anyActive, isFalse);
    expect(irrigation.deviceOnline, isFalse);
    expect(irrigation.canManualControl, isTrue);
  });

  test('selectZone cambia la zona y rechaza zonas que no existen', () {
    // Arrange
    var avisos = 0;
    irrigation.addListener(() => avisos++);

    // Act
    irrigation.selectZone(2);
    irrigation.selectZone(3); // no existe
    irrigation.selectZone(2); // ya seleccionada

    // Assert: solo el primer cambio cuenta
    expect(irrigation.selectedZone, 2);
    expect(avisos, 1);
  });

  test('turnOn enciende solo la zona elegida y manda esa zona al ESP', () async {
    // Arrange
    irrigation.setDeviceProvider(device);

    // Act
    await irrigation.turnOn(zone: 2);

    // Assert
    expect(irrigation.zone(2).isActive, isTrue);
    expect(irrigation.zone(2).statusLabel, 'Riego Manual');
    expect(irrigation.zone(1).isActive, isFalse);
    expect(irrigation.activeCount, 1);
    expect(device.commands, ['on:2:0']);
  });

  test('si el ESP no responde, la zona queda en error de conexión', () async {
    // Arrange
    device.commandsOk = false;
    irrigation.setDeviceProvider(device);

    // Act
    await irrigation.turnOn();

    // Assert
    expect(irrigation.status, IrrigationStatus.error);
    expect(irrigation.statusLabel, 'Error de conexión');
    expect(irrigation.startTime, isNull);
  });

  test('turnOff apaga la zona, manda el comando y cuenta la sesión', () async {
    // Arrange: la zona 2 lleva 90 segundos regando
    irrigation.setDeviceProvider(device);
    await irrigation.turnOn(zone: 2);
    irrigation.zone(2).startTime =
        DateTime.now().subtract(const Duration(seconds: 90));
    expect(irrigation.zone(2).elapsedTime, '01:30');

    // Act
    await irrigation.turnOff(zone: 2);

    // Assert
    expect(irrigation.zone(2).isActive, isFalse);
    expect(device.commands.last, 'off:2');
    expect(irrigation.sessionsToday, 1);
    expect(irrigation.waterUsageToday, closeTo(0.8, 0.001));

    // Y las estadísticas del día se pueden reiniciar
    irrigation.resetDailyStats();
    expect(irrigation.sessionsToday, 0);
    expect(irrigation.waterUsageToday, 0);
  });

  test('toggleZone alterna entre encender y apagar la zona', () async {
    // Arrange
    irrigation.setDeviceProvider(device);

    // Act
    await irrigation.toggleZone(1);
    final encendida = irrigation.zone(1).isActive;
    await irrigation.toggleZone(1);

    // Assert
    expect(encendida, isTrue);
    expect(irrigation.zone(1).isActive, isFalse);
    expect(device.commands, ['on:1:0', 'off:1']);
  });

  test('syncStatus refleja el estado que reporta el ESP en cada zona', () async {
    // Arrange: la zona 1 riega por horario y la zona 2 tiene falla
    irrigation.setDeviceProvider(device);
    device.status = {
      'zones': [
        {'id': 1, 'valve': true, 'manual': false, 'stopAt': '07:00'},
        {'id': 2, 'valve': false, 'fault': true},
      ],
    };

    // Act
    await irrigation.syncStatus();

    // Assert
    expect(irrigation.zone(1).statusLabel, 'Riego Programado');
    expect(irrigation.zone(1).stopAt, '07:00');
    expect(irrigation.isScheduledRun, isTrue);
    expect(irrigation.zone(2).statusLabel, 'Falla en la válvula');

    // Cuando el ESP termina, la zona vuelve a reposo
    device.status = {
      'zones': [
        {'id': 1, 'valve': false},
        {'id': 2, 'valve': false},
      ],
    };
    await irrigation.syncStatus();
    expect(irrigation.zone(1).isActive, isFalse);
    expect(irrigation.zone(2).fault, isFalse);
  });

  test('al reconectarse el dispositivo se sincroniza el estado', () async {
    // Arrange
    irrigation.setDeviceProvider(device);
    device.status = {
      'zones': [
        {'id': 1, 'valve': false},
        {'id': 2, 'valve': true, 'manual': true},
      ],
    };

    // Act: el DeviceProvider avisa que cambió (reconexión)
    device.notifyListeners();
    await Future<void>.delayed(Duration.zero);

    // Assert
    expect(irrigation.deviceOnline, isTrue);
    expect(irrigation.zone(2).isActive, isTrue);
    expect(irrigation.zone(2).manualOverride, isTrue);
  });

  test('activateFromSchedule marca riego programado y bloquea el manual', () {
    // Act
    irrigation.activateFromSchedule(1);
    irrigation.activateFromSchedule(9); // zona inexistente: se ignora

    // Assert
    expect(irrigation.isActive, isTrue);
    expect(irrigation.manualOverride, isFalse);
    expect(irrigation.canManualControl, isFalse);
    expect(irrigation.statusLabel, 'Riego Programado');
  });

  test('turnOnTest manda al menos 1 minuto y termina sola', () async {
    // Arrange
    irrigation.setDeviceProvider(device);

    // Act: prueba rápida de 0 segundos
    await irrigation.turnOnTest(seconds: 0, zone: 2);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // Assert
    expect(device.commands, ['on:2:1']);
    expect(irrigation.zone(2).isActive, isFalse);
  });

  test('turnOnTest con el ESP sin responder deja la zona en error', () async {
    // Arrange
    device.commandsOk = false;
    irrigation.setDeviceProvider(device);

    // Act
    await irrigation.turnOnTest(seconds: 90);

    // Assert: 90 s se redondean a 2 minutos
    expect(device.commands, ['on:1:2']);
    expect(irrigation.status, IrrigationStatus.error);
  });
}
