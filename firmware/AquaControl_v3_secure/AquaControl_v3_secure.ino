/**
 * ============================================================
 *  AquaControl – Firmware ESP32  v3.2  (Multizona + Avisos)
 * ============================================================
 *
 *  Hardware:
 *    ESP32 + RTC DS3231 (SDA=21, SCL=22)
 *    Relé / MOSFET zona 1 = GPIO23   ·   zona 2 = GPIO19
 *    Sensores de retroalimentación opcionales (corriente o flujo):
 *      zona 1 = GPIO34 · zona 2 = GPIO35 (solo entrada, usar pull-down externo)
 *    LED integrado = GPIO2
 *
 *  Librerías (Herramientas → Administrar bibliotecas):
 *    - RTClib       by Adafruit
 *    - ArduinoJson  by Benoît Blanchon  (>= 7.0)
 *
 *  PRIMERA VEZ: el ESP crea red WiFi "AquaControl-XXXXXX"
 *  La contraseña y el Reset PIN aparecen en Monitor Serial (115200).
 *
 * ============================================================
 */

#include <WiFi.h>
#include <WebServer.h>
#include <ESPmDNS.h>
#include <DNSServer.h>
#include <Preferences.h>
#include <Wire.h>
#include <RTClib.h>
#include <ArduinoJson.h>
#include <HTTPClient.h>
#include <WiFiClientSecure.h>
#include <esp_system.h>
#include <esp_random.h>
#include <time.h>

// ─── Configuración ───────────────────────────────────────────────────────────
#define FW_VERSION         "3.2"
#define MDNS_NAME          "aquacontrol"
#define SDA_PIN            21
#define SCL_PIN            22
#define LED_PIN            2
#define MAX_SCHEDULES      10
#define WIFI_TIMEOUT_MS    30000
#define WIFI_MAX_RETRIES   3
#define MAX_PAIR_ATTEMPTS  5
#define LOCKOUT_MS         (5UL * 60 * 1000)
#define MIN_TOKEN_LEN      32
#define PRODUCTION_MODE    true
// Zona horaria: UTC-6 México Centro = -21600 | UTC-5 = -18000 | UTC-7 = -25200
#define TZ_OFFSET_SECONDS  -21600

// ─── Zonas ───────────────────────────────────────────────────────────────────
#define ZONE_COUNT         2
const uint8_t ZONE_PINS[ZONE_COUNT]       = {23, 19};
const uint8_t ZONE_SENSE_PINS[ZONE_COUNT] = {34, 35};
// true solo si cada zona tiene sensor de retroalimentación conectado;
// sin sensor, las entradas quedan flotando y se detectarían fallas falsas.
#define FAULT_DETECTION    false
#define FAULT_CHECK_MS     4000          // tiempo para que la válvula responda
#define MAX_MANUAL_MIN     120           // riego manual máximo (min)
#define MAX_SCHEDULE_MIN   120           // duración máxima de una programación (min)

// ─── Avisos (notificaciones) ─────────────────────────────────────────────────
// URL de la Cloud Function deviceEvent. Vacía = avisos desactivados.
// Ej: "https://us-central1-<id-del-proyecto>.cloudfunctions.net/deviceEvent"
#define EVENT_URL          ""
#define EVENT_QUEUE_SIZE   8
#define EVENT_MAX_ATTEMPTS 3
#define EVENT_RETRY_MS     30000

