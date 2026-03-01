// lib/screens/live_data_screen.dart
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/obd_pid.dart';
import '../models/vehicle_data.dart';

class LiveDataScreen extends StatefulWidget {
  final Map<String, double> currentValues;
  final Map<String, List<VehicleData>> historyData;
  
  const LiveDataScreen({
    super.key,
    required this.currentValues,
    required this.historyData,
  });
  
  @override
  State<LiveDataScreen> createState() => _LiveDataScreenState();
}

class _LiveDataScreenState extends State<LiveDataScreen> {
  String? selectedPid;
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Data Monitor'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Graph Section
          if (selectedPid != null) ...[
            Container(
              height: 250,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        ObdPidDatabase.getPid(selectedPid!)?.name ?? selectedPid!,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => selectedPid = null),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(child: _buildGraph(selectedPid!)),
                ],
              ),
            ),
            const Divider(height: 1),
          ],
          
          // Parameters List
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: ObdPidDatabase.getCategories().map((category) {
                return _buildCategoryCard(category);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildCategoryCard(String category) {
    final pids = ObdPidDatabase.getPidsByCategory(category);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        title: Text(
          category,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        children: pids.map((pid) => _buildPidTile(pid)).toList(),
      ),
    );
  }
  
  Widget _buildPidTile(ObdPid pid) {
    final value = widget.currentValues[pid.command];
    final hasHistory = widget.historyData.containsKey(pid.command) && 
                       widget.historyData[pid.command]!.isNotEmpty;
    
    return ListTile(
      onTap: hasHistory ? () => setState(() => selectedPid = pid.command) : null,
      leading: Icon(
        hasHistory ? Icons.show_chart : Icons.remove_circle_outline,
        color: hasHistory ? Colors.blue : Colors.grey,
      ),
      title: Text(pid.shortName),
      subtitle: Text(
        pid.name,
        style: const TextStyle(fontSize: 11),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            value != null 
                ? '${value.toStringAsFixed(1)} ${pid.unit}'
                : '—',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: value != null ? Colors.black : Colors.grey,
            ),
          ),
          if (hasHistory)
            Text(
              'Tap for graph',
              style: TextStyle(
                fontSize: 10,
                color: Colors.blue.shade700,
              ),
            ),
        ],
      ),
    );
  }
  
  Widget _buildGraph(String pidCode) {
    final history = widget.historyData[pidCode];
    
    if (history == null || history.isEmpty) {
      return const Center(child: Text('No data available'));
    }
    
    // Get last 50 points
    final displayData = history.length > 50 
        ? history.sublist(history.length - 50) 
        : history;
    
    final spots = displayData.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), e.value.value);
    }).toList();
    
    // Calculate min/max for better scaling
    final values = spots.map((s) => s.y).toList();
    final minY = values.reduce((a, b) => a < b ? a : b);
    final maxY = values.reduce((a, b) => a > b ? a : b);
    final padding = (maxY - minY) * 0.1;
    
    return LineChart(
      LineChartData(
        minY: minY - padding,
        maxY: maxY + padding,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          horizontalInterval: (maxY - minY) / 5,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: Colors.grey.shade300,
              strokeWidth: 1,
            );
          },
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toStringAsFixed(0),
                  style: const TextStyle(fontSize: 10),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(color: Colors.grey.shade300),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: Colors.blue.shade700,
            barWidth: 3,
            dotData: FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: Colors.blue.withOpacity(0.1),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            tooltipBgColor: Colors.blueGrey,
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final pid = ObdPidDatabase.getPid(pidCode);
                return LineTooltipItem(
                  '${spot.y.toStringAsFixed(1)} ${pid?.unit ?? ''}',
                  const TextStyle(color: Colors.white),
                );
              }).toList();
            },
          ),
        ),
      ),
    );
  }
}