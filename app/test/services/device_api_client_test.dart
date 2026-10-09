import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:irrigation_app/services/device_api_client.dart';

/// Pruebas del cliente del API REST del ESP32 con el patrón AAA
/// (Arrange – Act – Assert). El ESP32 se sustituye por un MockClient que
/// responde igual que el firmware AquaControl v3, así que no se requiere
/// hardware. Los IDs (CP-xx) corresponden al Plan de Pruebas.
void main() {
  const validToken = 'a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d'; // UUID v4, 36 chars
  final baseUri = Uri.parse('http://192.168.1.50');

  http.Response json(int status, Map<String, dynamic> body) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );

  group('GET /status', () {
    test('CP-01 devuelve el estado y envía el token Bearer', () async {
      // Arrange
      http.Request? sent;
      final mock = MockClient((req) async {
        sent = req;
        return json(200, {'online': true, 'valve': true, 'paired': true});
      });
      final api =
          DeviceApiClient(baseUri: baseUri, token: validToken, client: mock);

      // Act
      final status = await api.getStatus();

      // Assert
      expect(sent!.method, 'GET');
      expect(sent!.url.path, '/status');
      expect(sent!.headers['Authorization'], 'Bearer $validToken');
      expect(status['valve'], isTrue);
    });

    test('CP-02 token inválido produce DeviceApiException 401', () async {
      // Arrange
      final mock = MockClient(
          (_) async => json(401, {'ok': false, 'error': 'Token invalido'}));
      final api =
          DeviceApiClient(baseUri: baseUri, token: 'token-viejo', client: mock);

      // Act
      final call = api.getStatus();

      // Assert
      await expectLater(
        call,
        throwsA(isA<DeviceApiException>()
            .having((e) => e.statusCode, 'statusCode', 401)
            .having((e) => e.isUnauthorized, 'isUnauthorized', isTrue)
            .having((e) => e.message, 'message', 'Token invalido')),
      );
    });

    test('CP-03 sin conexión produce DeviceApiException offline', () async {
      // Arrange
      final mock = MockClient((_) async => throw http.ClientException(
          'Connection refused'));
      final api =
          DeviceApiClient(baseUri: baseUri, token: validToken, client: mock);

      // Act
      final call = api.getStatus();

      // Assert
      await expectLater(
        call,
        throwsA(isA<DeviceApiException>()
            .having((e) => e.isOffline, 'isOffline', isTrue)),
      );
    });

    test('CP-04 dispositivo que no responde a tiempo produce timeout',
        () async {
      // Arrange
      final mock = MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return json(200, {'online': true});
      });
      final api = DeviceApiClient(
        baseUri: baseUri,
        token: validToken,
        client: mock,
        timeout: const Duration(milliseconds: 20),
      );

      // Act
      final call = api.getStatus();

      // Assert
      await expectLater(
        call,
        throwsA(isA<DeviceApiException>()
            .having((e) => e.statusCode, 'statusCode', 0)
            .having((e) => e.message, 'message', contains('a tiempo'))),
      );
    });

    test('CP-05 petición sin vincular no llega a la red', () async {
      // Arrange
      var requests = 0;
      final mock = MockClient((_) async {
        requests++;
        return json(200, {});
      });
      final api = DeviceApiClient(baseUri: baseUri, client: mock);

      // Act
      final call = api.getStatus();

      // Assert
      await expectLater(call, throwsStateError);
      expect(requests, 0);
    });
  });

  group('POST /pair', () {
    test('CP-06 vinculación exitosa envía token y uid sin Bearer', () async {
      // Arrange
      http.Request? sent;
      final mock = MockClient((req) async {
        sent = req;
        return json(200, {'ok': true, 'device': 'A1B2C3'});
      });
      final api = DeviceApiClient(baseUri: baseUri, client: mock);

      // Act
      final res = await api.pair(pairingToken: validToken, uid: 'uid-123');

      // Assert
      expect(sent!.url.path, '/pair');
      expect(sent!.headers.containsKey('Authorization'), isFalse);
      expect(jsonDecode(sent!.body), {'token': validToken, 'uid': 'uid-123'});
      expect(res['ok'], isTrue);
      expect(res['device'], 'A1B2C3');
    });

    test('CP-07 token corto se rechaza sin gastar intentos del ESP32', () {
      // Arrange
      var requests = 0;
      final mock = MockClient((_) async {
        requests++;
        return json(400, {'ok': false, 'error': 'Token corto'});
      });
      final api = DeviceApiClient(baseUri: baseUri, client: mock);

      // Act
      void call() => api.pair(pairingToken: 'abc123', uid: 'uid-123');

      // Assert
      expect(call, throwsArgumentError);
      expect(requests, 0);
    });

    test('CP-08 dispositivo ya vinculado responde 403', () async {
      // Arrange
      final mock = MockClient(
          (_) async => json(403, {'ok': false, 'error': 'Ya vinculado'}));
      final api = DeviceApiClient(baseUri: baseUri, client: mock);

      // Act
      final call = api.pair(pairingToken: validToken, uid: 'uid-123');

      // Assert
      await expectLater(
        call,
        throwsA(isA<DeviceApiException>()
            .having((e) => e.statusCode, 'statusCode', 403)
            .having((e) => e.message, 'message', 'Ya vinculado')),
      );
    });

    test('CP-09 UID vacío se rechaza en el cliente', () {
      // Arrange
      final api = DeviceApiClient(
          baseUri: baseUri,
          client: MockClient((_) async => json(200, {'ok': true})));

      // Act
      void call() => api.pair(pairingToken: validToken, uid: '   ');

      // Assert
      expect(call, throwsArgumentError);
    });
  });

  group('POST /on y /off', () {
    test('CP-10 encender con duración envía {"duration": 15}', () async {
      // Arrange
      http.Request? sent;
      final mock = MockClient((req) async {
        sent = req;
        return json(200, {'ok': true, 'valve': true, 'duration': 15});
      });
      final api =
          DeviceApiClient(baseUri: baseUri, token: validToken, client: mock);

      // Act
      final res = await api.turnOn(durationMinutes: 15);

      // Assert
      expect(sent!.method, 'POST');
      expect(sent!.url.path, '/on');
      expect(jsonDecode(sent!.body), {'duration': 15});
      expect(res['valve'], isTrue);
    });

    test('CP-11 duración fuera de rango (121 min) se rechaza', () {
      // Arrange
      final api = DeviceApiClient(
          baseUri: baseUri,
          token: validToken,
          client: MockClient((_) async => json(200, {'ok': true})));

      // Act
      void call() => api.turnOn(durationMinutes: 121);

      // Assert
      expect(call, throwsRangeError);
    });

    test('CP-12 apagar el riego devuelve valve=false', () async {
      // Arrange
      final mock = MockClient(
          (_) async => json(200, {'ok': true, 'valve': false}));
      final api =
          DeviceApiClient(baseUri: baseUri, token: validToken, client: mock);

      // Act
      final res = await api.turnOff();

      // Assert
      expect(res['ok'], isTrue);
      expect(res['valve'], isFalse);
    });
  });

  group('Programaciones /schedules', () {
    Map<String, dynamic> schedule(int i) => {
          'id': 'p$i',
          'active': true,
          'days': 127,
          'startHour': 6,
          'startMinute': 30,
          'duration': 15,
        };

    test('CP-13 sincronizar programaciones envía la lista completa',
        () async {
      // Arrange
      http.Request? sent;
      final mock = MockClient((req) async {
        sent = req;
        return json(200, {'ok': true, 'count': 2});
      });
      final api =
          DeviceApiClient(baseUri: baseUri, token: validToken, client: mock);

      // Act
      final res = await api.syncSchedules([schedule(1), schedule(2)]);

      // Assert
      expect(sent!.url.path, '/schedules');
      expect((jsonDecode(sent!.body)['schedules'] as List).length, 2);
      expect(res['count'], 2);
    });

    test('CP-14 más de 10 programaciones se rechaza (MAX_SCHEDULES)', () {
      // Arrange
      final api = DeviceApiClient(
          baseUri: baseUri,
          token: validToken,
          client: MockClient((_) async => json(200, {'ok': true})));
      final once = List.generate(11, schedule);

      // Act
      void call() => api.syncSchedules(once);

      // Assert
      expect(call, throwsArgumentError);
    });

    test('CP-15 eliminar programación inexistente responde 404', () async {
      // Arrange
      final mock = MockClient(
          (_) async => json(404, {'ok': false, 'error': 'No encontrada'}));
      final api =
          DeviceApiClient(baseUri: baseUri, token: validToken, client: mock);

      // Act
      final call = api.deleteSchedule('no-existe');

      // Assert
      await expectLater(
        call,
        throwsA(isA<DeviceApiException>()
            .having((e) => e.statusCode, 'statusCode', 404)
            .having((e) => e.message, 'message', 'No encontrada')),
      );
    });

    test('CP-16 activar programación envía id y active', () async {
      // Arrange
      http.Request? sent;
      final mock = MockClient((req) async {
        sent = req;
        return json(200, {'ok': true});
      });
      final api =
          DeviceApiClient(baseUri: baseUri, token: validToken, client: mock);

      // Act
      final res = await api.setScheduleActive('p1', true);

      // Assert
      expect(sent!.url.path, '/schedules/active');
      expect(jsonDecode(sent!.body), {'id': 'p1', 'active': true});
      expect(res['ok'], isTrue);
    });
  });
}
