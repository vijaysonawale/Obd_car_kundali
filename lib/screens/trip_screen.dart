// lib/screens/trip_screen.dart
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

class TripData {
  final double distanceKm;
  final Duration duration;
  final double avgSpeedKmh;
  final double maxSpeedKmh;
  final double fuelConsumedL;
  final double avgFuelL100km;
  final double currentFuelL100km;
  final double avgRpm;
  final double maxCoolantTemp;
  final DateTime tripStart;

  TripData({
    required this.distanceKm,
    required this.duration,
    required this.avgSpeedKmh,
    required this.maxSpeedKmh,
    required this.fuelConsumedL,
    required this.avgFuelL100km,
    required this.currentFuelL100km,
    required this.avgRpm,
    required this.maxCoolantTemp,
    required this.tripStart,
  });

  String get fuelEfficiencyRating {
    if (avgFuelL100km <= 0) return 'N/A';
    if (avgFuelL100km < 6) return '⭐⭐⭐ Excellent';
    if (avgFuelL100km < 10) return '⭐⭐ Good';
    if (avgFuelL100km < 14) return '⭐ Average';
    return '⚠ Poor';
  }

  String get summary => '''Car Kundali - Trip Summary
─────────────────────────
Distance   : ${distanceKm.toStringAsFixed(2)} km
Duration   : ${_formatDuration(duration)}
Avg Speed  : ${avgSpeedKmh.toStringAsFixed(1)} km/h
Max Speed  : ${maxSpeedKmh.toStringAsFixed(1)} km/h
Fuel Used  : ${fuelConsumedL.toStringAsFixed(2)} L
Fuel Economy: ${avgFuelL100km.toStringAsFixed(1)} L/100km
Avg RPM    : ${avgRpm.toStringAsFixed(0)} rpm
Max Coolant: ${maxCoolantTemp.toStringAsFixed(0)}°C
Trip Start : ${tripStart.day}/${tripStart.month}/${tripStart.year} ${tripStart.hour}:${tripStart.minute.toString().padLeft(2, '0')}
''';

  static String _formatDuration(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

class TripScreen extends StatelessWidget {
  final TripData tripData;

  const TripScreen({super.key, required this.tripData});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Trip Computer'),
        backgroundColor: Colors.blue.shade800,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: () => Share.share(tripData.summary),
            icon: const Icon(Icons.share),
            tooltip: 'Share Trip',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Live economy header
          _buildEconomyHero(context),
          const SizedBox(height: 16),
          _buildCard('📍 Distance & Time', [
            _buildRow('Distance Traveled', '${tripData.distanceKm.toStringAsFixed(2)} km', Icons.straighten, Colors.blue),
            _buildRow('Trip Duration', TripData._formatDuration(tripData.duration), Icons.timer, Colors.indigo),
            _buildRow('Average Speed', '${tripData.avgSpeedKmh.toStringAsFixed(1)} km/h', Icons.speed, Colors.teal),
            _buildRow('Maximum Speed', '${tripData.maxSpeedKmh.toStringAsFixed(1)} km/h', Icons.speed_outlined, Colors.red),
          ]),
          const SizedBox(height: 12),
          _buildCard('⛽ Fuel Economy', [
            _buildRow('Fuel Consumed', '${tripData.fuelConsumedL.toStringAsFixed(2)} L', Icons.local_gas_station, Colors.orange),
            _buildRow('Average Economy', '${tripData.avgFuelL100km.toStringAsFixed(1)} L/100km', Icons.eco, Colors.green),
            _buildRow('Current Economy', '${tripData.currentFuelL100km.toStringAsFixed(1)} L/100km', Icons.flash_on, Colors.blue),
            _buildRow('Efficiency Rating', tripData.fuelEfficiencyRating, Icons.star, Colors.amber),
          ]),
          const SizedBox(height: 12),
          _buildCard('🔧 Engine Stats', [
            _buildRow('Average RPM', '${tripData.avgRpm.toStringAsFixed(0)} rpm', Icons.settings_input_component, Colors.purple),
            _buildRow('Max Coolant Temp', '${tripData.maxCoolantTemp.toStringAsFixed(0)}°C', Icons.thermostat, tripData.maxCoolantTemp > 100 ? Colors.red : Colors.orange),
            _buildRow('Trip Started', '${tripData.tripStart.day}/${tripData.tripStart.month}/${tripData.tripStart.year} ${tripData.tripStart.hour}:${tripData.tripStart.minute.toString().padLeft(2, '0')}', Icons.calendar_today, Colors.grey),
          ]),
          const SizedBox(height: 16),
          // Fuel tip card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lightbulb_outline, color: Colors.green.shade700),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Fuel Saving Tip', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade700)),
                      const SizedBox(height: 4),
                      Text(
                        tripData.avgFuelL100km > 10
                            ? 'Try smooth acceleration and maintaining 80-100 km/h on highways to improve fuel economy.'
                            : 'Great fuel economy! Keep maintaining smooth driving habits.',
                        style: TextStyle(fontSize: 12, color: Colors.green.shade800),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEconomyHero(BuildContext context) {
    final economy = tripData.avgFuelL100km;
    final color = economy > 12 ? Colors.red : economy > 8 ? Colors.orange : Colors.green;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.shade700, color.shade500],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: color.withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _heroStat('${tripData.distanceKm.toStringAsFixed(1)}', 'km', 'Distance'),
          Container(width: 1, height: 60, color: Colors.white.withOpacity(0.3)),
          _heroStat(
              economy > 0 ? '${economy.toStringAsFixed(1)}' : '--',
              'L/100km',
              'Avg Economy'),
          Container(width: 1, height: 60, color: Colors.white.withOpacity(0.3)),
          _heroStat('${tripData.fuelConsumedL.toStringAsFixed(1)}', 'L used', 'Fuel'),
        ],
      ),
    );
  }

  Widget _heroStat(String value, String unit, String label) {
    return Column(
      children: [
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
        Text(unit, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12)),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 10, letterSpacing: 1)),
      ],
    );
  }

  Widget _buildCard(String title, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildRow(String label, String value, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

extension ColorExt on Color {
  Color get shade500 => withOpacity(0.85);
  Color get shade700 => withOpacity(1.0);
}