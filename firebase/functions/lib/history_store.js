'use strict';

const { buildHistoryDoc, dailyDelta, dailyDocFor, recordId } = require('./history');

/**
 * Guarda un lote de riegos de forma idempotente (Sprint 8).
 * Cada riego se crea solo si no existía: así, si el ESP32 reenvía un lote tras
 * una desconexión, el consumo del día no se suma dos veces.
 * Devuelve cuántos se guardaron y cuántos ya estaban.
 */
async function saveRecords(db, FieldValue, uid, device, records) {
  let saved = 0;
  let duplicates = 0;
  for (const record of records) {
    const historyRef = db.doc(`users/${uid}/history/${recordId(record)}`);
    const { date, expireAt } = dailyDocFor(record);
    const dailyRef = db.doc(`users/${uid}/dailyStats/${date}`);
    const delta = dailyDelta(record);

    const created = await db.runTransaction(async (tx) => {
      if ((await tx.get(historyRef)).exists) return false;
      tx.create(historyRef, buildHistoryDoc(record, device));
      tx.set(dailyRef, {
        date,
        expireAt,
        zones: {
          [record.zone]: {
            runs: FieldValue.increment(delta.runs),
            seconds: FieldValue.increment(delta.seconds),
            skipped: FieldValue.increment(delta.skipped),
          },
        },
      }, { merge: true });
      return true;
    });
    if (created) saved += 1; else duplicates += 1;
  }
  return { saved, duplicates };
}

module.exports = { saveRecords };
