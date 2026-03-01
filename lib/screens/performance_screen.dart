// lib/screens/performance_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';

enum _TestState { idle, waitingLaunch, running, done }

class PerformanceScreen extends StatefulWidget {
  final ValueNotifier<Map<String, double>> valuesNotifier;
  const PerformanceScreen({super.key, required this.valuesNotifier});

  @override
  State<PerformanceScreen> createState() => _PerformanceScreenState();
}

class _PerformanceScreenState extends State<PerformanceScreen>
    with SingleTickerProviderStateMixin {
  _TestState _state = _TestState.idle;
  DateTime? _startTime;
  double _t0to60mph = 0;   // 0-97 km/h
  double _t0to100 = 0;
  double _t0to80 = 0;
  double _peakSpeed = 0;
  double _peakRpm = 0;
  bool _done60 = false, _done80 = false, _done100 = false;

  StreamSubscription? _valueSub;
  Timer? _readyTimer;
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 600))
          ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _valueSub?.cancel();
    _readyTimer?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _startTest() {
    setState(() {
      _state = _TestState.waitingLaunch;
      _resetResults();
    });

    // Listen to value changes
    _valueSub?.cancel();
    _valueSub = Stream.periodic(const Duration(milliseconds: 100)).listen((_) {
      _onTick();
    });
  }

  void _resetResults() {
    _t0to60mph = 0; _t0to100 = 0; _t0to80 = 0;
    _peakSpeed = 0; _peakRpm = 0;
    _done60 = false; _done80 = false; _done100 = false;
    _startTime = null;
  }

  void _onTick() {
    final values = widget.valuesNotifier.value;
    final speed = values['010D'] ?? 0;
    final rpm = values['010C'] ?? 0;

    if (!mounted) return;

    if (_state == _TestState.waitingLaunch) {
      // Start when speed crosses 5 km/h from standstill
      if (speed > 3) {
        setState(() {
          _state = _TestState.running;
          _startTime = DateTime.now();
        });
      }
    }

    if (_state == _TestState.running) {
      if (speed > _peakSpeed) _peakSpeed = speed;
      if (rpm > _peakRpm) _peakRpm = rpm;

      final elapsed = _startTime != null
          ? DateTime.now().difference(_startTime!).inMilliseconds / 1000.0
          : 0.0;

      if (!_done60 && speed >= 60) {
        setState(() { _t0to60mph = elapsed; _done60 = true; });
      }
      if (!_done80 && speed >= 80) {
        setState(() { _t0to80 = elapsed; _done80 = true; });
      }
      if (!_done100 && speed >= 100) {
        setState(() {
          _t0to100 = elapsed;
          _done100 = true;
          _state = _TestState.done;
        });
        _valueSub?.cancel();
      }
    }
  }

  void _stopTest() {
    _valueSub?.cancel();
    setState(() => _state = _TestState.idle);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07071A),
      appBar: AppBar(
        title: const Text('PERFORMANCE TEST',
            style: TextStyle(letterSpacing: 3, fontSize: 12, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF07071A),
        foregroundColor: Colors.white,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ValueListenableBuilder<Map<String, double>>(
        valueListenable: widget.valuesNotifier,
        builder: (context, values, _) {
          final speed = values['010D'] ?? 0;
          final rpm = values['010C'] ?? 0;

          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                // Status / Timer
                _buildStatusRow(speed),
                const SizedBox(height: 16),
                // Speed display
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        speed.toStringAsFixed(0),
                        style: TextStyle(
                          color: _state == _TestState.running ? const Color(0xFF00FF9C) : Colors.white,
                          fontSize: 100,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                          shadows: _state == _TestState.running
                              ? [const Shadow(color: Color(0xFF00FF9C), blurRadius: 20)]
                              : [],
                        ),
                      ),
                      Text('km/h', style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
                      const SizedBox(height: 8),
                      Text('RPM: ${rpm.toStringAsFixed(0)}',
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                      const SizedBox(height: 40),

                      // Results / Milestones
                      if (_state == _TestState.done) _buildResults() else _buildMilestones(),

                      const SizedBox(height: 32),
                      // Action button
                      _buildActionButton(),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusRow(double speed) {
    String msg;
    Color color;

    switch (_state) {
      case _TestState.idle:
        msg = 'Ready to test'; color = Colors.grey;
        break;
      case _TestState.waitingLaunch:
        msg = '⚡ WAITING FOR LAUNCH — Accelerate now!'; color = Colors.orange;
        break;
      case _TestState.running:
        final elapsed = _startTime != null
            ? DateTime.now().difference(_startTime!).inMilliseconds / 1000.0
            : 0.0;
        msg = '🏁 RUNNING — ${elapsed.toStringAsFixed(1)}s'; color = const Color(0xFF00FF9C);
        break;
      case _TestState.done:
        msg = '✅ TEST COMPLETE'; color = const Color(0xFF00B4FF);
        break;
    }

    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (_, __) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(
              _state == _TestState.waitingLaunch ? 0.08 + 0.08 * _pulseCtrl.value : 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Text(msg,
            textAlign: TextAlign.center,
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
      ),
    );
  }

  Widget _buildMilestones() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F28),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        children: [
          const Text('MILESTONES', style: TextStyle(color: Colors.grey, fontSize: 10, letterSpacing: 2)),
          const SizedBox(height: 12),
          _milestoneRow('0 → 60 km/h', _done60 ? '${_t0to60mph.toStringAsFixed(2)}s' : '...', _done60),
          _milestoneRow('0 → 80 km/h', _done80 ? '${_t0to80.toStringAsFixed(2)}s' : '...', _done80),
          _milestoneRow('0 → 100 km/h', _done100 ? '${_t0to100.toStringAsFixed(2)}s' : '...', _done100),
        ],
      ),
    );
  }

  Widget _buildResults() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F28),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF00B4FF).withOpacity(0.3)),
        boxShadow: [BoxShadow(color: const Color(0xFF00B4FF).withOpacity(0.1), blurRadius: 20)],
      ),
      child: Column(
        children: [
          const Text('RESULTS', style: TextStyle(color: Color(0xFF00B4FF), fontSize: 12, letterSpacing: 3, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _resultRow('0 → 60 km/h', '${_t0to60mph.toStringAsFixed(2)}s', const Color(0xFF00FF9C)),
          const Divider(color: Colors.white12),
          _resultRow('0 → 80 km/h', '${_t0to80.toStringAsFixed(2)}s', Colors.orange),
          const Divider(color: Colors.white12),
          _resultRow('0 → 100 km/h', '${_t0to100.toStringAsFixed(2)}s', const Color(0xFF00B4FF)),
          const Divider(color: Colors.white12),
          _resultRow('Peak Speed', '${_peakSpeed.toStringAsFixed(0)} km/h', Colors.red),
          _resultRow('Peak RPM', '${_peakRpm.toStringAsFixed(0)} rpm', Colors.purple),
        ],
      ),
    );
  }

  Widget _milestoneRow(String label, String value, bool done) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: done ? const Color(0xFF00FF9C).withOpacity(0.15) : Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(value,
                style: TextStyle(
                  color: done ? const Color(0xFF00FF9C) : Colors.grey.shade700,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                )),
          ),
        ],
      ),
    );
  }

  Widget _resultRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
          Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 20, fontFamily: 'monospace')),
        ],
      ),
    );
  }

  Widget _buildActionButton() {
    if (_state == _TestState.idle || _state == _TestState.done) {
      return GestureDetector(
        onTap: _startTest,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF00B4FF), Color(0xFF0040FF)]),
            borderRadius: BorderRadius.circular(50),
            boxShadow: [BoxShadow(color: const Color(0xFF00B4FF).withOpacity(0.4), blurRadius: 24, offset: const Offset(0, 8))],
          ),
          child: Text(
            _state == _TestState.done ? '🔄  TEST AGAIN' : '🏁  START TEST',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 2),
          ),
        ),
      );
    }

    if (_state == _TestState.running || _state == _TestState.waitingLaunch) {
      return GestureDetector(
        onTap: _stopTest,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 18),
          decoration: BoxDecoration(
            color: Colors.red.shade900,
            borderRadius: BorderRadius.circular(50),
            border: Border.all(color: Colors.red.withOpacity(0.5)),
          ),
          child: const Text('⛔  CANCEL',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 2)),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}