// Certificados raíz de Google Trust Services (GTS Root R1 y R4, vigentes a 2036)
// para validar el HTTPS de Cloud Functions. Fuente: https://pki.goog/repository/
static const char GOOGLE_ROOT_CAS[] PROGMEM = R"PEM(
-----BEGIN CERTIFICATE-----
MIIFVzCCAz+gAwIBAgINAgPlk28xsBNJiGuiFzANBgkqhkiG9w0BAQwFADBHMQsw
CQYDVQQGEwJVUzEiMCAGA1UEChMZR29vZ2xlIFRydXN0IFNlcnZpY2VzIExMQzEU
MBIGA1UEAxMLR1RTIFJvb3QgUjEwHhcNMTYwNjIyMDAwMDAwWhcNMzYwNjIyMDAw
MDAwWjBHMQswCQYDVQQGEwJVUzEiMCAGA1UEChMZR29vZ2xlIFRydXN0IFNlcnZp
Y2VzIExMQzEUMBIGA1UEAxMLR1RTIFJvb3QgUjEwggIiMA0GCSqGSIb3DQEBAQUA
A4ICDwAwggIKAoICAQC2EQKLHuOhd5s73L+UPreVp0A8of2C+X0yBoJx9vaMf/vo
27xqLpeXo4xL+Sv2sfnOhB2x+cWX3u+58qPpvBKJXqeqUqv4IyfLpLGcY9vXmX7w
Cl7raKb0xlpHDU0QM+NOsROjyBhsS+z8CZDfnWQpJSMHobTSPS5g4M/SCYe7zUjw
TcLCeoiKu7rPWRnWr4+wB7CeMfGCwcDfLqZtbBkOtdh+JhpFAz2weaSUKK0Pfybl
qAj+lug8aJRT7oM6iCsVlgmy4HqMLnXWnOunVmSPlk9orj2XwoSPwLxAwAtcvfaH
szVsrBhQf4TgTM2S0yDpM7xSma8ytSmzJSq0SPly4cpk9+aCEI3oncKKiPo4Zor8
Y/kB+Xj9e1x3+naH+uzfsQ55lVe0vSbv1gHR6xYKu44LtcXFilWr06zqkUspzBmk
MiVOKvFlRNACzqrOSbTqn3yDsEB750Orp2yjj32JgfpMpf/VjsPOS+C12LOORc92
wO1AK/1TD7Cn1TsNsYqiA94xrcx36m97PtbfkSIS5r762DL8EGMUUXLeXdYWk70p
aDPvOmbsB4om3xPXV2V4J95eSRQAogB/mqghtqmxlbCluQ0WEdrHbEg8QOB+DVrN
VjzRlwW5y0vtOUucxD/SVRNuJLDWcfr0wbrM7Rv1/oFB2ACYPTrIrnqYNxgFlQID
AQABo0IwQDAOBgNVHQ8BAf8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4E
FgQU5K8rJnEaK0gnhS9SZizv8IkTcT4wDQYJKoZIhvcNAQEMBQADggIBAJ+qQibb
C5u+/x6Wki4+omVKapi6Ist9wTrYggoGxval3sBOh2Z5ofmmWJyq+bXmYOfg6LEe
QkEzCzc9zolwFcq1JKjPa7XSQCGYzyI0zzvFIoTgxQ6KfF2I5DUkzps+GlQebtuy
h6f88/qBVRRiClmpIgUxPoLW7ttXNLwzldMXG+gnoot7TiYaelpkttGsN/H9oPM4
7HLwEXWdyzRSjeZ2axfG34arJ45JK3VmgRAhpuo+9K4l/3wV3s6MJT/KYnAK9y8J
ZgfIPxz88NtFMN9iiMG1D53Dn0reWVlHxYciNuaCp+0KueIHoI17eko8cdLiA6Ef
MgfdG+RCzgwARWGAtQsgWSl4vflVy2PFPEz0tv/bal8xa5meLMFrUKTX5hgUvYU/
Z6tGn6D/Qqc6f1zLXbBwHSs09dR2CQzreExZBfMzQsNhFRAbd03OIozUhfJFfbdT
6u9AWpQKXCBfTkBdYiJ23//OYb2MI3jSNwLgjt7RETeJ9r/tSQdirpLsQBqvFAnZ
0E6yove+7u7Y/9waLd64NnHi/Hm3lCXRSHNboTXns5lndcEZOitHTtNCjv0xyBZm
2tIMPNuzjsmhDYAPexZ3FL//2wmUspO8IFgV6dtxQ/PeEMMA3KgqlbbC1j+Qa3bb
bP6MvPJwNQzcmRk13NfIRmPVNnGuV/u3gm3c
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIICCTCCAY6gAwIBAgINAgPlwGjvYxqccpBQUjAKBggqhkjOPQQDAzBHMQswCQYD
VQQGEwJVUzEiMCAGA1UEChMZR29vZ2xlIFRydXN0IFNlcnZpY2VzIExMQzEUMBIG
A1UEAxMLR1RTIFJvb3QgUjQwHhcNMTYwNjIyMDAwMDAwWhcNMzYwNjIyMDAwMDAw
WjBHMQswCQYDVQQGEwJVUzEiMCAGA1UEChMZR29vZ2xlIFRydXN0IFNlcnZpY2Vz
IExMQzEUMBIGA1UEAxMLR1RTIFJvb3QgUjQwdjAQBgcqhkjOPQIBBgUrgQQAIgNi
AATzdHOnaItgrkO4NcWBMHtLSZ37wWHO5t5GvWvVYRg1rkDdc/eJkTBa6zzuhXyi
QHY7qca4R9gq55KRanPpsXI5nymfopjTX15YhmUPoYRlBtHci8nHc8iMai/lxKvR
HYqjQjBAMA4GA1UdDwEB/wQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQW
BBSATNbrdP9JNqPV2Py1PsVq8JQdjDAKBggqhkjOPQQDAwNpADBmAjEA6ED/g94D
9J+uHXqnLrmvT/aDHQ4thQEd0dlq7A/Cr8deVl5c1RxYIigL9zC2L7F8AjEA8GE8
p/SgguMh1YQdc4acLa/KNJvxn7kjNuK8YAOdgLOaVsjh4rsUecrNIdSUtUlD
-----END CERTIFICATE-----
)PEM";

// ─── Objetos ─────────────────────────────────────────────────────────────────
WebServer   server(80);
DNSServer   dnsServer;
RTC_DS3231  rtc;
Preferences prefs;

// ─── Estructura de programación ──────────────────────────────────────────────
#define SCHED_VERSION 2
struct Schedule {
  bool     active;
  uint8_t  days;
  uint8_t  startHour;
  uint8_t  startMinute;
  uint16_t durationMin;
  char     id[37];
  uint8_t  zone;          // 1..ZONE_COUNT
};
// Formato guardado por el firmware v3.1 (sin zona), solo para migrar.
struct ScheduleV1 {
  bool     active;
  uint8_t  days;
  uint8_t  startHour;
  uint8_t  startMinute;
  uint16_t durationMin;
  char     id[37];
};
Schedule schedules[MAX_SCHEDULES];
int      scheduleCount = 0;

// ─── Estado runtime por zona ─────────────────────────────────────────────────
struct ZoneState {
  bool          active;
  bool          manual;
  bool          timed;        // tiene hora de apagado automático
  bool          fault;        // última activación falló
  DateTime      stopAt;
  DateTime      startedAt;
  unsigned long onSinceMs;
  int           lastFiredMin;   // evita disparar dos veces la misma
  int           lastFiredIdx;   // programación en su ventana de ±1 min
  int32_t       lastFiredDate;  // AAAAMMDD del último disparo
};
ZoneState zones[ZONE_COUNT];

// ─── Cola de avisos ──────────────────────────────────────────────────────────
enum EventType : uint8_t { EV_START, EV_END, EV_FAIL };
struct PendingEvent {
  uint8_t       type;
  uint8_t       zone;          // 1..ZONE_COUNT
  bool          manual;
  uint16_t      minutes;
  uint8_t       attempts;
  unsigned long notBefore;
};
PendingEvent eventQueue[EVENT_QUEUE_SIZE];
int          eventHead  = 0;
int          eventCount = 0;

// ─── Datos sensibles ─────────────────────────────────────────────────────────
String   wifiSSID       = "";
String   wifiPassword   = "";
String   authToken      = "";
String   linkedUID      = "";
String   apPassword     = "";

// ─── Modos ───────────────────────────────────────────────────────────────────
enum Mode { MODE_SETUP, MODE_NORMAL };
Mode currentMode = MODE_NORMAL;

