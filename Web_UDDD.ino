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

// Định nghĩa PIN
#define DHT_PIN 4
#define DHT_TYPE DHT22
#define FAN_PIN 26
#define PUMP_PIN 25
#define LIGHT_PIN 27
#define SOIL_PIN 34
#define CO2_PIN 35

// Cấu hình WiFi
const char* WIFI_SSID = "."; // *** NHỚ ĐIỀN WIFI CỦA BẠN ***
const char* WIFI_PASSWORD = "12345678"; // *** NHỚ ĐIỀN MẬT KHẨU WIFI ***

// Cấu hình NTP
WiFiUDP ntpUDP;
NTPClient timeClient(ntpUDP, "pool.ntp.org", 25200, 60000); // 25200 = GMT+7

// Biến toàn cục cho timers
unsigned long lastFirebaseSend = 0;
unsigned long lastHistorySave = 0;

// ====== SENSOR MANAGER (Giữ nguyên) ======
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

// ====== DEVICE MANAGER (Giữ nguyên) ======
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

// ====== HISTORY MANAGER (Giữ nguyên) ======
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

// ====== AUTOMATION MANAGER (*** SỬA LẠI LOGIC ***) ======
// Struct định nghĩa ngưỡng, với giá trị mặc định
struct SensorThresholds {
  float tHigh=30,tLow=27; int sDry=4000,sWet=3000; int lDark=50,lBright=300; int cHigh=1000,cLow=400;
};

class AutomationManager {
public:
    static void initialize(){ 
        timeClient.begin(); 
        timeClient.update();
        _autoMode = true; // Mặc định là auto
    }

    static void update(){
        if(!_autoMode) return; // Chỉ chạy khi autoMode = true
        
        float temp=SensorManager::getTemperature();
        int soil=SensorManager::getSoilMoisture();
        float light=SensorManager::getLightLevel();
        int co2=SensorManager::getCO2Level();
        timeClient.update(); int hour=timeClient.getHours();

        // Logic đèn
        if(hour>=6 && hour<18){
            if(light < _th.lDark) DeviceManager::lightOn();
            else if(light > _th.lBright) DeviceManager::lightOff();
        } else DeviceManager::lightOff();

        // Logic quạt
        if(temp > _th.tHigh || co2 > _th.cHigh) DeviceManager::fanOn();
        else if(temp < _th.tLow && co2 < _th.cHigh) DeviceManager::fanOff();

        // Logic bơm
        if(soil > _th.sDry) DeviceManager::pumpOn();
        else if(soil < _th.sWet) DeviceManager::pumpOff();

        HistoryManager::saveData();
    }
    
    static bool isAutoMode(){ return _autoMode; }
    static void setAutoMode(bool mode){ _autoMode = mode; }
    
    // *** MỚI: Các hàm để set/get ngưỡng ***
    static void setThresholds(const SensorThresholds& newThresholds) {
        _th = newThresholds;
        Serial.println("Thresholds updated.");
        Serial.printf("New tHigh: %.1f, tLow: %.1f\n", _th.tHigh, _th.tLow);
    }
    
    // *** MỚI: Hàm lấy ngưỡng để gửi lên Firebase
    static const SensorThresholds& getThresholds() {
        return _th;
    }
    
private:
    static SensorThresholds _th; // Sử dụng giá trị mặc định từ struct
    static bool _autoMode;
};
SensorThresholds AutomationManager::_th;
bool AutomationManager::_autoMode;

// ====== FIREBASE MANAGER (*** THÊM LẠI PHẦN BỊ THIẾU ***) ======
class FirebaseManager {
public:
    static void initialize(){
        // URL để GỬI (POST) dữ liệu cảm biến (dạng log)
        _firebaseUrl="https://uddd-e0e1f-default-rtdb.firebaseio.com/sensorData.json?auth=KyN7SUx5fyAYmowUkvXTkggp5QBy9ZlPaonhRhOJ";
        
        // URL để NHẬN (GET) lệnh điều khiển VÀ ngưỡng
        _controlsUrl="https://uddd-e0e1f-default-rtdb.firebaseio.com/controls.json?auth=KyN7SUx5fyAYmowUkvXTkggp5QBy9ZlPaonhRhOJ";
        
        _client.setInsecure();
    }

