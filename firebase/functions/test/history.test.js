'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const {
  buildHistoryDoc,
  dailyDelta,
  dailyDocFor,
  dateKey,
  instantOf,
  recordId,
  simulateHistory,
  validateBatch,
  validateRecord,
} = require('../lib/history');

// 2026-10-21 23:30:00 hora local, expresado como "segundos locales"
const AT_2330 = Date.parse('2026-10-21T23:30:00Z') / 1000;
const RECORD = { at: AT_2330, zone: 1, outcome: 'done', reason: 'dry', seconds: 600, manual: false };

test('un riego de las 23:30 queda en su día local, no en el siguiente (UTC)', () => {
  // Arrange / Act
  const doc = buildHistoryDoc(RECORD, 'A1B2C3');
  // Assert: la fecha local es la del 21; el instante real ya es del 22 en UTC
  assert.equal(doc.date, '2026-10-21');
  assert.equal(doc.startAt.toISOString(), '2026-10-22T05:30:00.000Z');
});

test('valores límite de día y de mes: 00:00, 23:59:59 y cambio de mes', () => {
  const midnight = Date.parse('2026-11-01T00:00:00Z') / 1000;
  assert.equal(dateKey(midnight), '2026-11-01');
  assert.equal(dateKey(midnight - 1), '2026-10-31');
  assert.equal(dateKey(Date.parse('2026-12-31T23:59:59Z') / 1000), '2026-12-31');
  assert.equal(instantOf(midnight).toISOString(), '2026-11-01T06:00:00.000Z');
});

test('el documento caduca a los 12 meses (365 días) del riego', () => {
  const doc = buildHistoryDoc(RECORD, null);
  const days = (doc.expireAt - doc.startAt) / 86400000;
  assert.equal(days, 365);
  assert.equal(doc.device, null);
});

test('el resumen diario caduca a los 365 días de la medianoche local', () => {
  const { date, expireAt } = dailyDocFor(RECORD);
  assert.equal(date, '2026-10-21');
  assert.equal(expireAt.toISOString(), '2027-10-21T06:00:00.000Z');
});

test('el mismo riego reenviado produce el mismo identificador (sin duplicados)', () => {
  assert.equal(recordId(RECORD), `${AT_2330}_1_done`);
  assert.equal(recordId({ ...RECORD }), recordId(RECORD));
  assert.notEqual(recordId({ ...RECORD, zone: 2 }), recordId(RECORD));
  assert.notEqual(recordId({ ...RECORD, outcome: 'reduced' }), recordId(RECORD));
});

test('solo los riegos con agua suman al consumo', () => {
  assert.deepEqual(dailyDelta(RECORD), { runs: 1, seconds: 600, skipped: 0 });
  assert.deepEqual(dailyDelta({ ...RECORD, outcome: 'reduced', seconds: 300 }), { runs: 1, seconds: 300, skipped: 0 });
  assert.deepEqual(dailyDelta({ ...RECORD, outcome: 'skipped', seconds: 0 }), { runs: 0, seconds: 0, skipped: 1 });
  assert.deepEqual(dailyDelta({ ...RECORD, outcome: 'cancelled', seconds: 0 }), { runs: 0, seconds: 0, skipped: 1 });
  assert.deepEqual(dailyDelta({ ...RECORD, outcome: 'postponed', seconds: 0 }), { runs: 0, seconds: 0, skipped: 0 });
  assert.deepEqual(dailyDelta({ ...RECORD, outcome: 'failed', seconds: 0 }), { runs: 0, seconds: 0, skipped: 0 });
});

test('valida cada campo del registro', () => {
  assert.equal(validateRecord(RECORD), null);
  assert.equal(validateRecord(null), 'registro inválido');
  assert.equal(validateRecord({ ...RECORD, at: 946684800 }), 'at inválido'); // RTC sin ajustar (año 2000)
  assert.equal(validateRecord({ ...RECORD, at: 1.5 }), 'at inválido');
  assert.equal(validateRecord({ ...RECORD, zone: 0 }), 'zone inválida');
  assert.equal(validateRecord({ ...RECORD, zone: 3 }), 'zone inválida');
  assert.equal(validateRecord({ ...RECORD, outcome: 'lost' }), 'outcome inválido');
  assert.equal(validateRecord({ ...RECORD, reason: 'x' }), 'reason inválido');
  assert.equal(validateRecord({ ...RECORD, seconds: -1 }), 'seconds inválido');
  assert.equal(validateRecord({ ...RECORD, seconds: 86401 }), 'seconds inválido');
  assert.equal(validateRecord({ ...RECORD, manual: 'no' }), 'manual inválido');
});

test('acepta los límites de segundos: 0 y 86400', () => {
  assert.equal(validateRecord({ ...RECORD, seconds: 0 }), null);
  assert.equal(validateRecord({ ...RECORD, seconds: 86400 }), null);
});

test('valida el lote completo: uid, tamaño y cada registro', () => {
  const ok = validateBatch({ uid: 'u1', device: 'A1B2C3', records: [RECORD] });
  assert.equal(ok.ok, true);
  assert.equal(ok.batch.records.length, 1);

  assert.equal(validateBatch(null).ok, false);
  assert.equal(validateBatch({ uid: 'a/b', records: [RECORD] }).error, 'uid inválido');
  assert.equal(validateBatch({ uid: '', records: [RECORD] }).error, 'uid inválido');
  assert.equal(validateBatch({ uid: 'u1', device: 'x'.repeat(17), records: [RECORD] }).error, 'device inválido');
  assert.equal(validateBatch({ uid: 'u1', records: [] }).error, 'records inválidos');
  assert.equal(validateBatch({ uid: 'u1', records: 'x' }).error, 'records inválidos');
  assert.equal(validateBatch({ uid: 'u1', records: Array(21).fill(RECORD) }).error, 'records inválidos');
  assert.equal(validateBatch({ uid: 'u1', records: Array(20).fill(RECORD) }).ok, true);
  assert.equal(validateBatch({ uid: 'u1', records: [RECORD, { ...RECORD, zone: 9 }] }).error, 'zone inválida');
});

test('los datos de prueba cubren 6 meses, son deterministas y todos válidos', () => {
  const a = simulateHistory({ endDate: '2026-10-23', months: 6, seed: 7 });
  const b = simulateHistory({ endDate: '2026-10-23', months: 6, seed: 7 });
  assert.deepEqual(a, b);
  assert.ok(a.length > 300);
  assert.ok(a.every((r) => validateRecord(r) === null));
  const days = new Set(a.map((r) => dateKey(r.at)));
  assert.ok(days.size >= 180);
  assert.equal(Math.max(...a.map((r) => r.at)) <= Date.parse('2026-10-24T00:00:00Z') / 1000, true);
  // incluye riegos de borde de día (23:30) y de todos los resultados
  assert.ok(a.some((r) => dateKey(r.at) !== dateKey(r.at + 1800) && r.at % 86400 === 23 * 3600 + 30 * 60));
  const outcomes = new Set(a.map((r) => r.outcome));
  for (const o of ['done', 'reduced', 'skipped', 'cancelled']) assert.ok(outcomes.has(o), o);
});
