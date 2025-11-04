import 'dart:async';
import 'dart:math' as math;
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'sensor_chart_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // --- Các biến và hàm logic (Giữ nguyên) ---
  final DatabaseReference sensorRef = FirebaseDatabase.instance.ref(
    "sensorData",
  );
  final DatabaseReference controlRef = FirebaseDatabase.instance.ref(
    "controls",
  );

  Timer? _autoModeTimer;
  bool _currentAutoMode = true;

  void _setControl(String device, bool value) {
    controlRef.child(device).set(value);
  }

  @override
  void dispose() {
    _autoModeTimer?.cancel();
    super.dispose();
  }

  void _handleManualControl(String device, bool value) {
    _autoModeTimer?.cancel();
    Map<String, dynamic> updates = {};
    if (_currentAutoMode) {
      updates["autoMode"] = false;
    }
    updates[device] = value;
    controlRef.update(updates);
    _autoModeTimer = Timer(const Duration(seconds: 30), () {
      _setControl("autoMode", true);
    });
  }

  void _handleAutoModeChange(bool value) {
    _autoModeTimer?.cancel();
    if (value == false) {
      _autoModeTimer = Timer(const Duration(seconds: 30), () {
        _setControl("autoMode", true);
      });
    }
    _setControl("autoMode", value);
  }

  // --- Hàm Build (Giữ nguyên cấu trúc) ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Smart Greenhouse"),
        backgroundColor: Colors.green[700],
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
          _buildSensorSection(), // Widget cảm biến
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
          _buildControlSection(), // Widget điều khiển (giữ nguyên)
        ],
      ),
    );
  }

  // --- Các Widget Helper (Đã thiết kế lại) ---

  // *** THIẾT KẾ LẠI: Dùng GridView cho các đồng hồ đo ***
  Widget _buildSensorSection() {
    return StreamBuilder(
      stream: sensorRef.onValue,
      builder: (context, AsyncSnapshot<DatabaseEvent> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data?.snapshot.value == null) {
          return const Center(child: Text("Không có dữ liệu cảm biến"));
        }
        Map<dynamic, dynamic> allData =
            snapshot.data!.snapshot.value as Map<dynamic, dynamic>;
        var lastKey = allData.keys.last;
        Map<dynamic, dynamic> data = allData[lastKey];

        // Lấy dữ liệu
        double temp = (data['temperature'] ?? 0.0).toDouble();
        double humi = (data['humidity'] ?? 0.0).toDouble();
        int soil = (data['soilMoisture'] ?? 0).toInt();
        double lightLux = (data['lightLevel'] ?? 0.0).toDouble();
        int co2 = (data['co2Level'] ?? 0).toInt();

        // --- Tính toán % cho đồng hồ đo (Giữ nguyên logic) ---
        double tempProgress = (temp / 50.0).clamp(0.0, 1.0);
        double humiProgress = (humi / 100.0).clamp(0.0, 1.0);
        // Giả định: 4095 là khô (0%), 1000 là ướt (100%)
        double soilProgress = ((4095 - soil) / (4095 - 1000)).clamp(0.0, 1.0);
        double lightProgress = (lightLux / 1500.0).clamp(0.0, 1.0);
        double co2Progress = (co2 / 2000.0).clamp(0.0, 1.0);

        // *** SỬA ĐỔI: Dùng 3 CỘT (crossAxisCount: 3) để nhỏ hơn ***
        return GridView.count(
          crossAxisCount: 3, // 3 cột
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10, // Giảm khoảng cách giữa các hàng
          crossAxisSpacing: 10, // Giảm khoảng cách giữa các cột
          // *** SỬA ĐỔI: Tăng childAspectRatio để card "vuông" hơn, nhìn nhỏ hơn ***
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

            // *** SỬA ĐỔI: Độ ẩm đất - HIỂN THỊ GIÁ TRỊ THÔ (không %) ***
            _buildSensorGauge(
              title: "Độ ẩm đất",
              sensorKey: "soilMoisture",
              value: soil.toString(), // <-- HIỂN THỊ GIÁ TRỊ THÔ
              unit: "", // <-- KHÔNG CÓ ĐƠN VỊ
              icon: Icons.eco_outlined,
              color: Colors.brown,
              progress: soilProgress, // <-- Progress bar vẫn chạy đúng
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

  // *** SỬA ĐỔI: Widget đồng hồ đo (Gauge) (Chỉnh kích thước chi tiết) ***
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
          // *** SỬA ĐỔI: Giảm padding trong card ***
          padding: const EdgeInsets.all(8.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // --- Phần đồng hồ tròn ---
              Expanded(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Vòng tròn nền
                    SizedBox(
                      width: double.infinity,
                      height: double.infinity,
                      child: CircularProgressIndicator(
                        value: 1.0,
                        // *** SỬA ĐỔI: Vòng tròn mỏng hơn nữa ***
                        strokeWidth: 6,
                        backgroundColor: color.withOpacity(0.1),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          color.withOpacity(0.1),
                        ),
                      ),
                    ),
                    // Vòng tròn giá trị
                    SizedBox(
                      width: double.infinity,
                      height: double.infinity,
                      child: CircularProgressIndicator(
                        value: progress,
                        // *** SỬA ĐỔI: Vòng tròn mỏng hơn nữa ***
                        strokeWidth: 6,
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                        strokeCap: StrokeCap.round,
                      ),
                    ),
                    // Icon và Giá trị ở giữa
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // *** SỬA ĐỔI: Icon nhỏ hơn nữa ***
                        Icon(icon, color: color, size: 22),
                        const SizedBox(height: 2),
                        Text(
                          value,
                          // *** SỬA ĐỔI: Font chữ nhỏ hơn nữa ***
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: color,
                                fontSize: 16, // Cố định cỡ chữ
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (unit.isNotEmpty) // Chỉ hiển thị nếu có đơn vị
                          Text(
                            unit,
                            // *** SỬA ĐỔI: Font chữ nhỏ hơn nữa ***
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
              // Giảm khoảng cách giữa vòng tròn và tiêu đề
              const SizedBox(height: 6),
              // --- Tiêu đề ---
              Text(
                title,
                style: const TextStyle(
                  // *** SỬA ĐỔI: Font chữ nhỏ hơn nữa ***
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

  // --- PHẦN ĐIỀU KHIỂN (GIỮ NGUYÊN) ---

  // *** GIỮ NGUYÊN: Widget điều khiển dạng danh sách ***
  Widget _buildControlSection() {
    return StreamBuilder(
      stream: controlRef.onValue,
      builder: (context, AsyncSnapshot<DatabaseEvent> snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: Text("Đang tải..."));
        }
        Map<dynamic, dynamic> data =
            snapshot.data!.snapshot.value as Map<dynamic, dynamic>;
        bool fanState = data['fan'] ?? false;
        bool pumpState = data['pump'] ?? false;
        bool lightState = data['light'] ?? false;
        bool autoMode = data['autoMode'] ?? true;
        _currentAutoMode = autoMode;

        return Column(
          children: [
            _buildControlTile(
              title: "Chế độ Tự động",
              subtitle: autoMode ? "ĐANG BẬT" : "THỦ CÔNG (Tự bật sau 30s)",
              icon: autoMode ? Icons.auto_awesome : Icons.touch_app,
              isActived: autoMode,
              onPressed: () {
                _handleAutoModeChange(!autoMode);
              },
            ),
            _buildControlTile(
              title: "Quạt",
              subtitle: fanState ? "ĐANG BẬT" : "ĐANG TẮT",
              icon: Icons.air_outlined,
              isActived: fanState,
              onPressed: () {
                _handleManualControl("fan", !fanState);
              },
            ),
            _buildControlTile(
              title: "Bơm",
              subtitle: pumpState ? "ĐANG BẬT" : "ĐANG TẮT",
              icon: Icons.water_damage_outlined,
              isActived: pumpState,
              onPressed: () {
                _handleManualControl("pump", !pumpState);
              },
            ),
            _buildControlTile(
              title: "Đèn",
              subtitle: lightState ? "ĐANG BẬT" : "ĐANG TẮT",
              icon: Icons.lightbulb_outline,
              isActived: lightState,
              onPressed: () {
                _handleManualControl("light", !lightState);
              },
            ),
          ],
        );
      },
    );
  }

  // *** GIỮ NGUYÊN: Widget Điều khiển dạng ListTile có thể "Nhấn" ***
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
