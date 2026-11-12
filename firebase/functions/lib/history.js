'use strict';

// Historial de riegos y resúmenes diarios (Sprint 8, HU-14 y HU-16).
//
// El ESP32 guarda cada riego en su memoria y los envía por lotes a la función
// deviceHistory. Aquí se validan y se convierten en:
//   users/{uid}/history/{id}      un documento por riego (lista del historial)
//   users/{uid}/dailyStats/{date} un resumen por día (estadísticas de consumo)
// Así la app calcula un año de consumo leyendo ~365 resúmenes y no miles de riegos.

const OUTCOMES = ['done', 'reduced', 'skipped', 'postponed', 'cancelled', 'failed'];
const REASONS = ['none', 'wet', 'near', 'dry', 'sensor', 'rain', 'valve'];
/** Resultados en los que sí corrió agua: son los que suman al consumo. */
const WATERED = ['done', 'reduced'];
const MAX_ZONES = 2;
const MAX_BATCH = 20;
const MAX_SECONDS = 86400;

/** México (Querétaro) no usa horario de verano: UTC-6 todo el año. */
const LOCAL_OFFSET_SECONDS = -6 * 3600;
/** Retención: 12 meses. El campo expireAt lo borra la política TTL de Firestore. */
const RETENTION_DAYS = 365;
const DAY_MS = 86400 * 1000;

/**
 * El firmware manda la hora local del RTC como "segundos desde 1970 con los
 * campos de la hora local" (at). Aquí se saca la fecha local AAAA-MM-DD sin
 * pasar por la zona horaria del servidor: así un riego de las 23:30 queda en
 * su día y no en el siguiente (error de fecha UTC del Sprint 3).
 */
function dateKey(localSeconds) {
  return new Date(localSeconds * 1000).toISOString().slice(0, 10);
}

/** Instante real (UTC) de una hora local expresada como "segundos locales". */
function instantOf(localSeconds) {
  return new Date((localSeconds - LOCAL_OFFSET_SECONDS) * 1000);
}

/** Medianoche local del día AAAA-MM-DD, como instante real. */
function dayStartInstant(date) {
  return instantOf(Date.parse(`${date}T00:00:00Z`) / 1000);
}

function expiresAt(instant) {
  return new Date(instant.getTime() + RETENTION_DAYS * DAY_MS);
}

/** Identificador estable: el mismo riego reenviado produce el mismo documento. */
function recordId(record) {
  return `${record.at}_${record.zone}_${record.outcome}`;
}

function validateRecord(r) {
  if (r === null || typeof r !== 'object') return 'registro inválido';
  const { at, zone, outcome, reason, seconds, manual } = r;
  // 2020-01-01 a 2100-01-01: descarta relojes sin ajustar (RTC en 2000)
  if (!Number.isInteger(at) || at < 1577836800 || at > 4102444800) return 'at inválido';
  if (!Number.isInteger(zone) || zone < 1 || zone > MAX_ZONES) return 'zone inválida';
  if (!OUTCOMES.includes(outcome)) return 'outcome inválido';
  if (!REASONS.includes(reason)) return 'reason inválido';
  if (!Number.isInteger(seconds) || seconds < 0 || seconds > MAX_SECONDS) return 'seconds inválido';
  if (typeof manual !== 'boolean') return 'manual inválido';
  return null;
}

/** Valida el cuerpo del lote que envía el ESP32. */
function validateBatch(body) {
  if (body === null || typeof body !== 'object') return { ok: false, error: 'Cuerpo inválido' };
  const { uid, device, records } = body;
  if (typeof uid !== 'string' || uid.length === 0 || uid.length > 128 || uid.includes('/')) {
    return { ok: false, error: 'uid inválido' };
  }
  if (device !== undefined && (typeof device !== 'string' || device.length > 16)) {
    return { ok: false, error: 'device inválido' };
  }
  if (!Array.isArray(records) || records.length === 0 || records.length > MAX_BATCH) {
    return { ok: false, error: 'records inválidos' };
  }
  for (const r of records) {
    const error = validateRecord(r);
    if (error) return { ok: false, error };
  }
  return { ok: true, batch: { uid, device: device ?? null, records } };
}

