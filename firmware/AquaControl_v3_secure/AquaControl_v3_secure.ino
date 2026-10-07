/**
 * ============================================================
 *  AquaControl – Firmware ESP32  v3.1  (Hardened + NTP + ResetPIN)
 * ============================================================
 *
 *  Hardware:
 *    ESP32 + RTC DS3231 (SDA=21, SCL=22) + MOSFET en GPIO23
 *    LED integrado = GPIO2
 *
 *  Librerías (Herramientas → Administrar bibliotecas):
 *    - RTClib       by Adafruit
 *    - ArduinoJson  by Benoît Blanchon  (>= 7.0)
 *
 *  PRIMERA VEZ: el ESP crea red WiFi "AquaControl-XXXXXX"
 *  La contraseña y el Reset PIN aparecen en Monitor Serial (115200).
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
#include <esp_system.h>
#include <esp_random.h>
#include <time.h>

// ─── Configuración ───────────────────────────────────────────────────────────
#define MDNS_NAME          "aquacontrol"
#define PIN_VALVULA        23
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

// ─── Objetos ─────────────────────────────────────────────────────────────────
WebServer   server(80);
DNSServer   dnsServer;
RTC_DS3231  rtc;
Preferences prefs;

// ─── Estructura de programación ──────────────────────────────────────────────
struct Schedule {
  bool     active;
  uint8_t  days;
  uint8_t  startHour;
  uint8_t  startMinute;
  uint16_t durationMin;
  char     id[37];
};
Schedule schedules[MAX_SCHEDULES];
int      scheduleCount = 0;

// ─── Estado runtime ──────────────────────────────────────────────────────────
bool     riegoActivo    = false;
bool     manualOverride = false;
DateTime riegoStop;
int      lastFiredMin   = -1;
int      lastFiredIdx   = -1;

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
void encenderRiego(bool manual);
void apagarRiego();
void checkStop();
void checkSchedules();
int  getDayBit(int dow);
void syncNTP();

// ── HTTP ──────────────────────────────────────────────────────────────────────
void sendJson(int code, JsonDocument& doc);
void sendError(int code, const char* msg);
void blinkLED(int times);
void logSecure(const char* event);

// ══════════════════════════════════════════════════════════════════════════════
void setup() {
  Serial.begin(115200);
  delay(300);

  Serial.println(F("\n╔═══════════════════════════════════╗"));
  Serial.println(F("║  AquaControl  Firmware v3.1       ║"));
  Serial.println(F("╚═══════════════════════════════════╝"));
  Serial.printf("Device ID:  %s\n", getDeviceShortId().c_str());
  Serial.printf("Reset PIN:  %s  <- anota este numero\n", getResetPin().c_str());

  pinMode(PIN_VALVULA, OUTPUT); digitalWrite(PIN_VALVULA, LOW);
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
      doc["valve"]     = riegoActivo;
      doc["manual"]    = manualOverride;
      doc["paired"]    = !authToken.isEmpty();
      doc["mode"]      = "normal";
      doc["device"]    = getDeviceShortId();
      doc["schedules"] = scheduleCount;
      doc["ip"]        = WiFi.localIP().toString();
      if (!authToken.isEmpty()) doc["uid"] = linkedUID;
      char buf[24];
      snprintf(buf, sizeof(buf), "%04d-%02d-%02dT%02d:%02d:%02d",
        now.year(), now.month(), now.day(), now.hour(), now.minute(), now.second());
      doc["rtc"] = buf;
      if (riegoActivo && !manualOverride) {
        char sb[10];
        snprintf(sb, sizeof(sb), "%02d:%02d", riegoStop.hour(), riegoStop.minute());
        doc["stopAt"] = sb;
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

    server.on("/on", HTTP_POST, []() {
      if (!checkToken()) return;
      JsonDocument doc;
      if (server.hasArg("plain")) deserializeJson(doc, server.arg("plain"));
      int dur = doc["duration"]|0;
      if (riegoActivo) {
        JsonDocument r; r["ok"]=false; r["valve"]=true; r["message"]="Ya encendido"; sendJson(200,r); return;
      }
      encenderRiego(true);
      if (dur > 0) riegoStop = rtc.now() + TimeSpan(0,0,dur,0);
      JsonDocument r; r["ok"]=true; r["valve"]=true; r["duration"]=dur; sendJson(200,r);
    });

    server.on("/off", HTTP_POST, []() {
      if (!checkToken()) return;
      apagarRiego(); lastFiredMin=lastFiredIdx=-1;
      JsonDocument r; r["ok"]=true; r["valve"]=false; sendJson(200,r);
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
      }
      doc["count"]=scheduleCount; sendJson(200,doc);
    });

    server.on("/schedules", HTTP_POST, []() {
      if (!checkToken()) return;
      if (!server.hasArg("plain")) { sendError(400,"Body vacio"); return; }
      JsonDocument doc;
      if (deserializeJson(doc,server.arg("plain"))) { sendError(400,"JSON invalido"); return; }
      JsonArray arr = doc["schedules"].as<JsonArray>();
      if (arr.isNull()) { sendError(400,"schedules requerido"); return; }
      scheduleCount=0;
      for (JsonObject s:arr) {
        if (scheduleCount>=MAX_SCHEDULES) break;
        Schedule& sc=schedules[scheduleCount];
        sc.active=s["active"]|false; sc.days=s["days"]|127;
        sc.startHour=s["startHour"]|0; sc.startMinute=s["startMinute"]|0;
        sc.durationMin=s["duration"]|20;
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

    server.on("/schedules/active", HTTP_POST, []() {
      if (!checkToken()) return;
      if (!server.hasArg("plain")) { sendError(400,"Body vacio"); return; }
      JsonDocument doc; deserializeJson(doc,server.arg("plain"));
      const char* id=doc["id"]|""; bool active=doc["active"]|false;
      for (int i=0;i<scheduleCount;i++) schedules[i].active=false;
      for (int i=0;i<scheduleCount;i++) { if (strcmp(schedules[i].id,id)==0) { schedules[i].active=active; break; } }
      saveSchedules();
      JsonDocument r; r["ok"]=true; sendJson(200,r);
    });

    server.on("/reset", HTTP_POST, []() {
      if (!checkToken()) return;
      if (!server.hasArg("plain")) { sendError(400,"Body vacio"); return; }
      JsonDocument doc; deserializeJson(doc,server.arg("plain"));
      if (!timingSafeCompare(String(doc["pin"]|""), getResetPin())) {
        logSecure("reset_bad_pin"); sendError(403,"PIN incorrecto"); return;
      }
      apagarRiego();
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
      apagarRiego();
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
  if (currentMode==MODE_NORMAL) { checkStop(); checkSchedules(); }
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
  prefs.begin("aqua-sched",false); prefs.putInt("count",scheduleCount);
  for (int i=0;i<scheduleCount;i++) { char k[8]; snprintf(k,sizeof(k),"s%d",i); prefs.putBytes(k,&schedules[i],sizeof(Schedule)); }
  prefs.end();
}

void loadSchedules() {
  prefs.begin("aqua-sched",true); scheduleCount=prefs.getInt("count",0);
  for (int i=0;i<scheduleCount;i++) { char k[8]; snprintf(k,sizeof(k),"s%d",i); prefs.getBytes(k,&schedules[i],sizeof(Schedule)); }
  prefs.end();
  Serial.printf("[Flash] %d programaciones cargadas\n",scheduleCount);
}

// ══════════════════════════════════════════════════════════════════════════════
//  CONTROL VÁLVULA + SCHEDULER
// ══════════════════════════════════════════════════════════════════════════════
void encenderRiego(bool manual) {
  riegoActivo=true; manualOverride=manual; digitalWrite(PIN_VALVULA,HIGH);
  if (!PRODUCTION_MODE) Serial.println(F("[Valve] ON"));
}

void apagarRiego() {
  riegoActivo=false; manualOverride=false; digitalWrite(PIN_VALVULA,LOW);
  if (!PRODUCTION_MODE) Serial.println(F("[Valve] OFF"));
}

void checkStop() {
  if (!riegoActivo||manualOverride) return;
  if (rtc.now()>=riegoStop) { apagarRiego(); lastFiredMin=lastFiredIdx=-1; }
}

void checkSchedules() {
  if (riegoActivo) return;
  DateTime now=rtc.now();
  int currentMin=now.hour()*60+now.minute();
  int dayBit=getDayBit(now.dayOfTheWeek());
  for (int i=0;i<scheduleCount;i++) {
    Schedule& s=schedules[i];
    if (!s.active) continue;
    if (!(s.days&(1<<dayBit))) continue;
    int schedMin=s.startHour*60+s.startMinute;
    if (abs(currentMin-schedMin)>1) continue;
    if (lastFiredIdx==i&&lastFiredMin==schedMin) continue;
    lastFiredIdx=i; lastFiredMin=schedMin;
    riegoStop=rtc.now()+TimeSpan(0,0,s.durationMin,0);
    encenderRiego(false);
    Serial.printf("[Scheduler] Programacion #%d disparada\n",i);
    break;
  }
}

int getDayBit(int dow) { return (dow==0)?6:(dow-1); }

// ══════════════════════════════════════════════════════════════════════════════
//  UTILIDADES
// ══════════════════════════════════════════════════════════════════════════════
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
