'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { bearerToken, buildMessage, tokensEqual, validateEvent } = require('../lib/notifications');

const VALID = { uid: 'uid-123', type: 'start', zone: 1, source: 'schedule', minutes: 15, device: 'A1B2C3' };

test('acepta un aviso válido del ESP32', () => {
  // Arrange / Act
  const result = validateEvent(VALID);
  // Assert
  assert.equal(result.ok, true);
  assert.equal(result.event.zone, 1);
  assert.equal(result.event.minutes, 15);
});

test('rechaza una zona que no existe', () => {
  const result = validateEvent({ ...VALID, zone: 3 });
  assert.deepEqual(result, { ok: false, error: 'zone inválida' });
});

test('rechaza un tipo de aviso desconocido', () => {
  const result = validateEvent({ ...VALID, type: 'reboot' });
  assert.equal(result.ok, false);
});

test('rechaza un uid con "/" (evita escribir en otra ruta)', () => {
  const result = validateEvent({ ...VALID, uid: 'otro/devices' });
  assert.equal(result.ok, false);
});

test('el mensaje de falla incluye el nombre de la zona', () => {
  const message = buildMessage({ ...VALID, type: 'fail' }, 'Jardín');
  assert.equal(message.title, 'Falla en Jardín');
  assert.equal(message.severity, 'error');
});

test('el mensaje de inicio indica la duración', () => {
  const message = buildMessage(VALID, null);
  assert.equal(message.title, 'Riego iniciado · Zona 1');
  assert.match(message.body, /15 min/);
});

test('compara tokens y solo acepta el idéntico', () => {
  const token = 'a'.repeat(36);
  assert.equal(tokensEqual(token, token), true);
  assert.equal(tokensEqual(token, 'b'.repeat(36)), false);
  assert.equal(tokensEqual(token, 'a'.repeat(35)), false);
  assert.equal(tokensEqual(token, undefined), false);
});

test('extrae el token Bearer del encabezado', () => {
  assert.equal(bearerToken('Bearer abc'), 'abc');
  assert.equal(bearerToken('Basic abc'), null);
  assert.equal(bearerToken(undefined), null);
});
