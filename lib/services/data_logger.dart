// lib/services/data_logger.dart
import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import '../models/vehicle_data.dart';

class DataLogger {
  final List<VehicleData> _sessionData = [];
  DateTime? _sessionStart;
  
  void startSession() {
    _sessionStart = DateTime.now();
    _sessionData.clear();
  }
  
  void logData(VehicleData data) {
    _sessionData.add(data);
  }
  
  Future<File> exportToCSV() async {
    final dir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final file = File('${dir.path}/obd_data_$timestamp.csv');
    
    final buffer = StringBuffer();
    buffer.writeln('Timestamp,PID,Value,Unit');
    
    for (var data in _sessionData) {
      buffer.writeln('${data.timestamp.toIso8601String()},${data.pidCode},${data.value},${data.unit}');
    }
    
    await file.writeAsString(buffer.toString());
    return file;
  }
  
  Future<File> exportToJSON() async {
    final dir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final file = File('${dir.path}/obd_data_$timestamp.json');
    
    final jsonData = {
      'sessionStart': _sessionStart?.toIso8601String(),
      'sessionEnd': DateTime.now().toIso8601String(),
      'dataPoints': _sessionData.length,
      'data': _sessionData.map((d) => d.toJson()).toList(),
    };
    
    await file.writeAsString(jsonEncode(jsonData));
    return file;
  }
  
  Map<String, dynamic> getStatistics(String pidCode) {
    final filtered = _sessionData.where((d) => d.pidCode == pidCode).toList();
    
    if (filtered.isEmpty) {
      return {
        'min': 0.0,
        'max': 0.0,
        'avg': 0.0,
        'count': 0,
      };
    }
    
    final values = filtered.map((d) => d.value).toList();
    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);
    final avg = values.reduce((a, b) => a + b) / values.length;
    
    return {
      'min': min,
      'max': max,
      'avg': avg,
      'count': values.length,
    };
  }
  
  void clearSession() {
    _sessionData.clear();
    _sessionStart = null;
  }
  
  int get dataPointCount => _sessionData.length;
  Duration? get sessionDuration => _sessionStart != null 
      ? DateTime.now().difference(_sessionStart!) 
      : null;
}