// ─── Rate limiting ───────────────────────────────────────────────────────────
int           pairAttempts    = 0;
unsigned long pairLockedUntil = 0;
int           pinAttempts     = 0;
unsigned long pinLockedUntil  = 0;

// ── Seguridad ─────────────────────────────────────────────────────────────────
bool   checkToken();
bool   timingSafeCompare(const String& a, const String& b);
String xorEncryptDecrypt(const String& data, const String& key);
String getDeviceKey();
String getDeviceShortId();
String getResetPin();
String generateRandomString(int len);

// ── Persistencia ──────────────────────────────────────────────────────────────
void   saveSecure(const char* ns, const char* key, const String& value);
String loadSecure(const char* ns, const char* key);
void   saveSchedules();
void   loadSchedules();

// ── Riego ─────────────────────────────────────────────────────────────────────
bool validZone(int zone);
void encenderZona(uint8_t z, bool manual, uint16_t minutes);
void apagarZona(uint8_t z, bool notify);
void apagarTodas(bool notify);
bool anyZoneActive();
void checkStop();
void checkSchedules();
void checkFaults();
int  getDayBit(int dow);
void syncNTP();

// ── Avisos ────────────────────────────────────────────────────────────────────
void queueEvent(uint8_t type, uint8_t zone, bool manual, uint16_t minutes);
void processEvents();
bool postEvent(const PendingEvent& e);

// ── HTTP ──────────────────────────────────────────────────────────────────────
void sendJson(int code, JsonDocument& doc);
void sendError(int code, const char* msg);
void blinkLED(int times);
void logSecure(const char* event);
String formatTime(const DateTime& t);

