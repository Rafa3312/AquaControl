'use strict';

const { onRequest } = require('firebase-functions/v2/https');
const logger = require('firebase-functions/logger');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');
const {
  STALE_TOKEN_CODES,
  bearerToken,
  buildMessage,
  defaultZoneName,
  tokensEqual,
  validateEvent,
} = require('./lib/notifications');
const { validateBatch } = require('./lib/history');
const { saveRecords } = require('./lib/history_store');

initializeApp();
const db = getFirestore();

/**
 * Recibe los avisos de inicio, fin y falla del riego que envía el ESP32,
 * los guarda en users/{uid}/notifications y, si el usuario dio su
 * consentimiento, envía la notificación push con Firebase Cloud Messaging.
 *
 * El ESP32 se autentica con el mismo token Bearer de la vinculación, que se
 * compara contra devices/{uid}.token.
 */
exports.deviceEvent = onRequest({ region: 'us-central1', maxInstances: 5 }, async (req, res) => {
  if (req.method !== 'POST') {
    res.status(405).json({ ok: false, error: 'Método no permitido' });
    return;
  }

  const token = bearerToken(req.get('Authorization'));
  if (!token) {
    res.status(401).json({ ok: false, error: 'Token requerido' });
    return;
  }

  const parsed = validateEvent(req.body);
  if (!parsed.ok) {
    res.status(400).json({ ok: false, error: parsed.error });
    return;
  }
  const event = parsed.event;

  try {
    const device = await db.doc(`devices/${event.uid}`).get();
    if (!device.exists || !tokensEqual(token, device.get('token'))) {
      // No se registra el token: solo el uid para poder investigar
      logger.warn('Aviso rechazado: dispositivo no autorizado', { uid: event.uid });
      res.status(401).json({ ok: false, error: 'Dispositivo no autorizado' });
      return;
    }

    // zona 0 = sensor general de lluvia: no tiene nombre de zona
    const zone = event.zone === 0 ? null : await db.doc(`users/${event.uid}/zones/${event.zone}`).get();
    const zoneName = event.zone === 0
      ? 'Sensor de lluvia'
      : zone.get('name') || defaultZoneName(event.zone);
    const message = buildMessage(event, zoneName);

    await db.collection(`users/${event.uid}/notifications`).add({
      type: event.type,
      zone: event.zone,
      zoneName,
      source: event.source,
      minutes: event.minutes,
      moisture: event.moisture,
      threshold: event.threshold,
      title: message.title,
      body: message.body,
      severity: message.severity,
      createdAt: FieldValue.serverTimestamp(),
    });

    let sent = 0;
    const user = await db.doc(`users/${event.uid}`).get();
    if (user.get('notificationsEnabled') === true) {
      const snapshot = await db.collection(`users/${event.uid}/fcmTokens`).get();
      const tokens = snapshot.docs.map((d) => d.id);
      if (tokens.length > 0) {
        const response = await getMessaging().sendEachForMulticast({
          tokens,
          notification: { title: message.title, body: message.body },
          data: { type: event.type, zone: String(event.zone) },
          android: { priority: message.severity === 'error' ? 'high' : 'normal' },
        });
        sent = response.successCount;

        const stale = response.responses
          .map((r, i) => (!r.success && STALE_TOKEN_CODES.includes(r.error?.code) ? tokens[i] : null))
          .filter(Boolean);
        await Promise.all(stale.map((t) => db.doc(`users/${event.uid}/fcmTokens/${t}`).delete()));
      }
    }

    logger.info('Aviso procesado', { uid: event.uid, type: event.type, zone: event.zone, sent });
    res.json({ ok: true, sent });
  } catch (err) {
    logger.error('Error al procesar el aviso', { uid: event.uid, error: err.message });
    res.status(500).json({ ok: false, error: 'Error interno' });
  }
});

/**
 * Recibe el historial de riegos que guarda el ESP32 en su memoria (Sprint 8,
 * HU-14) y lo escribe en users/{uid}/history y en el resumen diario
 * users/{uid}/dailyStats (HU-16).
 *
 * Es idempotente: cada riego tiene un identificador propio (hora, zona y
 * resultado). Si el ESP32 reenvía un lote después de una desconexión, los
 * riegos que ya existen se cuentan como duplicados y no se suman dos veces.
 */
exports.deviceHistory = onRequest({ region: 'us-central1', maxInstances: 5 }, async (req, res) => {
  if (req.method !== 'POST') {
    res.status(405).json({ ok: false, error: 'Método no permitido' });
    return;
  }

  const token = bearerToken(req.get('Authorization'));
  if (!token) {
    res.status(401).json({ ok: false, error: 'Token requerido' });
    return;
  }

  const parsed = validateBatch(req.body);
  if (!parsed.ok) {
    res.status(400).json({ ok: false, error: parsed.error });
    return;
  }
  const { uid, device, records } = parsed.batch;

  try {
    const owner = await db.doc(`devices/${uid}`).get();
    if (!owner.exists || !tokensEqual(token, owner.get('token'))) {
      logger.warn('Historial rechazado: dispositivo no autorizado', { uid });
      res.status(401).json({ ok: false, error: 'Dispositivo no autorizado' });
      return;
    }

    const { saved, duplicates } = await saveRecords(db, FieldValue, uid, device, records);

    logger.info('Historial procesado', { uid, saved, duplicates });
    res.json({ ok: true, saved, duplicates });
  } catch (err) {
    logger.error('Error al procesar el historial', { uid, error: err.message });
    res.status(500).json({ ok: false, error: 'Error interno' });
  }
});
