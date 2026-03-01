// lib/models/vehicle_data.dart
class VehicleData {
  final String pidCode;
  final double value;
  final String unit;
  final DateTime timestamp;
  
  VehicleData({
    required this.pidCode,
    required this.value,
    required this.unit,
    required this.timestamp,
  });
  
  Map<String, dynamic> toJson() => {
    'pidCode': pidCode,
    'value': value,
    'unit': unit,
    'timestamp': timestamp.toIso8601String(),
  };
  
  factory VehicleData.fromJson(Map<String, dynamic> json) => VehicleData(
    pidCode: json['pidCode'],
    value: json['value'],
    unit: json['unit'],
    timestamp: DateTime.parse(json['timestamp']),
  );
}

class ReadinessMonitor {
  final String name;
  final bool isSupported;
  final bool isComplete;
  
  ReadinessMonitor({
    required this.name,
    required this.isSupported,
    required this.isComplete,
  });
}

class VehicleInfo {
  final String? vin;
  final String? ecuName;
  final String? protocol;
  final List<String> supportedPids;
  
  VehicleInfo({
    this.vin,
    this.ecuName,
    this.protocol,
    this.supportedPids = const [],
  });
}

class FreezeFrameData {
  final String dtcCode;
  final Map<String, double> parameters;
  final DateTime timestamp;
  
  FreezeFrameData({
    required this.dtcCode,
    required this.parameters,
    required this.timestamp,
  });
  
  Map<String, dynamic> toJson() => {
    'dtcCode': dtcCode,
    'parameters': parameters,
    'timestamp': timestamp.toIso8601String(),
  };
}

class DtcInfo {
  final String code;
  final String description;
  final String status; // Confirmed, Pending, Permanent
  final DateTime? firstDetected;
  final FreezeFrameData? freezeFrame;
  
  DtcInfo({
    required this.code,
    required this.description,
    required this.status,
    this.firstDetected,
    this.freezeFrame,
  });
  
  Map<String, dynamic> toJson() => {
    'code': code,
    'description': description,
    'status': status,
    'firstDetected': firstDetected?.toIso8601String(),
    'freezeFrame': freezeFrame?.toJson(),
  };
}