// ══════════════════════════════════════════════════════════════════════════════
void setup() {
  Serial.begin(115200);
  delay(300);

  Serial.println(F("\n╔═══════════════════════════════════╗"));
  Serial.println(F("║  AquaControl  Firmware v3.2       ║"));
  Serial.println(F("╚═══════════════════════════════════╝"));
  Serial.printf("Device ID:  %s\n", getDeviceShortId().c_str());
  Serial.printf("Reset PIN:  %s  <- anota este numero\n", getResetPin().c_str());

  for (int z = 0; z < ZONE_COUNT; z++) {
    pinMode(ZONE_PINS[z], OUTPUT);
    digitalWrite(ZONE_PINS[z], LOW);
    if (FAULT_DETECTION) pinMode(ZONE_SENSE_PINS[z], INPUT);
    zones[z] = ZoneState();
    zones[z].lastFiredMin = zones[z].lastFiredIdx = zones[z].lastFiredDate = -1;
  }
  pinMode(LED_PIN, OUTPUT);

  Wire.begin(SDA_PIN, SCL_PIN);
  if (!rtc.begin()) {
    Serial.println(F("[ERROR] RTC no detectado. Verifica SDA=21 SCL=22"));
    while (1) { blinkLED(3); delay(1000); }
  }
  if (rtc.lostPower()) {
    rtc.adjust(DateTime(F(__DATE__), F(__TIME__)));
    Serial.println(F("[RTC] Ajustado con fecha de compilacion"));
  }
  DateTime now = rtc.now();
  Serial.printf("[RTC] %02d/%02d/%04d %02d:%02d:%02d\n",
    now.day(), now.month(), now.year(), now.hour(), now.minute(), now.second());

  loadSchedules();
  authToken = loadSecure("aqua-auth", "token");
  linkedUID = loadSecure("aqua-auth", "uid");

  wifiSSID     = loadSecure("aqua-wifi", "ssid");
  wifiPassword = loadSecure("aqua-wifi", "pass");

  if (wifiSSID.length() > 0) {
    Serial.println(F("[Boot] WiFi encontrado -> modo NORMAL"));

    WiFi.mode(WIFI_STA);
    WiFi.setAutoReconnect(true);
    WiFi.persistent(false);

    bool connected = false;
    for (int attempt = 1; attempt <= WIFI_MAX_RETRIES; attempt++) {
      Serial.printf("[WiFi] Intento %d/%d -> %s", attempt, WIFI_MAX_RETRIES, wifiSSID.c_str());
      WiFi.begin(wifiSSID.c_str(), wifiPassword.c_str());
      unsigned long start = millis();
      while (WiFi.status() != WL_CONNECTED && millis() - start < WIFI_TIMEOUT_MS) {
        delay(500); Serial.print(".");
      }
      if (WiFi.status() == WL_CONNECTED) { connected = true; break; }
      Serial.printf("\n[WiFi] Intento %d fallido (status=%d)\n", attempt, WiFi.status());
      WiFi.disconnect(true); delay(2000);
    }

    if (!connected) {
      Serial.println(F("\n[WiFi] Sin conexion tras todos los intentos. SETUP temporal."));
      Serial.println(F("[WiFi] Credenciales conservadas para el proximo reinicio."));
      goto start_setup;
    }

    currentMode = MODE_NORMAL;
    Serial.printf("\n[WiFi] OK -> IP: %s\n", WiFi.localIP().toString().c_str());
    syncNTP();

    if (MDNS.begin(MDNS_NAME)) {
      MDNS.addService("http", "tcp", 80);
      Serial.printf("[mDNS] http://%s.local\n", MDNS_NAME);
    }

    // Registrar rutas modo normal
    const char* headers[] = {"Authorization", "Content-Type"};
    server.collectHeaders(headers, 2);

    server.on("/status", HTTP_GET, []() {
      JsonDocument doc;
      DateTime now = rtc.now();
      doc["online"]    = true;
      doc["valve"]     = anyZoneActive();
      bool anyManual = false;
      for (int z = 0; z < ZONE_COUNT; z++) anyManual |= zones[z].active && zones[z].manual;
      doc["manual"]    = anyManual;
      doc["paired"]    = !authToken.isEmpty();
      doc["mode"]      = "normal";
      doc["device"]    = getDeviceShortId();
      doc["firmware"]  = FW_VERSION;
      doc["schedules"] = scheduleCount;
      doc["zoneCount"] = ZONE_COUNT;
      doc["ip"]        = WiFi.localIP().toString();
      if (!authToken.isEmpty()) doc["uid"] = linkedUID;
      char buf[24];
      snprintf(buf, sizeof(buf), "%04d-%02d-%02dT%02d:%02d:%02d",
        now.year(), now.month(), now.day(), now.hour(), now.minute(), now.second());
      doc["rtc"] = buf;

      JsonArray arr = doc["zones"].to<JsonArray>();
      for (int z = 0; z < ZONE_COUNT; z++) {
        JsonObject o = arr.add<JsonObject>();
        o["id"]     = z + 1;
        o["valve"]  = zones[z].active;
        o["manual"] = zones[z].active && zones[z].manual;
        o["fault"]  = zones[z].fault;
        if (zones[z].active && zones[z].timed) o["stopAt"] = formatTime(zones[z].stopAt);
      }
      // Compatibilidad con la app v1: hora de apagado de la primera zona temporizada
      for (int z = 0; z < ZONE_COUNT; z++) {
        if (zones[z].active && zones[z].timed) { doc["stopAt"] = formatTime(zones[z].stopAt); break; }
      }
      sendJson(200, doc);
    });

    server.on("/pair", HTTP_POST, []() {
      if (millis() < pairLockedUntil) {
        JsonDocument d; d["ok"]=false; d["error"]="Rate limit. Espera 5 min.";
        d["lockedSeconds"]=(pairLockedUntil-millis())/1000; sendJson(429,d); return;
      }
      if (!authToken.isEmpty()) { sendError(403, "Ya vinculado"); return; }
      if (!server.hasArg("plain")) { sendError(400, "Body vacio"); return; }
      JsonDocument doc;
      if (deserializeJson(doc, server.arg("plain"))) { sendError(400,"JSON invalido"); return; }
      const char* token = doc["token"]|"";
      const char* uid   = doc["uid"]|"";
      if (strlen(token) < MIN_TOKEN_LEN) {
        pairAttempts++;
        if (pairAttempts >= MAX_PAIR_ATTEMPTS) { pairLockedUntil=millis()+LOCKOUT_MS; pairAttempts=0; logSecure("pair_locked"); }
        sendError(400,"Token corto"); return;
      }
      if (strlen(uid)==0) { sendError(400,"UID requerido"); return; }
      authToken=String(token); linkedUID=String(uid);
      saveSecure("aqua-auth","token",authToken); saveSecure("aqua-auth","uid",linkedUID);
      pairAttempts=0; pairLockedUntil=0; logSecure("paired_new"); blinkLED(10);
      JsonDocument res; res["ok"]=true; res["device"]=getDeviceShortId();
      sendJson(200,res);
    });

    // Body: {"zone": 1..ZONE_COUNT (opcional, 1 por defecto), "duration": 0..MAX_MANUAL_MIN}
    server.on("/on", HTTP_POST, []() {
      if (!checkToken()) return;
      JsonDocument doc;
      if (server.hasArg("plain") && deserializeJson(doc, server.arg("plain"))) { sendError(400,"JSON invalido"); return; }
      int zone = doc["zone"]|1;
      int dur  = doc["duration"]|0;
      if (!validZone(zone)) { sendError(400,"Zona invalida"); return; }
      if (dur < 0 || dur > MAX_MANUAL_MIN) { sendError(400,"Duracion invalida"); return; }
      uint8_t z = zone - 1;
      if (zones[z].active) {
        JsonDocument r; r["ok"]=false; r["zone"]=zone; r["valve"]=true; r["message"]="Ya encendido"; sendJson(200,r); return;
      }
      encenderZona(z, true, dur);
      JsonDocument r; r["ok"]=true; r["zone"]=zone; r["valve"]=true; r["duration"]=dur; sendJson(200,r);
    });

    // Body: {"zone": 1..ZONE_COUNT}. Sin zona apaga todas (compatibilidad v1).
    server.on("/off", HTTP_POST, []() {
      if (!checkToken()) return;
      JsonDocument doc;
      if (server.hasArg("plain") && deserializeJson(doc, server.arg("plain"))) { sendError(400,"JSON invalido"); return; }
      JsonDocument r; r["ok"]=true; r["valve"]=false;
      if (doc["zone"].is<int>()) {
        int zone = doc["zone"];
        if (!validZone(zone)) { sendError(400,"Zona invalida"); return; }
        apagarZona(zone - 1, true);
        r["zone"] = zone;
      } else {
        apagarTodas(true);
      }
      sendJson(200,r);
    });

    server.on("/schedules", HTTP_GET, []() {
      if (!checkToken()) return;
      JsonDocument doc;
      JsonArray arr = doc["schedules"].to<JsonArray>();
      for (int i=0;i<scheduleCount;i++) {
        JsonObject s=arr.add<JsonObject>();
        s["id"]=schedules[i].id; s["active"]=schedules[i].active;
        s["days"]=schedules[i].days; s["startHour"]=schedules[i].startHour;
        s["startMinute"]=schedules[i].startMinute; s["duration"]=schedules[i].durationMin;
        s["zone"]=schedules[i].zone;
      }
      doc["count"]=scheduleCount; sendJson(200,doc);
    });

    // Reemplaza todas las programaciones. Se valida todo antes de guardar:
    // la app no es frontera de confianza.
    server.on("/schedules", HTTP_POST, []() {
      if (!checkToken()) return;
      if (!server.hasArg("plain")) { sendError(400,"Body vacio"); return; }
      JsonDocument doc;
      if (deserializeJson(doc,server.arg("plain"))) { sendError(400,"JSON invalido"); return; }
      JsonArray arr = doc["schedules"].as<JsonArray>();
      if (arr.isNull()) { sendError(400,"schedules requerido"); return; }
      if (arr.size() > MAX_SCHEDULES) { sendError(400,"Maximo 10 programaciones"); return; }
      for (JsonObject s:arr) {
        int zone = s["zone"]|1, hour = s["startHour"]|0, minute = s["startMinute"]|0, dur = s["duration"]|20;
        if (!validZone(zone)) { sendError(400,"Zona invalida"); return; }
        if (hour < 0 || hour > 23 || minute < 0 || minute > 59) { sendError(400,"Hora invalida"); return; }
        if (dur < 1 || dur > MAX_SCHEDULE_MIN) { sendError(400,"Duracion invalida"); return; }
      }
      scheduleCount=0;
      for (JsonObject s:arr) {
        Schedule& sc=schedules[scheduleCount];
        sc.active=s["active"]|false; sc.days=s["days"]|127;
        sc.startHour=s["startHour"]|0; sc.startMinute=s["startMinute"]|0;
        sc.durationMin=s["duration"]|20; sc.zone=s["zone"]|1;
        strlcpy(sc.id,s["id"]|"",sizeof(sc.id)); scheduleCount++;
      }
      saveSchedules();
      JsonDocument r; r["ok"]=true; r["count"]=scheduleCount; sendJson(200,r);
    });

    server.on("/schedules/delete", HTTP_POST, []() {
      if (!checkToken()) return;
      if (!server.hasArg("plain")) { sendError(400,"Body vacio"); return; }
      JsonDocument doc; deserializeJson(doc,server.arg("plain"));
      const char* id=doc["id"]|"";
      for (int i=0;i<scheduleCount;i++) {
        if (strcmp(schedules[i].id,id)==0) {
          for (int j=i;j<scheduleCount-1;j++) schedules[j]=schedules[j+1];
          scheduleCount--; saveSchedules();
          JsonDocument r; r["ok"]=true; sendJson(200,r); return;
        }
      }
      sendError(404,"No encontrada");
    });

    // Solo una programación activa POR ZONA: activar una desactiva las demás de su zona.
    server.on("/schedules/active", HTTP_POST, []() {
      if (!checkToken()) return;
      if (!server.hasArg("plain")) { sendError(400,"Body vacio"); return; }
      JsonDocument doc; deserializeJson(doc,server.arg("plain"));
      const char* id=doc["id"]|""; bool active=doc["active"]|false;
      int target=-1;
      for (int i=0;i<scheduleCount;i++) if (strcmp(schedules[i].id,id)==0) { target=i; break; }
      if (target<0) { sendError(404,"No encontrada"); return; }
      if (active) {
        for (int i=0;i<scheduleCount;i++) if (schedules[i].zone==schedules[target].zone) schedules[i].active=false;
      }
      schedules[target].active=active;
      saveSchedules();
      JsonDocument r; r["ok"]=true; r["zone"]=schedules[target].zone; sendJson(200,r);
    });

    server.on("/reset", HTTP_POST, []() {
      if (!checkToken()) return;
      if (!server.hasArg("plain")) { sendError(400,"Body vacio"); return; }
      JsonDocument doc; deserializeJson(doc,server.arg("plain"));
      if (!timingSafeCompare(String(doc["pin"]|""), getResetPin())) {
        logSecure("reset_bad_pin"); sendError(403,"PIN incorrecto"); return;
      }
      apagarTodas(false);
      prefs.begin("aqua-auth",false);  prefs.clear(); prefs.end();
      prefs.begin("aqua-sched",false); prefs.clear(); prefs.end();
      prefs.begin("aqua-wifi",false);  prefs.clear(); prefs.end();
      logSecure("factory_reset_full");
      JsonDocument r; r["ok"]=true; r["message"]="Reset completo"; sendJson(200,r);
      delay(1000); ESP.restart();
    });

    server.on("/reset-pin", HTTP_POST, []() {
      if (millis()<pinLockedUntil) { sendError(429,"Demasiados intentos"); return; }
      if (!server.hasArg("plain")) { sendError(400,"Body vacio"); return; }
      JsonDocument doc;
      if (deserializeJson(doc,server.arg("plain"))) { sendError(400,"JSON invalido"); return; }
      if (!timingSafeCompare(String(doc["pin"]|""), getResetPin())) {
        pinAttempts++;
        logSecure("reset_pin_bad");
        if (pinAttempts>=5) { pinLockedUntil=millis()+LOCKOUT_MS; pinAttempts=0; }
        sendError(403,"PIN incorrecto"); return;
      }
      pinAttempts=0; pinLockedUntil=0;
      apagarTodas(false);
      prefs.begin("aqua-auth",false);  prefs.clear(); prefs.end();
      prefs.begin("aqua-sched",false); prefs.clear(); prefs.end();
      // NO borrar WiFi — solo desvincular token
      logSecure("reset_pin_ok");
      JsonDocument r; r["ok"]=true; r["message"]="Token borrado. Listo para vincular."; sendJson(200,r);
      delay(800); ESP.restart();
    });

    server.on("/sync-time", HTTP_POST, []() {
      if (!checkToken()) return;
      syncNTP();
      DateTime now=rtc.now(); char buf[24];
      snprintf(buf,sizeof(buf),"%04d-%02d-%02dT%02d:%02d:%02d",
        now.year(),now.month(),now.day(),now.hour(),now.minute(),now.second());
      JsonDocument r; r["ok"]=true; r["rtc"]=buf; sendJson(200,r);
    });

    server.onNotFound([]() { sendError(404,"No encontrado"); });
    server.begin();
    Serial.println(F("[HTTP] Servidor en puerto 80"));
    Serial.printf("[Zonas] %d zonas configuradas\n", ZONE_COUNT);
    if (strlen(EVENT_URL) == 0) Serial.println(F("[Avisos] EVENT_URL vacia: notificaciones desactivadas"));
    blinkLED(5);
    if (authToken.isEmpty()) Serial.println(F("[Sec] Sin vincular. Esperando /pair."));
    else logSecure("boot_ok");
    return;
  }

start_setup:
  // ── MODO SETUP ────────────────────────────────────────────────────────────
  currentMode = MODE_SETUP;
  apPassword  = generateRandomString(10);
  String apSsid = String("AquaControl-") + getDeviceShortId();
  WiFi.mode(WIFI_AP);
  WiFi.softAP(apSsid.c_str(), apPassword.c_str());
  IPAddress apIp = WiFi.softAPIP();

  Serial.println(F("\n┌────────────────────────────────────────┐"));
  Serial.println(F("│       MODO DE CONFIGURACION            │"));
  Serial.println(F("├────────────────────────────────────────┤"));
  Serial.printf ("│ SSID:     %-28s │\n", apSsid.c_str());
  Serial.printf ("│ Password: %-28s │\n", apPassword.c_str());
  Serial.printf ("│ IP:       %-28s │\n", apIp.toString().c_str());
  Serial.println(F("└────────────────────────────────────────┘"));

  dnsServer.start(53, "*", apIp);

  server.on("/", HTTP_GET, []() {
    server.send(200,"text/html",
      "<!DOCTYPE html><html><head><meta charset='utf-8'>"
      "<meta name='viewport' content='width=device-width,initial-scale=1'>"
      "<title>AquaControl Setup</title>"
      "<style>body{font-family:sans-serif;background:#061422;color:#fff;padding:24px;}"
      "h1{color:#0EA5E9;}input,button{width:100%;padding:14px;margin:8px 0;"
      "border-radius:10px;border:1px solid #1E3A5F;background:#112240;color:#fff;}"
      "button{background:#0EA5E9;border:none;font-weight:600;font-size:16px;}"
      "p{color:#94A3B8;font-size:13px;}</style></head><body>"
      "<h1>AquaControl</h1><h3>Configurar WiFi</h3>"
      "<p>Solo redes 2.4 GHz. El ESP32 no soporta 5 GHz.</p>"
      "<form action='/setup' method='POST'>"
      "<input name='ssid' placeholder='Nombre de tu red WiFi' required>"
      "<input name='pass' placeholder='Contrasena WiFi' type='password' required>"
      "<button type='submit'>Verificar y guardar</button>"
      "</form></body></html>");
  });

  server.on("/setup/info", HTTP_GET, []() {
    JsonDocument d; d["mode"]="setup"; d["device"]=getDeviceShortId(); sendJson(200,d);
  });

  server.on("/setup", HTTP_POST, []() {
    if (!server.hasArg("ssid")||!server.hasArg("pass")) { sendError(400,"ssid y pass requeridos"); return; }
    String ssid=server.arg("ssid"), pass=server.arg("pass");
    if (ssid.length()<1||ssid.length()>32) { sendError(400,"SSID invalido"); return; }
    if (pass.length()<8||pass.length()>63) { sendError(400,"Contrasena 8-63 caracteres"); return; }

    Serial.printf("[Setup] Verificando: %s\n", ssid.c_str());
    WiFi.mode(WIFI_AP_STA);
    WiFi.begin(ssid.c_str(), pass.c_str());
    Serial.print("[Setup] Probando");
    unsigned long start=millis();
    while (WiFi.status()!=WL_CONNECTED && millis()-start<20000) { delay(500); Serial.print("."); }

    if (WiFi.status()!=WL_CONNECTED) {
      WiFi.mode(WIFI_AP);
      Serial.printf("\n[Setup] Fallo (status=%d)\n", WiFi.status());
      JsonDocument e; e["ok"]=false;
      e["error"]="No se pudo conectar. Verifica SSID y contrasena.";
      e["tip"]="Solo redes 2.4 GHz.";
      sendJson(400,e); return;
    }

    String ip=WiFi.localIP().toString();
    Serial.printf("\n[Setup] OK -> IP: %s\n", ip.c_str());
    saveSecure("aqua-wifi","ssid",ssid); saveSecure("aqua-wifi","pass",pass);
    logSecure("wifi_verified_saved");
    JsonDocument r; r["ok"]=true; r["message"]="WiFi guardado. Reconectando..."; r["ip"]=ip;
    sendJson(200,r);
    delay(1500); ESP.restart();
  });

  server.onNotFound([]() {
    server.sendHeader("Location","http://192.168.4.1"); server.send(302,"text/plain","");
  });
  server.begin();
}

