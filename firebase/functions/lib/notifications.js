'use strict';

const crypto = require('node:crypto');

const EVENT_TYPES = ['start', 'end', 'fail'];
const SOURCES = ['manual', 'schedule'];
const MAX_ZONES = 2;

/** Nombre por defecto de una zona cuando el usuario no la ha renombrado. */
function defaultZoneName(zone) {
  return `Zona ${zone}`;
}

/** Extrae el token de un encabezado "Authorization: Bearer <token>". */
function bearerToken(header) {
  if (typeof header !== 'string' || !header.startsWith('Bearer ')) return null;
  const token = header.slice(7).trim();
  return token.length > 0 ? token : null;
}

/** Compara dos tokens en tiempo constante para no filtrar información por tiempos. */
function tokensEqual(received, stored) {
  if (typeof received !== 'string' || typeof stored !== 'string') return false;
  const a = Buffer.from(received);
  const b = Buffer.from(stored);
  if (a.length !== b.length) return false;
  return crypto.timingSafeEqual(a, b);
}

/**
 * Valida el cuerpo que envía el ESP32. No se confía en el dispositivo:
 * cualquier campo fuera de rango rechaza la petición.
 */
function validateEvent(body) {
  if (body === null || typeof body !== 'object') return { ok: false, error: 'Cuerpo inválido' };
  const { uid, type, zone, source = 'schedule', minutes, device } = body;

  if (typeof uid !== 'string' || uid.length === 0 || uid.length > 128 || uid.includes('/')) {
    return { ok: false, error: 'uid inválido' };
  }
  if (!EVENT_TYPES.includes(type)) return { ok: false, error: 'type inválido' };
  if (!Number.isInteger(zone) || zone < 1 || zone > MAX_ZONES) return { ok: false, error: 'zone inválida' };
  if (!SOURCES.includes(source)) return { ok: false, error: 'source inválido' };
  if (minutes !== undefined && (!Number.isInteger(minutes) || minutes < 0 || minutes > 1440)) {
    return { ok: false, error: 'minutes inválido' };
  }
  if (device !== undefined && (typeof device !== 'string' || device.length > 16)) {
    return { ok: false, error: 'device inválido' };
  }

  return { ok: true, event: { uid, type, zone, source, minutes: minutes ?? null, device: device ?? null } };
}

/** Arma el título y el texto de la notificación que verá el usuario. */
function buildMessage(event, zoneName) {
  const name = zoneName || defaultZoneName(event.zone);
  const manual = event.source === 'manual';

  switch (event.type) {
    case 'start': {
      const base = manual ? 'Encendiste el riego manualmente.' : 'Comenzó el riego programado.';
      const extra = event.minutes ? ` Durará ${event.minutes} min.` : '';
      return { title: `Riego iniciado · ${name}`, body: base + extra, severity: 'info' };
    }
    case 'end': {
      const body = event.minutes ? `La zona regó ${event.minutes} min.` : 'El riego terminó.';
      return { title: `Riego terminado · ${name}`, body, severity: 'info' };
    }
    case 'fail':
    default:
      return {
        title: `Falla en ${name}`,
        body: 'La válvula no respondió y la zona se apagó por seguridad. Revisa la conexión.',
        severity: 'error',
      };
  }
}

/** Códigos de FCM que indican que un token ya no sirve y debe borrarse. */
const STALE_TOKEN_CODES = [
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
];

module.exports = {
  EVENT_TYPES,
  MAX_ZONES,
  STALE_TOKEN_CODES,
  bearerToken,
  buildMessage,
  defaultZoneName,
  tokensEqual,
  validateEvent,
};