/** Documento que se guarda en users/{uid}/history/{id}. */
function buildHistoryDoc(record, device) {
  const startAt = instantOf(record.at);
  return {
    startAt,
    date: dateKey(record.at),
    zone: record.zone,
    outcome: record.outcome,
    reason: record.reason,
    seconds: record.seconds,
    manual: record.manual,
    device: device ?? null,
    expireAt: expiresAt(startAt),
  };
}

/**
 * Cuánto suma un riego al resumen del día. Los riegos omitidos, pospuestos o
 * cancelados no gastan agua; solo "omitidos" y "cancelados" cuentan como agua
 * ahorrada (skipped).
 */
function dailyDelta(record) {
  const watered = WATERED.includes(record.outcome);
  return {
    runs: watered ? 1 : 0,
    seconds: watered ? record.seconds : 0,
    skipped: record.outcome === 'skipped' || record.outcome === 'cancelled' ? 1 : 0,
  };
}

/** Fecha a la que se le suma el riego y su expiración (13 meses del día). */
function dailyDocFor(record) {
  const date = dateKey(record.at);
  return { date, expireAt: expiresAt(dayStartInstant(date)) };
}

/**
 * Datos de prueba (acción de mejora del Sprint 7): riegos simulados de varios
 * meses para probar el historial y las estadísticas sin esperar riegos reales.
 * Determinista: el mismo "seed" produce siempre los mismos riegos.
 * `endDate` es el último día (AAAA-MM-DD, hora local).
 */
function simulateHistory({ endDate, months = 6, seed = 1 }) {
  let state = seed >>> 0 || 1;
  const rand = () => {
    state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
    return state / 4294967296;
  };

  const end = Date.parse(`${endDate}T00:00:00Z`);
  const days = Math.round(months * 30.4);
  const records = [];
  for (let d = days - 1; d >= 0; d--) {
    const dayStart = end - d * DAY_MS;
    // Riego programado: zona 1 a las 06:00 y zona 2 a las 18:30; la zona 1
    // también a las 23:30 los sábados (borde de día).
    const slots = [
      { zone: 1, hour: 6, minute: 0, minutes: 10 },
      { zone: 2, hour: 18, minute: 30, minutes: 8 },
    ];
    if (new Date(dayStart).getUTCDay() === 6) slots.push({ zone: 1, hour: 23, minute: 30, minutes: 6 });

    for (const slot of slots) {
      const at = Math.floor(dayStart / 1000) + slot.hour * 3600 + slot.minute * 60;
      const roll = rand();
      let outcome;
      let reason;
      let seconds = slot.minutes * 60;
      if (roll < 0.15) { outcome = 'skipped'; reason = 'wet'; seconds = 0; }
      else if (roll < 0.25) { outcome = 'reduced'; reason = 'near'; seconds = Math.max(60, Math.round(seconds / 2)); }
      else if (roll < 0.30) { outcome = 'cancelled'; reason = 'rain'; seconds = 0; }
      else if (roll < 0.32) { outcome = 'failed'; reason = 'valve'; seconds = 0; }
      else { outcome = 'done'; reason = roll < 0.6 ? 'dry' : 'none'; }
      records.push({ at, zone: slot.zone, outcome, reason, seconds, manual: false });
    }
  }
  return records;
}

module.exports = {
  LOCAL_OFFSET_SECONDS,
  MAX_BATCH,
  OUTCOMES,
  REASONS,
  RETENTION_DAYS,
  buildHistoryDoc,
  dailyDelta,
  dailyDocFor,
  dateKey,
  dayStartInstant,
  instantOf,
  recordId,
  simulateHistory,
  validateBatch,
  validateRecord,
};