// ══════════════════════════════════════════════════════════════════════════════
void loop() {
  if (currentMode==MODE_SETUP) dnsServer.processNextRequest();
  server.handleClient();
  if (currentMode==MODE_NORMAL) {
    checkStop();
    checkSchedules();
    checkFaults();
    processEvents();
  }
  static unsigned long lastBlink=0;
  if (millis()-lastBlink > (currentMode==MODE_SETUP?500:3000)) { lastBlink=millis(); blinkLED(1); }
  delay(10);
}

// ══════════════════════════════════════════════════════════════════════════════
//  NTP
// ══════════════════════════════════════════════════════════════════════════════
void syncNTP() {
  Serial.print(F("[NTP] Sincronizando"));
  configTime(TZ_OFFSET_SECONDS, 0, "pool.ntp.org", "time.google.com", "time.cloudflare.com");
  struct tm timeinfo;
  int attempts=0;
  while (!getLocalTime(&timeinfo) && attempts<20) { delay(500); Serial.print("."); attempts++; }
  if (attempts>=20) { Serial.println(F("\n[NTP] Sin respuesta. Usando RTC.")); return; }
  DateTime t(timeinfo.tm_year+1900, timeinfo.tm_mon+1, timeinfo.tm_mday,
             timeinfo.tm_hour, timeinfo.tm_min, timeinfo.tm_sec);
  rtc.adjust(t);
  Serial.printf("\n[NTP] OK -> %02d/%02d/%04d %02d:%02d:%02d\n",
    t.day(),t.month(),t.year(),t.hour(),t.minute(),t.second());
}

