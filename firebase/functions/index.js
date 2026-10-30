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

    const zone = await db.doc(`users/${event.uid}/zones/${event.zone}`).get();
    const zoneName = zone.get('name') || defaultZoneName(event.zone);
    const message = buildMessage(event, zoneName);

    await db.collection(`users/${event.uid}/notifications`).add({
      type: event.type,
      zone: event.zone,
      zoneName,
      source: event.source,
      minutes: event.minutes,
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
          android: { priority: event.type === 'fail' ? 'high' : 'normal' },
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
