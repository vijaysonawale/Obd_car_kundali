// lib/screens/health_screen.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/dtc_model.dart';
import '../models/vehicle_data.dart';

class HealthScreen extends StatelessWidget {
  final List<DtcModel> dtcList;
  final Map<String, double> liveValues;
  final List<ReadinessMonitor> readinessMonitors;

  const HealthScreen({
    super.key,
    required this.dtcList,
    required this.liveValues,
    required this.readinessMonitors,
  });

  // ─── HEALTH SCORE CALCULATION ───────────────────────
  int get _score {
    int s = 100;

    // DTCs  (max deduction: 60)
    for (final dtc in dtcList) {
      s -= dtc.status == 'Confirmed' ? 18 : 8;
    }

    // Coolant
    final coolant = liveValues['0105'] ?? 80;
    if (coolant > 108)
      s -= 25;
    else if (coolant > 100)
      s -= 12;
    else if (coolant < 60 && coolant > 0)
      s -= 5; // running cold

    // Fuel trims
    final stft = (liveValues['0106'] ?? 0).abs();
    final ltft = (liveValues['0107'] ?? 0).abs();
    if (stft > 20 || ltft > 15)
      s -= 12;
    else if (stft > 12 || ltft > 10)
      s -= 6;

    // Readiness monitors not complete
    final notReady = readinessMonitors
        .where((m) => m.isSupported && !m.isComplete)
        .length;
    s -= notReady * 3;

    return s.clamp(0, 100);
  }

  Color get _scoreColor {
    final s = _score;
    if (s >= 85) return Colors.green;
    if (s >= 65) return Colors.orange;
    return Colors.red;
  }

  String get _scoreLabel {
    final s = _score;
    if (s >= 90) return 'Excellent';
    if (s >= 80) return 'Good';
    if (s >= 65) return 'Fair';
    if (s >= 40) return 'Poor';
    return 'Critical';
  }