// ══════════════════════════════════════════════════════════════════════════════
//  SEGURIDAD
// ══════════════════════════════════════════════════════════════════════════════
bool checkToken() {
  if (authToken.isEmpty()) { sendError(403,"No vinculado"); return false; }
  String auth=server.header("Authorization");
  if (!auth.startsWith("Bearer ")) { sendError(401,"Token requerido"); return false; }
  String received=auth.substring(7); received.trim();
  if (!timingSafeCompare(received,authToken)) { logSecure("bad_token"); sendError(401,"Token invalido"); return false; }
  return true;
}

bool timingSafeCompare(const String& a, const String& b) {
  if (a.length()!=b.length()) return false;
  uint8_t diff=0;
  for (size_t i=0;i<a.length();i++) diff|=(uint8_t)a[i]^(uint8_t)b[i];
  return diff==0;
}

String xorEncryptDecrypt(const String& data, const String& key) {
  String out; out.reserve(data.length());
  for (size_t i=0;i<data.length();i++) out+=(char)(data[i]^key[i%key.length()]);
  return out;
}

String getDeviceKey() {
  uint64_t c=ESP.getEfuseMac(); String k;
  for (int i=0;i<8;i++) k+=(char)((c>>(i*8))&0xFF);
  k+="AquaCtrl_v3_"; return k;
}

