// Tên tệp: sensor_chart_screen.dart
import 'package:firebase_database/firebase_database.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:math';

// *** SỬA ĐỔI: Enum định nghĩa các KHOẢNG THỜI GIAN LỌC ***
enum ChartTimeWindow {
  lastHour, // 1 giờ qua (12 mốc x 5 phút)
  last24Hours, // 24 giờ qua (24 mốc x 1 giờ)
  last30Days, // 30 ngày qua (30 mốc x 1 ngày)
  last12Months, // 12 tháng qua (12 mốc x 1 tháng)
}

class SensorChartScreen extends StatefulWidget {
  final String sensorKey;
  final String sensorTitle;

  const SensorChartScreen({
    Key? key,
    required this.sensorKey,
    required this.sensorTitle,
  }) : super(key: key);

  @override
  State<SensorChartScreen> createState() => _SensorChartScreenState();
}

class _SensorChartScreenState extends State<SensorChartScreen> {
  final DatabaseReference sensorRef = FirebaseDatabase.instance.ref(
    "sensorData",
  );

  // *** SỬA ĐỔI: Biến lưu trữ khoảng thời gian, mặc định là "1 Giờ" ***
  ChartTimeWindow _selectedWindow = ChartTimeWindow.lastHour;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("${widget.sensorTitle}"),
        backgroundColor: Colors.green[700],
      ),
      body: Column(
        children: [
          // *** SỬA ĐỔI: Các nút chọn khoảng thời gian ***
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildTimeWindowButton("1 Giờ", ChartTimeWindow.lastHour),
                  _buildTimeWindowButton("24 Giờ", ChartTimeWindow.last24Hours),
                  _buildTimeWindowButton("30 Ngày", ChartTimeWindow.last30Days),
                  _buildTimeWindowButton(
                    "12 Tháng",
                    ChartTimeWindow.last12Months,
                  ),
                ],
              ),
            ),
          ),

          // Biểu đồ
          Expanded(
            child: StreamBuilder(
              stream: sensorRef.onValue,
              builder: (context, AsyncSnapshot<DatabaseEvent> snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData ||
                    snapshot.data?.snapshot.value == null) {
                  return const Center(child: Text("Không có dữ liệu lịch sử."));
                }

                List<dynamic> records = [];
                try {
                  final Map<dynamic, dynamic> allData =
                      snapshot.data!.snapshot.value as Map<dynamic, dynamic>;
                  records = allData.values.toList();
                  // Sắp xếp không còn quá quan trọng vì chúng ta sẽ lọc, nhưng vẫn nên làm
                  records.sort(
                    (a, b) =>
                        (a['timestamp'] ?? 0).compareTo(b['timestamp'] ?? 0),
                  );
                } catch (e) {
                  return Center(child: Text("Lỗi xử lý dữ liệu: $e"));
                }

                if (records.isEmpty) {
                  return const Center(child: Text("Không có bản ghi nào."));
                }

                // *** THÊM MỚI: Lấy thời gian hiện tại làm mốc ***
                final DateTime now = DateTime.now();

                // *** THÊM MỚI: Xử lý (lọc và nhóm) dữ liệu theo lựa chọn ***
                final List<FlSpot> chartSpots = _processData(
                  records,
                  _selectedWindow,
                  now,
                  widget.sensorKey,
                );

                // (Không cần kiểm tra chartSpots.isEmpty nữa, vì biểu đồ sẽ tự vẽ trục trống)

                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 24, 16),
                  child: LineChart(
                    // Truyền cả cách nhóm và khoảng thời gian
                    _buildChartData(
                      context,
                      chartSpots,
                      _selectedWindow,
                      now,
                      widget.sensorKey, // Truyền sensorKey
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // *** THÊM MỚI: Hàm xử lý (LỌC và NHÓM) dữ liệu ***
  List<FlSpot> _processData(
    List<dynamic> records,
    ChartTimeWindow window,
    DateTime now,
    String sensorKey,
  ) {
    final Map<double, List<double>> groupedData = {};
    DateTime startTime;

    // 1. Xác định thời gian bắt đầu (startTime)
    switch (window) {
      case ChartTimeWindow.lastHour:
        startTime = now.subtract(const Duration(hours: 1));
        break;
      case ChartTimeWindow.last24Hours:
        startTime = now.subtract(const Duration(hours: 24));
        break;
      case ChartTimeWindow.last30Days:
        startTime = now.subtract(const Duration(days: 30));
        break;
      case ChartTimeWindow.last12Months:
        // Lấy ngày này năm ngoái
        startTime = DateTime(
          now.year - 1,
          now.month,
          now.day,
          now.hour,
          now.minute,
        );
        break;
    }

    final double startMillis = startTime.millisecondsSinceEpoch.toDouble();

    // 2. Lọc và Nhóm dữ liệu
    for (var record in records) {
      if (record is Map &&
          record.containsKey(sensorKey) &&
          record.containsKey('timestamp')) {
        final double yValue = (record[sensorKey] ?? 0.0).toDouble();
        final double xValue = (record['timestamp'] ?? 0.0).toDouble();

        // *** LỌC ***
        if (xValue < startMillis) continue; // Bỏ qua dữ liệu quá cũ

        // *** NHÓM ***
        final DateTime dt = DateTime.fromMillisecondsSinceEpoch(xValue.toInt());
        DateTime keyDt;

        switch (window) {
          case ChartTimeWindow.lastHour:
            // Nhóm theo mốc 5 phút
            final int minute = (dt.minute / 5).floor() * 5;
            keyDt = DateTime(dt.year, dt.month, dt.day, dt.hour, minute);
            break;
          case ChartTimeWindow.last24Hours:
            // Nhóm theo mốc 1 giờ
            keyDt = DateTime(dt.year, dt.month, dt.day, dt.hour);
            break;
          case ChartTimeWindow.last30Days:
            // Nhóm theo mốc 1 ngày
            keyDt = DateTime(dt.year, dt.month, dt.day);
            break;
          case ChartTimeWindow.last12Months:
            // Nhóm theo mốc 1 tháng
            keyDt = DateTime(dt.year, dt.month, 1);
            break;
        }

        final double keyTimestamp = keyDt.millisecondsSinceEpoch.toDouble();
        if (groupedData.containsKey(keyTimestamp)) {
          groupedData[keyTimestamp]!.add(yValue);
        } else {
          groupedData[keyTimestamp] = [yValue];
        }
      }
    }

    // 3. Tính trung bình và tạo Spot
    final List<FlSpot> spots = [];
    for (var entry in groupedData.entries) {
      final double x = entry.key;
      final double yAvg =
          entry.value.reduce((a, b) => a + b) / entry.value.length;
      spots.add(FlSpot(x, yAvg));
    }

    spots.sort((a, b) => a.x.compareTo(b.x));
    return spots;
  }

  // *** SỬA ĐỔI: Widget nút chọn (đổi tên) ***
  Widget _buildTimeWindowButton(String text, ChartTimeWindow window) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: ElevatedButton(
        onPressed: () {
          setState(() {
            _selectedWindow = window;
          });
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: _selectedWindow == window
              ? Colors.green[700]
              : Colors.grey[300],
          foregroundColor: _selectedWindow == window
              ? Colors.white
              : Colors.black87,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          elevation: 0,
        ),
        child: Text(text, style: const TextStyle(fontSize: 12)),
      ),
    );
  }

  // *** THÊM MỚI: Hàm helper để lấy Tọa độ Y (min/max) ***
  ({double? minY, double? maxY}) _getSensorRange(String key) {
    switch (key) {
      case 'temperature':
      case 'humidity':
        return (minY: 0.0, maxY: 100.0);
      case 'soilMoisture':
      case 'lightLevel':
        return (minY: 0.0, maxY: 10000.0);
      case 'co2Level':
        return (minY: 0.0, maxY: 40000.0);
      default:
        // Nếu không khớp, để fl_chart tự quyết định
        return (minY: null, maxY: null);
    }
  }

  // *** SỬA ĐỔI: Hàm cấu hình biểu đồ (nhận sensorKey, now, và window) ***
  LineChartData _buildChartData(
    BuildContext context,
    List<FlSpot> spots,
    ChartTimeWindow window,
    DateTime now,
    String sensorKey,
  ) {
    // 1. Cấu hình Trục Y (Nâng cao tọa độ)
    final range = _getSensorRange(sensorKey);

    // 2. Cấu hình Trục X (Cố định khoảng thời gian)
    final double maxX = now.millisecondsSinceEpoch.toDouble();
    double minX;

    switch (window) {
      case ChartTimeWindow.lastHour:
        minX = now
            .subtract(const Duration(hours: 1))
            .millisecondsSinceEpoch
            .toDouble();
        break;
      case ChartTimeWindow.last24Hours:
        minX = now
            .subtract(const Duration(hours: 24))
            .millisecondsSinceEpoch
            .toDouble();
        break;
      case ChartTimeWindow.last30Days:
        minX = now
            .subtract(const Duration(days: 30))
            .millisecondsSinceEpoch
            .toDouble();
        break;
      case ChartTimeWindow.last12Months:
        minX = DateTime(
          now.year - 1,
          now.month,
          now.day,
        ).millisecondsSinceEpoch.toDouble();
        break;
    }

    // Cấu hình gradient
    final List<Color> gradientColors = [Colors.green[700]!, Colors.green[200]!];

    return LineChartData(
      // *** SỬA ĐỔI: Thêm min/max cho Trục X và Y ***
      minY: range.minY,
      maxY: range.maxY,
      minX: minX,
      maxX: maxX,

      // Cấu hình Tooltip (Giữ nguyên)
      lineTouchData: LineTouchData(
        handleBuiltInTouches: true,
        touchTooltipData: LineTouchTooltipData(
          getTooltipItems: (List<LineBarSpot> touchedSpots) {
            return touchedSpots.map((barSpot) {
              final flSpot = barSpot;
              final DateTime date = DateTime.fromMillisecondsSinceEpoch(
                flSpot.x.toInt(),
              );
              String timeText;
              if (window == ChartTimeWindow.lastHour ||
                  window == ChartTimeWindow.last24Hours) {
                timeText = DateFormat('dd/MM HH:mm').format(date);
              } else if (window == ChartTimeWindow.last30Days) {
                timeText = DateFormat('dd/MM/yyyy').format(date);
              } else {
                timeText = DateFormat('MM/yyyy').format(date);
              }
              return LineTooltipItem(
                '${flSpot.y.toStringAsFixed(1)} \n',
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
                children: [
                  TextSpan(
                    text: timeText,
                    style: TextStyle(color: Colors.grey[300]),
                  ),
                ],
              );
            }).toList();
          },
        ),
      ),

      // Cấu hình lưới (Giu nguyên)
      gridData: FlGridData(
        show: true,
        drawVerticalLine: true,
        getDrawingHorizontalLine: (value) =>
            FlLine(color: Colors.grey[200]!, strokeWidth: 1),
        getDrawingVerticalLine: (value) =>
            FlLine(color: Colors.grey[200]!, strokeWidth: 1),
      ),

      // Cấu hình tiêu đề (Trục)
      titlesData: FlTitlesData(
        show: true,
        // Trục X (Bottom)
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            // Để fl_chart tự quyết định interval
            getTitlesWidget: (value, meta) {
              // Chỉ hiển thị nhãn ở các mốc chính
              if (value == meta.min || value == meta.max) return Container();

              final DateTime date = DateTime.fromMillisecondsSinceEpoch(
                value.toInt(),
              );
              String formattedText;

              switch (window) {
                case ChartTimeWindow.lastHour:
                  formattedText = DateFormat('HH:mm').format(date);
                  break;
                case ChartTimeWindow.last24Hours:
                  formattedText = DateFormat('HH:mm').format(date);
                  break;
                case ChartTimeWindow.last30Days:
                  formattedText = DateFormat('dd/MM').format(date);
                  break;
                case ChartTimeWindow.last12Months:
                  formattedText = DateFormat('MM/yy').format(date);
                  break;
              }
              return SideTitleWidget(
                axisSide: meta.axisSide,
                space: 8.0,
                child: Text(
                  formattedText,
                  style: const TextStyle(fontSize: 10),
                ),
              );
            },
          ),
        ),

        // Trục Y (Left)
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            // Để fl_chart tự quyết định interval dựa trên min/max
            getTitlesWidget: (value, meta) {
              // Chỉ hiển thị nhãn ở các mốc chính
              if (value == meta.min || value == meta.max) return Container();
              return Text(
                value.toStringAsFixed(0),
                style: const TextStyle(fontSize: 10),
                textAlign: TextAlign.left,
              );
            },
          ),
        ),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
      ),

      borderData: FlBorderData(
        show: true,
        border: Border.all(color: Colors.grey[300]!),
      ),

      // Cấu hình đường line
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          gradient: LinearGradient(colors: gradientColors),
          barWidth: 3,
          isStrokeCapRound: true,
          // Hiển thị chấm tròn (tất cả các chế độ giờ đều là nhóm)
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, percent, barData, index) {
              return FlDotCirclePainter(
                radius: 4,
                color: Colors.white,
                strokeWidth: 2,
                strokeColor: Colors.green[700]!,
              );
            },
          ),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              colors: gradientColors
                  .map((color) => color.withOpacity(0.3))
                  .toList(),
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
      ],
    );
  }
}
