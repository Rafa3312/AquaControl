'use strict';

// Prueba de integración de deviceHistory contra el emulador de Firestore:
// guardado, resumen diario y, sobre todo, que un reenvío no duplique nada.
// Se ejecuta con:  npm run test:rules   (el emulador define FIRESTORE_EMULATOR_HOST)

const { test, before, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');

const functionsDir = path.join(__dirname, '..', 'functions');
const { initializeApp } = require(path.join(functionsDir, 'node_modules', 'firebase-admin', 'lib', 'app'));
const { getFirestore, FieldValue } = require(path.join(functionsDir, 'node_modules', 'firebase-admin', 'lib', 'firestore'));
const { saveRecords } = require(path.join(functionsDir, 'lib', 'history_store'));

const local = (iso) => Date.parse(`${iso}Z`) / 1000;
const rec = (iso, zone, outcome, seconds, reason = 'none') =>
  ({ at: local(iso), zone, outcome, reason, seconds, manual: false });

let db;

before(() => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'Falta el emulador: usa npm run test:rules');
  initializeApp({ projectId: 'demo-aquacontrol' }, 'history-store-test');
});

beforeEach(async () => {
  const { getApp } = require(path.join(functionsDir, 'node_modules', 'firebase-admin', 'lib', 'app'));
  db = getFirestore(getApp('history-store-test'));
  await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/demo-aquacontrol/databases/(default)/documents`, { method: 'DELETE' });
});

test('guarda el riego y suma el resumen del día solo con riegos que usaron agua', async () => {
  const records = [
    rec('2026-10-21T06:00:00', 1, 'done', 600, 'dry'),
    rec('2026-10-21T18:30:00', 1, 'reduced', 300, 'near'),
    rec('2026-10-21T18:30:00', 2, 'skipped', 0, 'wet'),
    rec('2026-10-21T19:00:00', 2, 'postponed', 0, 'rain'),
  ];

  const result = await saveRecords(db, FieldValue, 'u1', 'A1B2C3', records);

  assert.deepEqual(result, { saved: 4, duplicates: 0 });
  assert.equal((await db.collection('users/u1/history').get()).size, 4);
  const day = (await db.doc('users/u1/dailyStats/2026-10-21').get()).data();
  assert.deepEqual(day.zones['1'], { runs: 2, seconds: 900, skipped: 0 });
  assert.deepEqual(day.zones['2'], { runs: 0, seconds: 0, skipped: 1 });
});

test('un reenvío tras una desconexión no duplica registros ni consumo', async () => {
  const records = [rec('2026-10-21T06:00:00', 1, 'done', 600), rec('2026-10-21T18:30:00', 2, 'done', 480)];
  await saveRecords(db, FieldValue, 'u1', null, records);

  // El ESP32 no recibió la respuesta y manda el mismo lote más otro riego nuevo
  const again = await saveRecords(db, FieldValue, 'u1', null, [...records, rec('2026-10-22T06:00:00', 1, 'done', 600)]);

  assert.deepEqual(again, { saved: 1, duplicates: 2 });
  assert.equal((await db.collection('users/u1/history').get()).size, 3);
  const day = (await db.doc('users/u1/dailyStats/2026-10-21').get()).data();
  assert.equal(day.zones['1'].runs, 1);
  assert.equal(day.zones['1'].seconds, 600);
});

test('un riego de las 23:30 se cuenta en su día local', async () => {
  await saveRecords(db, FieldValue, 'u1', null, [rec('2026-10-31T23:30:00', 1, 'done', 360)]);

  assert.equal((await db.doc('users/u1/dailyStats/2026-10-31').get()).exists, true);
  assert.equal((await db.doc('users/u1/dailyStats/2026-11-01').get()).exists, false);
});

test('cada documento guarda su fecha de caducidad a 12 meses', async () => {
  await saveRecords(db, FieldValue, 'u1', null, [rec('2026-10-21T06:00:00', 1, 'done', 600)]);

  const doc = (await db.collection('users/u1/history').get()).docs[0].data();
  assert.equal(doc.expireAt.toDate().toISOString(), '2027-10-21T12:00:00.000Z');
  const day = (await db.doc('users/u1/dailyStats/2026-10-21').get()).data();
  assert.equal(day.expireAt.toDate().toISOString(), '2027-10-21T06:00:00.000Z');
});