String getDeviceShortId() {
  char buf[8]; snprintf(buf,sizeof(buf),"%06X",(uint32_t)(ESP.getEfuseMac()&0xFFFFFF)); return String(buf);
}

String getResetPin() {
  char buf[7]; snprintf(buf,sizeof(buf),"%06u",(uint32_t)(ESP.getEfuseMac()%1000000)); return String(buf);
}

String generateRandomString(int len) {
  const char chars[]="ABCDEFGHJKMNPQRSTUVWXYZ23456789"; String s;
  for (int i=0;i<len;i++) s+=chars[esp_random()%(sizeof(chars)-1)]; return s;
}

// ══════════════════════════════════════════════════════════════════════════════
//  PERSISTENCIA CIFRADA
// ══════════════════════════════════════════════════════════════════════════════
void saveSecure(const char* ns, const char* key, const String& value) {
  String enc=xorEncryptDecrypt(value,getDeviceKey());
  prefs.begin(ns,false);
  prefs.putBytes(key,enc.c_str(),enc.length());
  prefs.putUShort((String(key)+"_len").c_str(),enc.length());
  prefs.end();
}

String loadSecure(const char* ns, const char* key) {
  prefs.begin(ns,true);
  uint16_t len=prefs.getUShort((String(key)+"_len").c_str(),0);
  if (len==0) { prefs.end(); return ""; }
  char* buf=(char*)malloc(len+1); if (!buf) { prefs.end(); return ""; }
  prefs.getBytes(key,buf,len); buf[len]='\0'; prefs.end();
  String enc; enc.reserve(len);
  for (uint16_t i=0;i<len;i++) enc+=buf[i]; free(buf);
  return xorEncryptDecrypt(enc,getDeviceKey());
}

void saveSchedules() {
  prefs.begin("aqua-sched",false);
  prefs.putInt("ver",SCHED_VERSION);
  prefs.putInt("count",scheduleCount);
  for (int i=0;i<scheduleCount;i++) { char k[8]; snprintf(k,sizeof(k),"s%d",i); prefs.putBytes(k,&schedules[i],sizeof(Schedule)); }
  prefs.end();
}

void loadSchedules() {
  prefs.begin("aqua-sched",true);
  int ver=prefs.getInt("ver",1);
  scheduleCount=constrain(prefs.getInt("count",0),0,MAX_SCHEDULES);
  for (int i=0;i<scheduleCount;i++) {
    char k[8]; snprintf(k,sizeof(k),"s%d",i);
    if (ver>=SCHED_VERSION) {
      prefs.getBytes(k,&schedules[i],sizeof(Schedule));
    } else {
      // Migración v3.1 → v3.2: las programaciones existentes pasan a la zona 1
      ScheduleV1 old; prefs.getBytes(k,&old,sizeof(ScheduleV1));
      Schedule& s=schedules[i];
      s.active=old.active; s.days=old.days; s.startHour=old.startHour;
      s.startMinute=old.startMinute; s.durationMin=old.durationMin;
      memcpy(s.id,old.id,sizeof(s.id)); s.zone=1;
    }
    if (!validZone(schedules[i].zone)) schedules[i].zone=1;
  }
  prefs.end();
  if (ver<SCHED_VERSION && scheduleCount>0) {
    saveSchedules();
    Serial.println(F("[Flash] Programaciones migradas al formato multizona"));
  }
  Serial.printf("[Flash] %d programaciones cargadas\n",scheduleCount);
}

// ══════════════════════════════════════════════════════════════════════════════
//  CONTROL DE ZONAS + SCHEDULER
// ══════════════════════════════════════════════════════════════════════════════
bool validZone(int zone) { return zone>=1 && zone<=ZONE_COUNT; }

bool anyZoneActive() {
  for (int z=0;z<ZONE_COUNT;z++) if (zones[z].active) return true;
  return false;
}

// z: índice 0-based. minutes = 0 → sin apagado automático.
void encenderZona(uint8_t z, bool manual, uint16_t minutes) {
  ZoneState& s=zones[z];
  s.active=true; s.manual=manual; s.fault=false;
  s.timed=minutes>0;
  s.startedAt=rtc.now();
  if (s.timed) s.stopAt=s.startedAt+TimeSpan(0,0,minutes,0);
  s.onSinceMs=millis();
  digitalWrite(ZONE_PINS[z],HIGH);
  if (!PRODUCTION_MODE) Serial.printf("[Zona %d] ON (pin %d)\n",z+1,ZONE_PINS[z]);
  queueEvent(EV_START,z+1,manual,minutes);
}

void apagarZona(uint8_t z, bool notify) {
  ZoneState& s=zones[z];
  if (!s.active) return;
  uint16_t ran=(uint16_t)((rtc.now()-s.startedAt).totalseconds()/60);
  bool wasManual=s.manual;
  s.active=false; s.manual=false; s.timed=false;
  digitalWrite(ZONE_PINS[z],LOW);
  if (!PRODUCTION_MODE) Serial.printf("[Zona %d] OFF\n",z+1);
  if (notify) queueEvent(EV_END,z+1,wasManual,ran);
}

