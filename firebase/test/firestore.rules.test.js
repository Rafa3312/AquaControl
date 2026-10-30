'use strict';

// Pruebas de las reglas de Firestore contra el emulador.
// Se ejecutan con:  npm run test:rules   (desde la carpeta firebase/)

const { test, before, after, beforeEach } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const { doc, getDoc, setDoc, deleteDoc, collection, addDoc } = require('firebase/firestore');

const TOKEN = 'a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d'; // 36 caracteres, como un UUID v4
let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-aquacontrol',
    firestore: {
      rules: fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });
});

after(async () => {
  await env.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
  // Datos iniciales sin pasar por las reglas
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'devices/alicia'), { uid: 'alicia', token: TOKEN, ip: '192.168.1.50' });
    await setDoc(doc(db, 'users/alicia/notifications/n1'), { type: 'fail', zone: 1 });
  });
});

const as = (uid) => env.authenticatedContext(uid).firestore();

// ── Dispositivos ──────────────────────────────────────────────────────────────
test('el dueño puede leer su dispositivo', async () => {
  await assertSucceeds(getDoc(doc(as('alicia'), 'devices/alicia')));
});

test('otro usuario NO puede leer el dispositivo ajeno (IDOR)', async () => {
  await assertFails(getDoc(doc(as('beto'), 'devices/alicia')));
});

test('sin sesión no se puede leer ningún dispositivo', async () => {
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'devices/alicia')));
});

test('no se puede guardar un dispositivo con token corto', async () => {
  await assertFails(setDoc(doc(as('beto'), 'devices/beto'), { uid: 'beto', token: 'corto' }));
});

test('no se puede guardar un dispositivo a nombre de otro uid', async () => {
  await assertFails(setDoc(doc(as('beto'), 'devices/beto'), { uid: 'alicia', token: TOKEN }));
});

// ── Zonas ─────────────────────────────────────────────────────────────────────
test('el dueño puede renombrar sus zonas 1 y 2', async () => {
  await assertSucceeds(setDoc(doc(as('alicia'), 'users/alicia/zones/1'), { name: 'Jardín' }));
  await assertSucceeds(setDoc(doc(as('alicia'), 'users/alicia/zones/2'), { name: 'Huerto' }));
});

test('no se puede crear una zona que no existe en el hardware', async () => {
  await assertFails(setDoc(doc(as('alicia'), 'users/alicia/zones/3'), { name: 'Patio' }));
});

test('el nombre de la zona debe tener entre 1 y 30 caracteres', async () => {
  await assertFails(setDoc(doc(as('alicia'), 'users/alicia/zones/1'), { name: '' }));
  await assertFails(setDoc(doc(as('alicia'), 'users/alicia/zones/1'), { name: 'x'.repeat(31) }));
});

test('otro usuario no puede renombrar zonas ajenas', async () => {
  await assertFails(setDoc(doc(as('beto'), 'users/alicia/zones/1'), { name: 'Mío' }));
});

// ── Consentimiento y tokens FCM ───────────────────────────────────────────────
test('sin consentimiento no se puede registrar un token FCM', async () => {
  await assertFails(setDoc(doc(as('alicia'), 'users/alicia/fcmTokens/tkn-1'), { platform: 'android' }));
});

test('con consentimiento el dueño registra su token FCM', async () => {
  const db = as('alicia');
  await assertSucceeds(setDoc(doc(db, 'users/alicia'), { notificationsEnabled: true }));
  await assertSucceeds(setDoc(doc(db, 'users/alicia/fcmTokens/tkn-1'), { platform: 'android' }));
});

test('no se pueden agregar campos extra al perfil (ej. rol de administrador)', async () => {
  await assertFails(setDoc(doc(as('alicia'), 'users/alicia'), { notificationsEnabled: true, role: 'admin' }));
});

// ── Avisos de riego ───────────────────────────────────────────────────────────
test('el dueño puede leer y borrar sus avisos', async () => {
  const db = as('alicia');
  await assertSucceeds(getDoc(doc(db, 'users/alicia/notifications/n1')));
  await assertSucceeds(deleteDoc(doc(db, 'users/alicia/notifications/n1')));
});

test('nadie puede crear avisos desde la app (solo la Cloud Function)', async () => {
  await assertFails(addDoc(collection(as('alicia'), 'users/alicia/notifications'), { type: 'fail', zone: 1 }));
});

test('otro usuario no puede leer los avisos ajenos', async () => {
  await assertFails(getDoc(doc(as('beto'), 'users/alicia/notifications/n1')));
});
