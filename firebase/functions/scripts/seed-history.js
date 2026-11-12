'use strict';

// Datos de prueba del historial (acción de mejora del Sprint 7): carga riegos
// simulados de varios meses para probar el historial y las estadísticas sin
// esperar riegos reales.
//
//   Con el emulador:  FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 node scripts/seed-history.js <uid>
//   Con el proyecto:  GOOGLE_APPLICATION_CREDENTIALS=<llave.json> node scripts/seed-history.js <uid>
//
// Opciones: --months=6  --end=AAAA-MM-DD (último día, por defecto hoy)  --project=<id>
// ¡Cuidado!: con el proyecto real escribe en la cuenta de ese uid. Úsalo con una cuenta de prueba.

const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const {
  buildHistoryDoc,
  dailyDelta,
  dailyDocFor,
  dateKey,
  recordId,
  simulateHistory,
} = require('../lib/history');

const args = process.argv.slice(2);
const uid = args.find((a) => !a.startsWith('--'));
const opt = (name, fallback) => {
  const hit = args.find((a) => a.startsWith(`--${name}=`));
  return hit ? hit.split('=')[1] : fallback;
};

if (!uid) {
  console.error('Uso: node scripts/seed-history.js <uid> [--months=6] [--end=AAAA-MM-DD] [--project=<id>]');
  process.exit(1);
}

const months = Number(opt('months', 6));
// Hora local de México (UTC-6, sin horario de verano)
const localNow = new Date(Date.now() - 6 * 3600 * 1000).toISOString().slice(0, 10);
const endDate = opt('end', localNow);
const projectId = opt('project', process.env.GCLOUD_PROJECT || 'demo-aquacontrol');

initializeApp({ projectId });
const db = getFirestore();

async function main() {
  const records = simulateHistory({ endDate, months, seed: 2026 });
  const daily = new Map();

  let batch = db.batch();
  let pending = 0;
  const flush = async () => { if (pending > 0) { await batch.commit(); batch = db.batch(); pending = 0; } };

  for (const record of records) {
    batch.set(db.doc(`users/${uid}/history/${recordId(record)}`), buildHistoryDoc(record, 'SEED'));
    pending += 1;

    const { date, expireAt } = dailyDocFor(record);
    const delta = dailyDelta(record);
    const day = daily.get(date) || { date, expireAt, zones: {} };
    const z = day.zones[record.zone] || { runs: 0, seconds: 0, skipped: 0 };
    z.runs += delta.runs; z.seconds += delta.seconds; z.skipped += delta.skipped;
    day.zones[record.zone] = z;
    daily.set(date, day);

    if (pending >= 400) await flush();
  }
  for (const day of daily.values()) {
    batch.set(db.doc(`users/${uid}/dailyStats/${day.date}`), day);
    pending += 1;
    if (pending >= 400) await flush();
  }
  await flush();

  const first = dateKey(Math.min(...records.map((r) => r.at)));
  console.log(`Listo: ${records.length} riegos y ${daily.size} resúmenes diarios (${first} a ${endDate}) para ${uid}.`);
}

main().catch((err) => { console.error(err); process.exit(1); });