void apagarTodas(bool notify) {
  for (int z=0;z<ZONE_COUNT;z++) apagarZona(z,notify);
}

// Apaga cada zona cuando se cumple su duración (también riegos manuales con duración)
void checkStop() {
  DateTime now=rtc.now();
  for (int z=0;z<ZONE_COUNT;z++) {
    ZoneState& s=zones[z];
    if (!s.active||!s.timed) continue;
    if (now>=s.stopAt) apagarZona(z,true);
  }
}

void checkSchedules() {
  DateTime now=rtc.now();
  int currentMin=now.hour()*60+now.minute();
  int dayBit=getDayBit(now.dayOfTheWeek());
  int32_t today=now.year()*10000L+now.month()*100+now.day();
  for (int i=0;i<scheduleCount;i++) {
    Schedule& s=schedules[i];
    if (!s.active||!validZone(s.zone)) continue;
    ZoneState& zs=zones[s.zone-1];
    if (zs.active) continue;                  // la zona ya está regando
    if (!(s.days&(1<<dayBit))) continue;
    int schedMin=s.startHour*60+s.startMinute;
    if (abs(currentMin-schedMin)>1) continue;
    if (zs.lastFiredIdx==i&&zs.lastFiredMin==schedMin&&zs.lastFiredDate==today) continue;
    zs.lastFiredIdx=i; zs.lastFiredMin=schedMin; zs.lastFiredDate=today;
    encenderZona(s.zone-1,false,s.durationMin);
    Serial.printf("[Scheduler] Programacion #%d disparada en zona %d\n",i,s.zone);
  }
}

// Con sensor de retroalimentación: si la válvula no responde, se apaga la zona
// y se avisa al usuario (falla).
void checkFaults() {
  if (!FAULT_DETECTION) return;
  for (int z=0;z<ZONE_COUNT;z++) {
    ZoneState& s=zones[z];
    if (!s.active||millis()-s.onSinceMs<FAULT_CHECK_MS) continue;
    if (digitalRead(ZONE_SENSE_PINS[z])==LOW) {
      bool wasManual=s.manual;
      apagarZona(z,false);
      s.fault=true;
      logSecure("valve_fault");
      queueEvent(EV_FAIL,z+1,wasManual,0);
    }
  }
}

int getDayBit(int dow) { return (dow==0)?6:(dow-1); }

// ══════════════════════════════════════════════════════════════════════════════
//  AVISOS → Cloud Function deviceEvent (notificaciones push)
// ══════════════════════════════════════════════════════════════════════════════
void queueEvent(uint8_t type, uint8_t zone, bool manual, uint16_t minutes) {
  if (strlen(EVENT_URL)==0||authToken.isEmpty()) return;
  if (eventCount==EVENT_QUEUE_SIZE) {             // cola llena: se descarta el más viejo
    eventHead=(eventHead+1)%EVENT_QUEUE_SIZE; eventCount--;
  }
  int idx=(eventHead+eventCount)%EVENT_QUEUE_SIZE;
  eventQueue[idx]={type,zone,manual,minutes,0,0};
  eventCount++;
}

// Envía un aviso por iteración del loop para no bloquear el servidor HTTP.
void processEvents() {
  if (eventCount==0||WiFi.status()!=WL_CONNECTED) return;
  PendingEvent& e=eventQueue[eventHead];
  if (millis()<e.notBefore) return;
  bool sent=postEvent(e);
  if (sent||++e.attempts>=EVENT_MAX_ATTEMPTS) {
    if (!sent) logSecure("event_dropped");
    eventHead=(eventHead+1)%EVENT_QUEUE_SIZE; eventCount--;
  } else {
    e.notBefore=millis()+EVENT_RETRY_MS;
  }
}

bool postEvent(const PendingEvent& e) {
  static const char* TYPES[]={"start","end","fail"};
  WiFiClientSecure client;
  client.setCACert(GOOGLE_ROOT_CAS);
  client.setTimeout(8);
  HTTPClient http;
  if (!http.begin(client,EVENT_URL)) return false;
  http.setTimeout(8000);
  http.addHeader("Content-Type","application/json");
  http.addHeader("Authorization","Bearer "+authToken);

  JsonDocument d;
  d["uid"]=linkedUID; d["device"]=getDeviceShortId();
  d["type"]=TYPES[e.type]; d["zone"]=e.zone;
  d["source"]=e.manual?"manual":"schedule";
  if (e.minutes>0) d["minutes"]=e.minutes;
  String body; serializeJson(d,body);

  int code=http.POST(body);
  http.end();
  if (!PRODUCTION_MODE) Serial.printf("[Avisos] %s zona %d -> HTTP %d\n",TYPES[e.type],e.zone,code);
  // 4xx = petición rechazada (token o datos): reintentar no sirve
  return (code>=200&&code<300)||(code>=400&&code<500);
}

// ══════════════════════════════════════════════════════════════════════════════
//  UTILIDADES
// ══════════════════════════════════════════════════════════════════════════════
String formatTime(const DateTime& t) {
  char b[6]; snprintf(b,sizeof(b),"%02d:%02d",t.hour(),t.minute()); return String(b);
}

void sendJson(int code, JsonDocument& doc) {
  server.sendHeader("Access-Control-Allow-Origin","*");
  server.sendHeader("Access-Control-Allow-Headers","Authorization, Content-Type");
  String out; serializeJson(doc,out);
  server.send(code,"application/json",out);
}

void sendError(int code, const char* msg) {
  JsonDocument doc; doc["ok"]=false; doc["error"]=msg; sendJson(code,doc);
}

void blinkLED(int times) {
  for (int i=0;i<times;i++) { digitalWrite(LED_PIN,HIGH);delay(60);digitalWrite(LED_PIN,LOW);delay(60); }
}

void logSecure(const char* event) {
  DateTime now=rtc.now();
  Serial.printf("[Sec] %02d:%02d:%02d  event=%s\n",now.hour(),now.minute(),now.second(),event);
}
