#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <DHT.h>
#include <Wire.h>
#include <BH1750.h>
#include <ArduinoJson.h>
#include <SPIFFS.h>
#include <time.h>
#include <NTPClient.h>
#include <WiFiUdp.h>

#define DHT_PIN 4
#define DHT_TYPE DHT22
#define FAN_PIN 26
#define PUMP_PIN 25
#define LIGHT_PIN 13
#define SOIL_PIN 34
#define CO2_PIN 35

const char* WIFI_SSID = ".";
const char* WIFI_PASSWORD = "12345678";

WiFiUDP ntpUDP;
NTPClient timeClient(ntpUDP, "pool.ntp.org", 25200, 60000);

unsigned long lastFirebaseSend = 0;
unsigned long lastHistorySave = 0;

// ====== SENSOR MANAGER ======
class SensorManager {
public:
    static void initialize() {
        Wire.begin();
        _dht.begin();
        _lightMeter.begin(BH1750::CONTINUOUS_HIGH_RES_MODE);
    }
    static float getTemperature() { float t=_dht.readTemperature(); return isnan(t)?25:t; }
    static float getHumidity() { float h=_dht.readHumidity(); return isnan(h)?60:h; }
    static int getSoilMoisture() { return analogRead(SOIL_PIN); }
    static float getLightLevel() { return _lightMeter.readLightLevel(); }
    static int getCO2Level() { return analogRead(CO2_PIN); }
private:
    static DHT _dht;
    static BH1750 _lightMeter;
};
DHT SensorManager::_dht(DHT_PIN, DHT_TYPE);
BH1750 SensorManager::_lightMeter;

// ====== DEVICE MANAGER ======
class DeviceManager {
public:
    static void initialize() {
        pinMode(FAN_PIN, OUTPUT); pinMode(PUMP_PIN, OUTPUT); pinMode(LIGHT_PIN, OUTPUT);
        fanOff(); pumpOff(); lightOff();
    }
    static void fanOn(){digitalWrite(FAN_PIN,HIGH);_fan=true;}
    static void fanOff(){digitalWrite(FAN_PIN,LOW);_fan=false;}
    static void pumpOn(){digitalWrite(PUMP_PIN,HIGH);_pump=true;}
    static void pumpOff(){digitalWrite(PUMP_PIN,LOW);_pump=false;}
    static void lightOn(){digitalWrite(LIGHT_PIN,HIGH);_light=true;}
    static void lightOff(){digitalWrite(LIGHT_PIN,LOW);_light=false;}
    static bool fan(){return _fan;} static bool pump(){return _pump;} static bool light(){return _light;}
private:
    static bool _fan,_pump,_light;
};
bool DeviceManager::_fan=false; bool DeviceManager::_pump=false; bool DeviceManager::_light=false;

// ====== HISTORY MANAGER ======
class HistoryManager {
public:
    static void initialize(){ if(!SPIFFS.begin(true)) Serial.println("SPIFFS init failed"); }
    static void saveData(){
        if(millis()-lastHistorySave < 30000) return; // save mỗi 30s
        lastHistorySave = millis();

        File f=SPIFFS.open("/sensor_history.json",FILE_APPEND);
        if(!f) return;
        StaticJsonDocument<200> doc;
        doc["t"]=SensorManager::getTemperature();
        doc["h"]=SensorManager::getHumidity();
        doc["s"]=SensorManager::getSoilMoisture();
        doc["l"]=SensorManager::getLightLevel();
        doc["c"]=SensorManager::getCO2Level();
        doc["ts"]=millis();
        serializeJson(doc,f);
        f.println();
        f.close();
    }
};

// ====== AUTOMATION MANAGER ======
struct SensorThresholds {
  float tHigh=30,tLow=27; int sDry=4000,sWet=3000; int lDark=50,lBright=300; int cHigh=1000,cLow=400;
};
class AutomationManager {
public:
    static void initialize(){ timeClient.begin(); timeClient.update(); _autoMode=true; }
    static void update(){
        if(!_autoMode) return; // nếu không auto thì không làm gì
        float temp=SensorManager::getTemperature();
        int soil=SensorManager::getSoilMoisture();
        float light=SensorManager::getLightLevel();
        int co2=SensorManager::getCO2Level();
        timeClient.update(); int hour=timeClient.getHours();

        // LIGHT
        if(hour>=6 && hour<18){
            if(light < _th.lDark) DeviceManager::lightOn();
            else if(light > _th.lBright) DeviceManager::lightOff();
        } else DeviceManager::lightOff();

        // TEMP + CO2
        if(temp > _th.tHigh || co2 > _th.cHigh) DeviceManager::fanOn();
        else if(temp < _th.tLow && co2 < _th.cHigh) DeviceManager::fanOff();

        // SOIL
        if(soil > _th.sDry) DeviceManager::pumpOn();
        else if(soil < _th.sWet) DeviceManager::pumpOff();

        HistoryManager::saveData();
    }
    static bool isAutoMode(){return _autoMode;}
    static void setAutoMode(bool mode){_autoMode=mode;}
private:
    static SensorThresholds _th;
    static bool _autoMode;
};
SensorThresholds AutomationManager::_th;
bool AutomationManager::_autoMode;

