import 'dart:async';
import 'dart:math' as math;
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'sensor_chart_screen.dart';
import 'threshold_settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // --- Firebase References ---

  /// Node chứa dữ liệu cảm biến và trạng thái thiết bị thực tế từ ESP32.
  final DatabaseReference sensorRef = FirebaseDatabase.instance.ref(
    "sensorData",
  );

  /// Node gửi lệnh điều khiển xuống ESP32.
  final DatabaseReference controlRef = FirebaseDatabase.instance.ref(
    "controls",
  );

  // --- Local State ---

  /// Timer đếm ngược để tự động bật lại Auto Mode sau khi can thiệp thủ công.
  Timer? _autoModeTimer;

  /// Biến cục bộ lưu trạng thái Auto Mode để xử lý logic nhanh tại client.
  bool _currentAutoMode = true;

  // --- Logic Methods ---

  void _setControl(String device, bool value) {
    controlRef.child(device).set(value);
  }

  @override
  void dispose() {
    _autoModeTimer?.cancel();
    super.dispose();
  }

  /// Xử lý khi điều khiển thiết bị thủ công.
  /// Logic: Tạm thời tắt Auto Mode và đặt lịch tự động bật lại sau 30s.
  void _handleManualControl(String device, bool value) {
    _autoModeTimer?.cancel();

    Map<String, dynamic> updates = {};

    // Nếu đang Auto, cần tắt Auto đi để tránh xung đột lệnh với ESP32
    if (_currentAutoMode) {
      updates["autoMode"] = false;
    }

    updates[device] = value;
    controlRef.update(updates);

    // Đặt timer khôi phục chế độ tự động
    _autoModeTimer = Timer(const Duration(seconds: 30), () {
      _setControl("autoMode", true);
    });
  }

  /// Xử lý bật/tắt chế độ tự động.
  /// Nếu tắt thủ công, cũng sẽ tự bật lại sau 30s (theo yêu cầu an toàn).
  void _handleAutoModeChange(bool value) {
    _autoModeTimer?.cancel();

    if (value == false) {
      _autoModeTimer = Timer(const Duration(seconds: 30), () {
        _setControl("autoMode", true);
      });
    }

    _setControl("autoMode", value);
  }

  // --- UI Build Methods ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Smart Greenhouse"),
        backgroundColor: Colors.green[700],
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: "Cài đặt ngưỡng",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ThresholdSettingsScreen(),
                ),
              );
            },
          ),
        ],
      ),
      backgroundColor: Colors.grey[100],
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Text(
            "Trạng thái Cảm biến",
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          _buildSensorSection(),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),
          Text(
            "Bảng điều khiển",
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _buildControlSection(),
        ],
      ),
    );
  }

  Widget _buildSensorSection() {
    return StreamBuilder(
      // LƯU Ý QUAN TRỌNG:
      // Sử dụng .limitToLast(1) để chỉ lấy bản ghi mới nhất.
      // Tránh dùng .onValue trực tiếp trên node lớn vì sẽ tải toàn bộ lịch sử gây lag và tốn chi phí.
      stream: sensorRef.orderByKey().limitToLast(1).onValue,
      builder: (context, AsyncSnapshot<DatabaseEvent> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data?.snapshot.value == null) {
          return const Center(child: Text("Không có dữ liệu cảm biến"));
        }

        // Parse dữ liệu an toàn từ Snapshot
        Map<dynamic, dynamic> allData =
            snapshot.data!.snapshot.value as Map<dynamic, dynamic>;
        var lastKey = allData.keys.first;
        Map<dynamic, dynamic> data = allData[lastKey];

        double temp = (data['temperature'] ?? 0.0).toDouble();
        double humi = (data['humidity'] ?? 0.0).toDouble();
        int soil = (data['soilMoisture'] ?? 0).toInt();
        double lightLux = (data['lightLevel'] ?? 0.0).toDouble();
        int co2 = (data['co2Level'] ?? 0).toInt();

        // Tính toán progress (0.0 -> 1.0) cho gauge
        double tempProgress = (temp / 50.0).clamp(0.0, 1.0);
        double humiProgress = (humi / 100.0).clamp(0.0, 1.0);
        double soilProgress = ((4095 - soil) / (4095 - 1000)).clamp(
          0.0,
          1.0,
        ); // 4095: Khô, 1000: Ướt
        double lightProgress = (lightLux / 1500.0).clamp(0.0, 1.0);
        double co2Progress = (co2 / 2000.0).clamp(0.0, 1.0);

        return GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.05,
          children: [
            _buildSensorGauge(
              title: "Nhiệt độ",
              sensorKey: "temperature",
              value: temp.toStringAsFixed(1),
              unit: "°C",
              icon: Icons.thermostat,
              color: Colors.red,
              progress: tempProgress,
            ),
            _buildSensorGauge(
              title: "Độ ẩm KK",
              sensorKey: "humidity",
              value: humi.toStringAsFixed(1),
              unit: "%",
              icon: Icons.water_drop_outlined,
              color: Colors.blue,
              progress: humiProgress,
            ),
            _buildSensorGauge(
              title: "Độ ẩm đất",
              sensorKey: "soilMoisture",
              value: soil.toString(),
              unit: "",
              icon: Icons.eco_outlined,
              color: Colors.brown,
              progress: soilProgress,
            ),
            _buildSensorGauge(
              title: "Ánh sáng",
              sensorKey: "lightLevel",
              value: lightLux.toStringAsFixed(0),
              unit: "lx",
              icon: Icons.wb_sunny_outlined,
              color: Colors.orange,
              progress: lightProgress,
            ),
            _buildSensorGauge(
              title: "CO2",
              sensorKey: "co2Level",
              value: co2.toString(),
              unit: "ppm",
              icon: Icons.air_outlined,
              color: Colors.grey.shade600,
              progress: co2Progress,
            ),
          ],
        );
      },
    );
  }

  /// Widget hiển thị đồng hồ đo (Gauge) cho từng cảm biến
  Widget _buildSensorGauge({
    required String title,
    required String sensorKey,
    required String value,
    required String unit,
    required IconData icon,
    required Color color,
    required double progress,
  }) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                SensorChartScreen(sensorKey: sensorKey, sensorTitle: title),
          ),
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Background Circle
                    SizedBox(
                      width: double.infinity,
                      height: double.infinity,
                      child: CircularProgressIndicator(
                        value: 1.0,
                        strokeWidth: 6,
                        backgroundColor: color.withOpacity(0.1),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          color.withOpacity(0.1),
                        ),
                      ),
                    ),
                    // Value Circle
                    SizedBox(
                      width: double.infinity,
                      height: double.infinity,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 6,
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                        strokeCap: StrokeCap.round,
                      ),
                    ),
                    // Center Info
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, color: color, size: 22),
                        const SizedBox(height: 2),
                        Text(
                          value,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: color,
                                fontSize: 16,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (unit.isNotEmpty)
                          Text(
                            unit,
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 10,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlSection() {
    // Stream này lắng nghe phản hồi trạng thái thực tế từ thiết bị (qua sensorRef)
    return StreamBuilder(
      stream: sensorRef.orderByKey().limitToLast(1).onValue,
      builder: (context, AsyncSnapshot<DatabaseEvent> snapshot) {
        if (!snapshot.hasData || snapshot.data?.snapshot.value == null) {
          return const Center(child: Text("Đang tải..."));
        }

        Map<dynamic, dynamic> allData =
            snapshot.data!.snapshot.value as Map<dynamic, dynamic>;
        var lastKey = allData.keys.first;
        Map<dynamic, dynamic> data = allData[lastKey];

        bool fanState = data['fan'] ?? false;
        bool pumpState = data['pump'] ?? false;
        bool lightState = data['light'] ?? false;
        bool autoMode = data['autoMode'] ?? true;

        // Đồng bộ biến cục bộ để dùng cho logic _handleManualControl
        _currentAutoMode = autoMode;

        return Column(
          children: [
            _buildControlTile(
              title: "Chế độ Tự động",
              subtitle: autoMode ? "ĐANG BẬT" : "THỦ CÔNG (Tự bật sau 30s)",
              icon: autoMode ? Icons.auto_awesome : Icons.touch_app,
              isActived: autoMode,
              onPressed: () => _handleAutoModeChange(!autoMode),
            ),
            _buildControlTile(
              title: "Quạt",
              subtitle: fanState ? "ĐANG BẬT" : "ĐANG TẮT",
              icon: Icons.air_outlined,
              isActived: fanState,
              onPressed: () => _handleManualControl("fan", !fanState),
            ),
            _buildControlTile(
              title: "Bơm",
              subtitle: pumpState ? "ĐANG BẬT" : "ĐANG TẮT",
              icon: Icons.water_damage_outlined,
              isActived: pumpState,
              onPressed: () => _handleManualControl("pump", !pumpState),
            ),
            _buildControlTile(
              title: "Đèn",
              subtitle: lightState ? "ĐANG BẬT" : "ĐANG TẮT",
              icon: Icons.lightbulb_outline,
              isActived: lightState,
              onPressed: () => _handleManualControl("light", !lightState),
            ),
          ],
        );
      },
    );
  }

  Widget _buildControlTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isActived,
    required VoidCallback onPressed,
  }) {
    final Color activeColor = Colors.green[600]!;
    final Color inactiveColor = Colors.grey[700]!;
    final Color displayColor = isActived ? activeColor : inactiveColor;

    return Card(
      elevation: 1.5,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          vertical: 8.0,
          horizontal: 16.0,
        ),
        onTap: onPressed,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Icon(icon, color: displayColor, size: 30),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: displayColor,
          ),
        ),
        subtitle: Text(subtitle, style: TextStyle(color: Colors.grey[600])),
        trailing: Icon(
          isActived ? Icons.toggle_on : Icons.toggle_off,
          color: displayColor,
          size: 40,
        ),
      ),
    );
  }
}