  String get _scoreEmoji {
    final s = _score;
    if (s >= 90) return '🟢';
    if (s >= 80) return '🟡';
    if (s >= 65) return '🟠';
    return '🔴';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Vehicle Health'),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildScoreCard(),
          const SizedBox(height: 16),
          _buildChecklist(),
          const SizedBox(height: 12),
          _buildFaultSection(),
          const SizedBox(height: 12),
          _buildSensorSection(),
          const SizedBox(height: 12),
          _buildReadinessSection(),
        ],
      ),
    );
  }

  Widget _buildScoreCard() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_scoreColor.withOpacity(0.85), _scoreColor.withOpacity(0.6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: _scoreColor.withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            height: 110,
            width: 110,
            child: CustomPaint(
              painter: _ScoreRingPainter(
                score: _score / 100,
                color: Colors.white,
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$_score',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '/100',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$_scoreEmoji $_scoreLabel',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  dtcList.isEmpty
                      ? 'No fault codes detected.\nAll systems nominal.'
                      : '${dtcList.length} fault code(s) detected.\nAttention required.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChecklist() {
    final items = [
      _CheckItem(
        label: 'Fault Codes',
        ok: dtcList.isEmpty,
        detail: dtcList.isEmpty
            ? 'None detected'
            : '${dtcList.length} code(s) found',
        icon: Icons.error_outline,
      ),
      _CheckItem(
        label: 'Coolant Temp',
        ok: (liveValues['0105'] ?? 80) <= 100,
        detail: '${(liveValues['0105'] ?? 0).toStringAsFixed(0)}°C',
        icon: Icons.thermostat,
      ),
      _CheckItem(
        label: 'Fuel Trims',
        ok:
            (liveValues['0106'] ?? 0).abs() <= 10 &&
            (liveValues['0107'] ?? 0).abs() <= 10,
        detail:
            'STFT ${(liveValues['0106'] ?? 0).toStringAsFixed(1)}% / LTFT ${(liveValues['0107'] ?? 0).toStringAsFixed(1)}%',
        icon: Icons.local_gas_station,
      ),
      _CheckItem(
        label: 'Readiness Monitors',
        ok: !readinessMonitors.any((m) => m.isSupported && !m.isComplete),
        detail: readinessMonitors.isEmpty
            ? 'Not checked'
            : '${readinessMonitors.where((m) => m.isComplete).length}/${readinessMonitors.length} ready',
        icon: Icons.verified,
      ),
    ];

    return _card(
      '🔍 Quick Health Check',
      Column(children: items.map(_buildCheckRow).toList()),
    );
  }

  Widget _buildCheckRow(_CheckItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: item.ok ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: item.ok ? Colors.green.shade200 : Colors.red.shade200,
        ),
      ),
      child: Row(
        children: [
          Icon(
            item.icon,
            color: item.ok ? Colors.green.shade600 : Colors.red.shade600,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Text(
                  item.detail,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          Icon(
            item.ok ? Icons.check_circle : Icons.warning_rounded,
            color: item.ok ? Colors.green : Colors.red,
            size: 22,
          ),
        ],
      ),
    );
  }

  Widget _buildFaultSection() {
    return _card(
      '⚠️ Fault Codes',
      dtcList.isEmpty
          ? Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'No fault codes stored',
                  style: TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            )
          : Column(
              children: dtcList.map((dtc) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: dtc.status == 'Confirmed'
                        ? Colors.red.shade50
                        : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error,
                        color: dtc.status == 'Confirmed'
                            ? Colors.red
                            : Colors.orange,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        dtc.code,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          dtc.description,
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: dtc.status == 'Confirmed'
                              ? Colors.red
                              : Colors.orange,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          dtc.status,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }

  Widget _buildSensorSection() {
    final coolant = liveValues['0105'] ?? 0;
    final stft = liveValues['0106'] ?? 0;
    final ltft = liveValues['0107'] ?? 0;
    final battery = liveValues['0142'] ?? 0;

    return _card(
      '📊 Sensor Status',
      Column(
        children: [
          _sensorBar(
            'Coolant Temp',
            coolant,
            0,
            120,
            '${coolant.toStringAsFixed(0)}°C',
            coolant > 100 ? Colors.red : Colors.blue,
          ),
          _sensorBar(
            'STFT B1',
            stft + 25,
            -25,
            50,
            '${stft >= 0 ? '+' : ''}${stft.toStringAsFixed(1)}%',
            stft.abs() > 10 ? Colors.red : Colors.green,
          ),
          _sensorBar(
            'LTFT B1',
            ltft + 25,
            -25,
            50,
            '${ltft >= 0 ? '+' : ''}${ltft.toStringAsFixed(1)}%',
            ltft.abs() > 10 ? Colors.red : Colors.green,
          ),
          if (battery > 0)
            _sensorBar(
              'Battery',
              battery,
              10,
              16,
              '${battery.toStringAsFixed(1)}V',
              battery < 12 ? Colors.red : Colors.green,
            ),
        ],
      ),
    );
  }

  Widget _sensorBar(
    String label,
    double value,
    double min,
    double max,
    String display,
    Color color,
  ) {
    final progress = ((value - min) / (max - min)).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
              Text(
                display,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: color,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation(color),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReadinessSection() {
    if (readinessMonitors.isEmpty) return const SizedBox.shrink();
    return _card(
      '🔧 Readiness Monitors',
      Column(
        children: readinessMonitors.map((m) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Icon(
                  m.isComplete ? Icons.check_circle : Icons.pending,
                  color: m.isComplete
                      ? Colors.green
                      : m.isSupported
                      ? Colors.orange
                      : Colors.grey,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(m.name, style: const TextStyle(fontSize: 14)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: m.isComplete
                        ? Colors.green.shade600
                        : m.isSupported
                        ? Colors.orange
                        : Colors.grey,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    m.isComplete
                        ? 'Ready'
                        : m.isSupported
                        ? 'Not Ready'
                        : 'N/A',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _card(String title, Widget child) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _CheckItem {
  final String label, detail;
  final bool ok;
  final IconData icon;
  _CheckItem({
    required this.label,
    required this.ok,
    required this.detail,
    required this.icon,
  });
}

class _ScoreRingPainter extends CustomPainter {
  final double score;
  final Color color;
  _ScoreRingPainter({required this.score, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = color.withOpacity(0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10,
    );

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 2 * score,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_ScoreRingPainter old) => old.score != score;
}