// ====== FIREBASE MANAGER ======
class FirebaseManager {
public:
    static void initialize(){
        _firebaseUrl="https://uddd-e0e1f-default-rtdb.firebaseio.com/sensorData.json?auth=KyN7SUx5fyAYmowUkvXTkggp5QBy9ZlPaonhRhOJ";
        _controlsUrl="https://uddd-e0e1f-default-rtdb.firebaseio.com/controls.json?auth=KyN7SUx5fyAYmowUkvXTkggp5QBy9ZlPaonhRhOJ";
        _client.setInsecure();
    }
    static void sendSensorData(){
        if(millis()-lastFirebaseSend < 10000) return; // gửi mỗi 10s
        lastFirebaseSend = millis();
        if(WiFi.status()!=WL_CONNECTED){ Serial.println("WiFi mất kết nối"); return; }

        StaticJsonDocument<400> doc;
        doc["temperature"]=SensorManager::getTemperature();
        doc["humidity"]=SensorManager::getHumidity();
        doc["soilMoisture"]=SensorManager::getSoilMoisture();
        doc["lightLevel"]=SensorManager::getLightLevel();
        doc["co2Level"]=SensorManager::getCO2Level();
        doc["fan"]=DeviceManager::fan();
        doc["pump"]=DeviceManager::pump();
        doc["light"]=DeviceManager::light();
        doc["autoMode"]=AutomationManager::isAutoMode();
        doc["timestamp"]=millis();

        String payload; serializeJson(doc,payload);

        _https.begin(_client, _firebaseUrl);
        _https.addHeader("Content-Type","application/json");
        int code=_https.POST(payload);

        if(code>0) Serial.printf("✅ Firebase code: %d\n", code);
        else Serial.printf("❌ Firebase error: %d\n", code);

        _https.end();
    }
    static void checkControls(){
        Serial.println("Checking controls from Firebase...");
        Serial.print("WiFi status: ");
        Serial.println(WiFi.status() == WL_CONNECTED ? "Connected" : "Disconnected");

        if(millis()-lastControlCheck < 2000) return; // kiểm tra mỗi 2s
        lastControlCheck = millis();
        if(WiFi.status()!=WL_CONNECTED) {
            Serial.println("WiFi not connected, skipping controls check");
            return;
        }

        Serial.print("Controls URL: ");
        Serial.println(_controlsUrl);

        _https.begin(_client, _controlsUrl);
        Serial.println("Starting HTTP GET for controls...");
        int code=_https.GET();
        Serial.print("HTTP Response Code: ");
        Serial.println(code);

        if(code==200){
            String payload=_https.getString();
            Serial.println("Controls received: " + payload);

            StaticJsonDocument<200> doc;
            DeserializationError error = deserializeJson(doc, payload);

            if (!error) {
                bool autoMode = doc["autoMode"] | true;
                bool fan = doc["fan"] | false;
                bool pump = doc["pump"] | false;
                bool light = doc["light"] | false;

                Serial.print("Parsed controls - autoMode: ");
                Serial.print(autoMode);
                Serial.print(", fan: ");
                Serial.print(fan);
                Serial.print(", pump: ");
                Serial.print(pump);
                Serial.print(", light: ");
                Serial.println(light);

                AutomationManager::setAutoMode(autoMode);

                if (!autoMode) {
                    if (fan) DeviceManager::fanOn(); else DeviceManager::fanOff();
                    if (pump) DeviceManager::pumpOn(); else DeviceManager::pumpOff();
                    if (light) DeviceManager::lightOn(); else DeviceManager::lightOff();
                    Serial.println("Manual controls applied");
                } else {
                    Serial.println("Auto mode active, skipping manual controls");
                }
            } else {
                Serial.println("Failed to parse controls JSON: " + String(error.c_str()));
            }
        } else {
private:
    static WiFiClientSecure _client;
    static HTTPClient _https;
    static String _firebaseUrl;
    static String _controlsUrl;
    static unsigned long lastControlCheck;
};
WiFiClientSecure FirebaseManager::_client;
HTTPClient FirebaseManager::_https;
String FirebaseManager::_firebaseUrl;
String FirebaseManager::_controlsUrl;
unsigned long FirebaseManager::lastControlCheck = 0;

// ====== MAIN ======
void setup(){
    Serial.begin(115200);
    WiFi.begin(WIFI_SSID,WIFI_PASSWORD);
    Serial.print("Đang kết nối WiFi");
    while(WiFi.status()!=WL_CONNECTED){ delay(500); Serial.print("."); }
    Serial.println("\nWiFi Connected: "+WiFi.localIP().toString());

    SensorManager::initialize();
    DeviceManager::initialize();
    HistoryManager::initialize();
    AutomationManager::initialize();
    FirebaseManager::initialize();
}

void loop(){
    AutomationManager::update();
    FirebaseManager::sendSensorData();
    FirebaseManager::checkControls();
