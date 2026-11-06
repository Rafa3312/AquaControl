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

// ── Riego inteligente (Sprint 6) ──────────────────────────────────────────────
test('acepta los avisos del riego inteligente con humedad y umbral', () => {
  const result = validateEvent({ ...VALID, type: 'skip', minutes: undefined, moisture: 68, threshold: 60 });
  assert.equal(result.ok, true);
  assert.equal(result.event.moisture, 68);
  assert.equal(result.event.threshold, 60);
});

test('rechaza humedad o umbral fuera de rango', () => {
  assert.equal(validateEvent({ ...VALID, type: 'skip', moisture: 101, threshold: 60 }).ok, false);
  assert.equal(validateEvent({ ...VALID, type: 'skip', moisture: 50, threshold: 9 }).ok, false);
  assert.equal(validateEvent({ ...VALID, type: 'skip', moisture: 50, threshold: 91 }).ok, false);
});

test('el riego omitido explica el motivo con la humedad y el umbral', () => {
  const message = buildMessage({ ...VALID, type: 'skip', moisture: 68, threshold: 60 }, 'Jardín');
  assert.equal(message.title, 'Riego omitido · Jardín');
  assert.match(message.body, /68%.*60%.*humedad suficiente/);
});

test('el riego reducido indica los minutos y la falla del sensor es una alerta', () => {
  const reduced = buildMessage({ ...VALID, type: 'reduce', moisture: 50, threshold: 60, minutes: 5 }, null);
  assert.match(reduced.body, /la mitad \(5 min\)/);
  const sensor = buildMessage({ ...VALID, type: 'sensor' }, null);
  assert.equal(sensor.title, 'Sensor de humedad sin lectura · Zona 1');
  assert.equal(sensor.severity, 'error');
});
