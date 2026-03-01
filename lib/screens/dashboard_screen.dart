// lib/screens/dashboard_screen.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';

class DashboardScreen extends StatefulWidget {
  final ValueNotifier<Map<String, double>> valuesNotifier;
  const DashboardScreen({super.key, required this.valuesNotifier});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _blinkCtrl;

  @override
  void initState() {
    super.initState();
    _blinkCtrl =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 800))
          ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _blinkCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07071A),
      appBar: AppBar(
        title: const Text('DASHBOARD',
            style: TextStyle(
                letterSpacing: 4,
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.white)),
        backgroundColor: const Color(0xFF07071A),
        foregroundColor: Colors.white,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ValueListenableBuilder<Map<String, double>>(
        valueListenable: widget.valuesNotifier,
        builder: (context, values, _) {
          final rpm = values['010C'] ?? 0;
          final speed = values['010D'] ?? 0;
          final coolant = values['0105'] ?? 0;
          final load = values['0104'] ?? 0;
          final throttle = values['0111'] ?? 0;
          final maf = values['0110'] ?? 0;
          final iat = values['010F'] ?? 0;
          final map = values['010B'] ?? 0;
          final stft = values['0106'] ?? 0;
          final ltft = values['0107'] ?? 0;
          final timing = values['010E'] ?? 0;
          final fuel = values['012F'] ?? 0;

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              children: [
                // === BIG GAUGES ===
                Row(
                  children: [
                    Expanded(
                      child: _GaugeCard(
                        label: 'RPM',
                        value: rpm,
                        max: 8000,
                        unit: 'rpm',
                        color: const Color(0xFF00B4FF),
                        dangerAt: 6500,
                        blinkCtrl: _blinkCtrl,
                        warningAt: 5500,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _GaugeCard(
                        label: 'SPEED',
                        value: speed,
                        max: 200,
                        unit: 'km/h',
                        color: const Color(0xFF00FF9C),
                        dangerAt: 130,
                        blinkCtrl: _blinkCtrl,
                        warningAt: 100,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // === SMALL GAUGES ===
                Row(
                  children: [
                    Expanded(child: _SmallGauge('COOLANT', coolant, 0, 130, '°C', Colors.orange, dangerAt: 103)),
                    const SizedBox(width: 8),
                    Expanded(child: _SmallGauge('LOAD', load, 0, 100, '%', Colors.purple, dangerAt: 85)),
                    const SizedBox(width: 8),
                    Expanded(child: _SmallGauge('THROTTLE', throttle, 0, 100, '%', Colors.teal, dangerAt: 90)),
                  ],
                ),
                const SizedBox(height: 12),
                // === DATA TILES ===
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 1.35,
                  children: [
                    _DataTile('MAF', '${maf.toStringAsFixed(1)} g/s', Icons.air, Colors.blue),
                    _DataTile('IAT', '${iat.toStringAsFixed(0)}°C', Icons.thermostat_outlined, Colors.cyan),
                    _DataTile('MAP', '${map.toStringAsFixed(0)} kPa', Icons.compress, Colors.green),
                    _DataTile('STFT', '${stft >= 0 ? '+' : ''}${stft.toStringAsFixed(1)}%', Icons.tune, stft.abs() > 10 ? Colors.red : Colors.orange),
                    _DataTile('LTFT', '${ltft >= 0 ? '+' : ''}${ltft.toStringAsFixed(1)}%', Icons.timeline, ltft.abs() > 10 ? Colors.red : Colors.teal),
                    _DataTile('TIMING', '${timing.toStringAsFixed(1)}°', Icons.schedule, Colors.purple),
                    _DataTile('FUEL LVL', '${fuel.toStringAsFixed(0)}%', Icons.local_gas_station, fuel < 15 ? Colors.red : Colors.green),
                    _DataTile('O2 S1', '${(values['0114'] ?? 0).toStringAsFixed(2)} V', Icons.sensors, Colors.indigo),
                    _DataTile('BATTERY', '${(values['0142'] ?? 0).toStringAsFixed(1)} V', Icons.battery_charging_full, Colors.lime),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// BIG GAUGE CARD
// ─────────────────────────────────────────────────────────
class _GaugeCard extends StatelessWidget {
  final String label;
  final double value;
  final double max;
  final String unit;
  final Color color;
  final double dangerAt;
  final double warningAt;
  final AnimationController blinkCtrl;

  const _GaugeCard({
    required this.label,
    required this.value,
    required this.max,
    required this.unit,
    required this.color,
    required this.dangerAt,
    required this.warningAt,
    required this.blinkCtrl,
  });

  @override
  Widget build(BuildContext context) {
    final isDanger = value >= dangerAt;
    final isWarn = value >= warningAt && !isDanger;
    final displayColor = isDanger ? Colors.red : isWarn ? Colors.orange : color;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F28),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDanger ? Colors.red.withOpacity(0.5) : Colors.white.withOpacity(0.06),
        ),
        boxShadow: isDanger
            ? [BoxShadow(color: Colors.red.withOpacity(0.2), blurRadius: 20)]
            : [],
      ),
      child: Column(
        children: [
          AnimatedBuilder(
            animation: blinkCtrl,
            builder: (_, __) => Text(
              label,
              style: TextStyle(
                color: isDanger
                    ? Colors.red.withOpacity(0.5 + 0.5 * blinkCtrl.value)
                    : Colors.grey.shade600,
                fontSize: 11,
                letterSpacing: 3,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 170,
            width: double.infinity,
            child: CustomPaint(
              painter: _GaugePainter(
                value: value,
                max: max,
                color: displayColor,
                dangerAt: dangerAt,
                warningAt: warningAt,
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        value.toStringAsFixed(0),
                        style: TextStyle(
                          color: displayColor,
                          fontSize: 42,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                          shadows: [Shadow(color: displayColor.withOpacity(0.5), blurRadius: 12)],
                        ),
                      ),
                      Text(
                        unit,
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12, letterSpacing: 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// SMALL GAUGE
// ─────────────────────────────────────────────────────────
class _SmallGauge extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final String unit;
  final Color color;
  final double dangerAt;

  const _SmallGauge(this.label, this.value, this.min, this.max, this.unit, this.color,
      {required this.dangerAt});

  @override
  Widget build(BuildContext context) {
    final isDanger = value >= dangerAt;
    final c = isDanger ? Colors.red : color;
    final progress = ((value - min) / (max - min)).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F28),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDanger ? Colors.red.withOpacity(0.5) : Colors.white.withOpacity(0.05),
        ),
      ),
      child: Column(
        children: [
          Text(label,
              style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 9,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          SizedBox(
            height: 75,
            width: 75,
            child: CustomPaint(
              painter: _SmallGaugePainter(progress: progress, color: c),
              child: Center(
                child: Text(
                  value.toStringAsFixed(0),
                  style: TextStyle(
                    color: c,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    shadows: [Shadow(color: c.withOpacity(0.4), blurRadius: 8)],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(unit, style: TextStyle(color: Colors.grey.shade700, fontSize: 9)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// DATA TILE
// ─────────────────────────────────────────────────────────
class _DataTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _DataTile(this.label, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F28),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color.withOpacity(0.8), size: 18),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  shadows: [Shadow(color: color.withOpacity(0.3), blurRadius: 6)],
                ),
              ),
              Text(label,
                  style: TextStyle(
                      color: Colors.grey.shade700, fontSize: 8, letterSpacing: 0.5)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// CUSTOM PAINTERS
// ─────────────────────────────────────────────────────────
class _GaugePainter extends CustomPainter {
  final double value;
  final double max;
  final Color color;
  final double dangerAt;
  final double warningAt;

  _GaugePainter({
    required this.value,
    required this.max,
    required this.color,
    required this.dangerAt,
    required this.warningAt,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.55);
    final radius = size.width * 0.43;
    const sw = 13.0;
    const startAngle = math.pi * 0.72;
    const sweepAngle = math.pi * 1.56;

    // BG arc
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle, sweepAngle, false,
      Paint()
        ..color = const Color(0xFF1A1A3A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw
        ..strokeCap = StrokeCap.round,
    );

    // Warning zone
    final warnProgress = (max - warningAt) / max;
    final dangerProgress = (max - dangerAt) / max;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle + sweepAngle * (1 - warnProgress),
      sweepAngle * (warnProgress - dangerProgress), false,
      Paint()
        ..color = Colors.orange.withOpacity(0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw
        ..strokeCap = StrokeCap.round,
    );

    // Danger zone
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle + sweepAngle * (1 - dangerProgress),
      sweepAngle * dangerProgress, false,
      Paint()
        ..color = Colors.red.withOpacity(0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw
        ..strokeCap = StrokeCap.round,
    );

    // Value arc
    final progress = (value / max).clamp(0.0, 1.0);
    if (progress > 0.001) {
      // Glow
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle, sweepAngle * progress, false,
        Paint()
          ..color = color.withOpacity(0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = sw * 2.8
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
      // Main
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle, sweepAngle * progress, false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = sw
          ..strokeCap = StrokeCap.round,
      );
    }

    // Tick marks
    for (int i = 0; i <= 16; i++) {
      final angle = startAngle + (sweepAngle * i / 16);
      final isMain = i % 4 == 0;
      final len = isMain ? 10.0 : 5.0;
      final innerR = radius - sw - len;
      final outerR = radius - sw / 2;
      canvas.drawLine(
        Offset(center.dx + innerR * math.cos(angle), center.dy + innerR * math.sin(angle)),
        Offset(center.dx + outerR * math.cos(angle), center.dy + outerR * math.sin(angle)),
        Paint()
          ..color = isMain ? Colors.grey.shade600 : Colors.grey.shade800
          ..strokeWidth = isMain ? 2.0 : 1.0,
      );
    }

    // Needle tip dot
    if (progress > 0.001) {
      final needleAngle = startAngle + sweepAngle * progress;
      final dotR = radius;
      canvas.drawCircle(
        Offset(center.dx + dotR * math.cos(needleAngle), center.dy + dotR * math.sin(needleAngle)),
        5,
        Paint()..color = color..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }

    // Center hub
    canvas.drawCircle(center, 6,
        Paint()..color = Colors.grey.shade700..style = PaintingStyle.fill);
    canvas.drawCircle(center, 3,
        Paint()..color = Colors.white.withOpacity(0.4)..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.value != value || old.color != color;
}

class _SmallGaugePainter extends CustomPainter {
  final double progress;
  final Color color;

  _SmallGaugePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.41;
    const sw = 7.0;
    const startAngle = math.pi * 0.75;
    const sweepAngle = math.pi * 1.5;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle, sweepAngle, false,
      Paint()
        ..color = const Color(0xFF1A1A3A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw
        ..strokeCap = StrokeCap.round,
    );

    if (progress > 0.001) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle, sweepAngle * progress, false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = sw
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_SmallGaugePainter old) =>
      old.progress != progress || old.color != color;
}