    static void sendSensorData(){
        if(millis()-lastFirebaseSend < 2000) return; // gửi mỗi 2s
        lastFirebaseSend = millis();
        if(WiFi.status()!=WL_CONNECTED){ Serial.println("WiFi mất kết nối"); return; }
        StaticJsonDocument<512> doc; // Tăng từ 400
        doc["temperature"]=SensorManager::getTemperature();
        doc["humidity"]=SensorManager::getHumidity();
        doc["soilMoisture"]=SensorManager::getSoilMoisture();
        doc["lightLevel"]=SensorManager::getLightLevel();
        doc["co2Level"]=SensorManager::getCO2Level();
        
        doc["fan"]=DeviceManager::fan(); 
        doc["pump"]=DeviceManager::pump();
        doc["light"]=DeviceManager::light();
        doc["autoMode"]=AutomationManager::isAutoMode();
        
        // *** MỚI: Thêm object ngưỡng vào payload ***
        // Ứng dụng Flutter của bạn sẽ đọc object này từ log mới nhất
        const SensorThresholds& th = AutomationManager::getThresholds();
        JsonObject thresholdsObj = doc.createNestedObject("thresholds");
        thresholdsObj["tHigh"] = th.tHigh;
        thresholdsObj["tLow"] = th.tLow;
        thresholdsObj["sDry"] = th.sDry;
        thresholdsObj["sWet"] = th.sWet;
        thresholdsObj["lDark"] = th.lDark;
        thresholdsObj["lBright"] = th.lBright;
        thresholdsObj["cHigh"] = th.cHigh;
        thresholdsObj["cLow"] = th.cLow;
        
      doc["timestamp"] = (unsigned long)timeClient.getEpochTime() * 1000UL;

        String payload; serializeJson(doc,payload);

        _https.begin(_client, _firebaseUrl);
        _https.addHeader("Content-Type","application/json");
        int code=_https.POST(payload);

        if(code>0) Serial.printf("✅ Firebase sensor data sent: %d\n", code);
        else Serial.printf("❌ Firebase sensor error: %d\n", code);

        _https.end();
    }

    static void checkControls(){
        if(millis() - lastControlCheck < 500) return; // Kiểm tra mỗi 0.5s
        lastControlCheck = millis();

        if(WiFi.status() != WL_CONNECTED) {
            Serial.println("WiFi not connected, skipping controls check");
            return;
        }

        _https.begin(_client, _controlsUrl);
        int code = _https.GET();

        if (code == 200) {
            String payload = _https.getString();
            Serial.println("Controls received: " + payload);

            // *** SỬA: Tăng dung lượng JSON để nhận thêm ngưỡng ***
            StaticJsonDocument<512> doc; // Tăng từ 200
            DeserializationError error = deserializeJson(doc, payload);

            if (!error) {
                // 1. Lấy lệnh điều khiển
                bool autoMode = doc["autoMode"] | true;
                bool fan = doc["fan"] | false;
                bool pump = doc["pump"] | false;
                bool light = doc["light"] | false;

                // 2. Cập nhật trạng thái AutoMode
                AutomationManager::setAutoMode(autoMode);

                // 3. Chỉ điều khiển bằng tay NẾU autoMode = false
                if (!autoMode) {
                    Serial.println("Manual mode: Applying controls...");
                    if (fan) DeviceManager::fanOn(); else DeviceManager::fanOff();
                    if (pump) DeviceManager::pumpOn(); else DeviceManager::pumpOff();
                    if (light) DeviceManager::lightOn(); else DeviceManager::lightOff();
                } else {
                    Serial.println("Auto mode active.");
                }

                // *** MỚI: Kiểm tra và cập nhật ngưỡng ***
                // App Flutter của bạn sẽ GHI (PUT/PATCH) vào /controls/thresholds
                if (doc.containsKey("thresholds")) {
                    JsonObject thJson = doc["thresholds"];
                    if (!thJson.isNull()) {
                        SensorThresholds newThresholds;
                        SensorThresholds defaults; // Lấy giá trị default từ struct
                        
                        // Đọc từng giá trị, nếu thiếu sẽ lấy giá trị default
                        newThresholds.tHigh = thJson["tHigh"] | defaults.tHigh;
                        newThresholds.tLow = thJson["tLow"] | defaults.tLow;
                        newThresholds.sDry = thJson["sDry"] | defaults.sDry;
                        newThresholds.sWet = thJson["sWet"] | defaults.sWet;
                        newThresholds.lDark = thJson["lDark"] | defaults.lDark;
                        newThresholds.lBright = thJson["lBright"] | defaults.lBright;
                        newThresholds.cHigh = thJson["cHigh"] | defaults.cHigh;
                        newThresholds.cLow = thJson["cLow"] | defaults.cLow;
                        
                        // Cập nhật vào AutomationManager
                        AutomationManager::setThresholds(newThresholds);
                    }
                }
                
            } else {
                Serial.println("Failed to parse controls JSON");
            }
        } else {
            Serial.printf("❌ Firebase controls error: %d\n", code);
        }
        _https.end();
    }

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

// ====== MAIN SETUP ======
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

// ====== MAIN LOOP  ======
void loop(){
    FirebaseManager::checkControls();
    AutomationManager::update();
    FirebaseManager::sendSensorData();
   }