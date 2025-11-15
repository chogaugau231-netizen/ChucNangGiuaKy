import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Màn hình Cài đặt Ngưỡng
class ThresholdSettingsScreen extends StatefulWidget {
  const ThresholdSettingsScreen({Key? key}) : super(key: key);

  @override
  State<ThresholdSettingsScreen> createState() =>
      _ThresholdSettingsScreenState();
}

class _ThresholdSettingsScreenState extends State<ThresholdSettingsScreen> {
  // Tham chiếu đến Firebase
  // 1. Để GHI ngưỡng mới
  final DatabaseReference controlThresholdRef = FirebaseDatabase.instance.ref(
    "controls/thresholds",
  );
  // 2. Để ĐỌC ngưỡng hiện tại (từ log mới nhất)
  final DatabaseReference sensorRef = FirebaseDatabase.instance.ref(
    "sensorData",
  );

  // Controllers cho các ô TextField
  final TextEditingController _tHighC = TextEditingController();
  final TextEditingController _tLowC = TextEditingController();
  final TextEditingController _sDryC = TextEditingController();
  final TextEditingController _sWetC = TextEditingController();
  final TextEditingController _lDarkC = TextEditingController();
  final TextEditingController _lBrightC = TextEditingController();
  final TextEditingController _cHighC = TextEditingController();
  final TextEditingController _cLowC = TextEditingController();

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCurrentThresholds();
  }

  @override
  void dispose() {
    // Giải phóng controllers
    _tHighC.dispose();
    _tLowC.dispose();
    _sDryC.dispose();
    _sWetC.dispose();
    _lDarkC.dispose();
    _lBrightC.dispose();
    _cHighC.dispose();
    _cLowC.dispose();
    super.dispose();
  }

  /// Đọc ngưỡng hiện tại từ /sensorData (entry mới nhất)
  Future<void> _loadCurrentThresholds() async {
    setState(() {
      _isLoading = true;
    });
    try {
      // 1. Lấy entry mới nhất từ sensorData
      final snapshot = await sensorRef.orderByKey().limitToLast(1).get();

      if (snapshot.value == null) {
        // Nếu không có dữ liệu, dùng giá trị mặc định của ESP32
        _setControllerValues(null);
        return;
      }

      // 2. Trích xuất object 'thresholds'
      final allData = snapshot.value as Map<dynamic, dynamic>;
      final lastKey = allData.keys.first;
      final lastData = allData[lastKey] as Map<dynamic, dynamic>;

      if (lastData.containsKey('thresholds')) {
        final thresholds = lastData['thresholds'] as Map<dynamic, dynamic>;
        // 3. Điền vào các ô text
        _setControllerValues(thresholds);
      } else {
        // Dùng giá trị mặc định nếu không tìm thấy
        _setControllerValues(null);
      }
    } catch (e) {
      print("Lỗi khi tải ngưỡng: $e");
      _setControllerValues(null); // Dùng mặc định nếu lỗi
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Lỗi khi tải ngưỡng: $e")));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Helper: Gán giá trị cho controllers (với giá trị mặc định)
  void _setControllerValues(Map<dynamic, dynamic>? thresholds) {
    _tHighC.text = thresholds?['tHigh']?.toString() ?? '30';
    _tLowC.text = thresholds?['tLow']?.toString() ?? '27';
    _sDryC.text = thresholds?['sDry']?.toString() ?? '4000';
    _sWetC.text = thresholds?['sWet']?.toString() ?? '3000';
    _lDarkC.text = thresholds?['lDark']?.toString() ?? '50';
    _lBrightC.text = thresholds?['lBright']?.toString() ?? '300';
    _cHighC.text = thresholds?['cHigh']?.toString() ?? '1000';
    _cLowC.text = thresholds?['cLow']?.toString() ?? '400';
  }

  /// Lưu ngưỡng mới vào /controls/thresholds
  Future<void> _saveThresholds() async {
    // Validate và Parse (chuyển text thành số)
    final double? tHigh = double.tryParse(_tHighC.text);
    final double? tLow = double.tryParse(_tLowC.text);
    final int? sDry = int.tryParse(_sDryC.text);
    final int? sWet = int.tryParse(_sWetC.text);
    final int? lDark = int.tryParse(_lDarkC.text);
    final int? lBright = int.tryParse(_lBrightC.text);
    final int? cHigh = int.tryParse(_cHighC.text);
    final int? cLow = int.tryParse(_cLowC.text);

    // Kiểm tra nếu có giá trị nào rỗng hoặc sai
    if ([
      tHigh,
      tLow,
      sDry,
      sWet,
      lDark,
      lBright,
      cHigh,
      cLow,
    ].any((v) => v == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Vui lòng nhập đúng tất cả giá trị (số)"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Tạo Map dữ liệu để gửi đi
    final Map<String, dynamic> newThresholds = {
      "tHigh": tHigh,
      "tLow": tLow,
      "sDry": sDry,
      "sWet": sWet,
      "lDark": lDark,
      "lBright": lBright,
      "cHigh": cHigh,
      "cLow": cLow,
    };

    try {
      // Gửi lên Firebase
      await controlThresholdRef.update(newThresholds);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Đã lưu ngưỡng mới!"),
            backgroundColor: Colors.green,
          ),
        );
        // Quay lại màn hình chính sau khi lưu
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Lỗi khi lưu: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Cài đặt Ngưỡng Tự động"),
        backgroundColor: Colors.green[700],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                const Text("Các giá trị này được dùng khi ở chế độ Tự động."),
                const SizedBox(height: 20),
                _buildSectionTitle("🌡️ Nhiệt độ"),
                _buildThresholdField(
                  controller: _tHighC,
                  label: "Bật quạt nếu >",
                  unit: "°C",
                ),
                _buildThresholdField(
                  controller: _tLowC,
                  label: "Tắt quạt nếu <",
                  unit: "°C",
                ),
                const Divider(height: 30),
                _buildSectionTitle("💧 Độ ẩm đất"),
                _buildThresholdField(
                  controller: _sDryC,
                  label: "Bật bơm nếu > (Khô)",
                  unit: "",
                ),
                _buildThresholdField(
                  controller: _sWetC,
                  label: "Tắt bơm nếu < (Ướt)",
                  unit: "",
                ),
                const Divider(height: 30),
                _buildSectionTitle("☀️ Ánh sáng (6h - 18h)"),
                _buildThresholdField(
                  controller: _lDarkC,
                  label: "Bật đèn nếu <",
                  unit: "lx",
                ),
                _buildThresholdField(
                  controller: _lBrightC,
                  label: "Tắt đèn nếu >",
                  unit: "lx",
                ),
                const Divider(height: 30),
                _buildSectionTitle("💨 CO2"),
                _buildThresholdField(
                  controller: _cHighC,
                  label: "Bật quạt nếu >",
                  unit: "ppm",
                ),
                _buildThresholdField(
                  controller: _cLowC,
                  label: "Ngưỡng thấp",
                  unit: "ppm",
                ),
                const SizedBox(height: 30),
                ElevatedButton(
                  onPressed: _saveThresholds,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[600],
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  child: const Text("Lưu thay đổi"),
                ),
              ],
            ),
    );
  }

  // Helper Widget cho Tiêu đề
  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }

  // Helper Widget cho ô nhập liệu
  Widget _buildThresholdField({
    required TextEditingController controller,
    required String label,
    required String unit,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          suffixText: unit,
          border: const OutlineInputBorder(),
        ),
        // Chỉ cho phép nhập số và dấu chấm
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
        ],
      ),
    );
  }
}
