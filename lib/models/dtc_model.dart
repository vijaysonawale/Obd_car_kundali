// lib/models/dtc_model.dart
import 'vehicle_data.dart';

class DtcModel {
  final String code;
  final String description;
  final String status; // Confirmed, Pending, Permanent
  final DateTime? firstDetected;
  final FreezeFrameData? freezeFrame;
  final int occurrenceCount;
  
  DtcModel({
    required this.code,
    required this.description,
    required this.status,
    this.firstDetected,
    this.freezeFrame,
    this.occurrenceCount = 1,
  });
  
  // Get severity level
  String get severity {
    if (code.startsWith('P0')) return 'Generic Powertrain';
    if (code.startsWith('P1')) return 'Manufacturer Specific';
    if (code.startsWith('P2')) return 'Generic Powertrain';
    if (code.startsWith('P3')) return 'Manufacturer Specific';
    if (code.startsWith('C')) return 'Chassis';
    if (code.startsWith('B')) return 'Body';
    if (code.startsWith('U')) return 'Network';
    return 'Unknown';
  }
  
  // Get color based on status
  int get colorCode {
    switch (status) {
      case 'Confirmed':
        return 0xFFEF5350; // Red
      case 'Pending':
        return 0xFFFF9800; // Orange
      case 'Permanent':
        return 0xFFE53935; // Dark Red
      default:
        return 0xFF757575; // Grey
    }
  }
  
  Map<String, dynamic> toJson() => {
    'code': code,
    'description': description,
    'status': status,
    'firstDetected': firstDetected?.toIso8601String(),
    'freezeFrame': freezeFrame?.toJson(),
    'occurrenceCount': occurrenceCount,
  };
  
  factory DtcModel.fromJson(Map<String, dynamic> json) => DtcModel(
    code: json['code'],
    description: json['description'],
    status: json['status'],
    firstDetected: json['firstDetected'] != null 
        ? DateTime.parse(json['firstDetected']) 
        : null,
    occurrenceCount: json['occurrenceCount'] ?? 1,
  );
  
  DtcModel copyWith({
    String? code,
    String? description,
    String? status,
    DateTime? firstDetected,
    FreezeFrameData? freezeFrame,
    int? occurrenceCount,
  }) {
    return DtcModel(
      code: code ?? this.code,
      description: description ?? this.description,
      status: status ?? this.status,
      firstDetected: firstDetected ?? this.firstDetected,
      freezeFrame: freezeFrame ?? this.freezeFrame,
      occurrenceCount: occurrenceCount ?? this.occurrenceCount,
    );
  }
}

// Enhanced DTC Database with more codes
class EnhancedDtcDatabase {
  static final Map<String, DtcInfo> dtcDescriptions = {
    // Fuel and Air Metering
    'P0100': DtcInfo('Mass Air Flow Circuit', 'Check MAF sensor wiring', 'Medium'),
    'P0101': DtcInfo('MAF Range/Performance', 'Clean or replace MAF sensor', 'Medium'),
    'P0102': DtcInfo('MAF Circuit Low', 'Check MAF sensor and wiring', 'Medium'),
    'P0103': DtcInfo('MAF Circuit High', 'Check MAF sensor and wiring', 'Medium'),
    'P0171': DtcInfo('System Too Lean (Bank 1)', 'Check for vacuum leaks, fuel pressure', 'High'),
    'P0172': DtcInfo('System Too Rich (Bank 1)', 'Check O2 sensors, fuel injectors', 'High'),
    'P0174': DtcInfo('System Too Lean (Bank 2)', 'Check for vacuum leaks', 'High'),
    'P0175': DtcInfo('System Too Rich (Bank 2)', 'Check fuel system', 'High'),
    
    // Ignition System
    'P0300': DtcInfo('Random/Multiple Misfire', 'Check spark plugs, ignition coils', 'High'),
    'P0301': DtcInfo('Cylinder 1 Misfire', 'Check spark plug, coil, injector', 'High'),
    'P0302': DtcInfo('Cylinder 2 Misfire', 'Check spark plug, coil, injector', 'High'),
    'P0303': DtcInfo('Cylinder 3 Misfire', 'Check spark plug, coil, injector', 'High'),
    'P0304': DtcInfo('Cylinder 4 Misfire', 'Check spark plug, coil, injector', 'High'),
    'P0305': DtcInfo('Cylinder 5 Misfire', 'Check spark plug, coil, injector', 'High'),
    'P0306': DtcInfo('Cylinder 6 Misfire', 'Check spark plug, coil, injector', 'High'),
    'P0307': DtcInfo('Cylinder 7 Misfire', 'Check spark plug, coil, injector', 'High'),
    'P0308': DtcInfo('Cylinder 8 Misfire', 'Check spark plug, coil, injector', 'High'),
    
    // Emissions
    'P0420': DtcInfo('Catalyst Efficiency Low (Bank 1)', 'May need new catalytic converter', 'High'),
    'P0430': DtcInfo('Catalyst Efficiency Low (Bank 2)', 'May need new catalytic converter', 'High'),
    'P0440': DtcInfo('EVAP System Malfunction', 'Check gas cap, EVAP system', 'Medium'),
    'P0441': DtcInfo('EVAP Purge Flow', 'Check purge valve', 'Medium'),
    'P0442': DtcInfo('EVAP Leak (Small)', 'Check for small leaks in EVAP system', 'Low'),
    'P0443': DtcInfo('EVAP Purge Valve Circuit', 'Check purge valve wiring', 'Medium'),
    'P0455': DtcInfo('EVAP Leak (Large)', 'Check gas cap, EVAP hoses', 'Medium'),
    'P0456': DtcInfo('EVAP Leak (Very Small)', 'Check for tiny leaks', 'Low'),
    
    // Oxygen Sensors
    'P0130': DtcInfo('O2 Sensor Circuit (Bank 1 Sensor 1)', 'Replace O2 sensor', 'Medium'),
    'P0131': DtcInfo('O2 Sensor Low (Bank 1 Sensor 1)', 'Replace O2 sensor', 'Medium'),
    'P0132': DtcInfo('O2 Sensor High (Bank 1 Sensor 1)', 'Replace O2 sensor', 'Medium'),
    'P0133': DtcInfo('O2 Sensor Slow Response (Bank 1 Sensor 1)', 'Replace O2 sensor', 'Medium'),
    'P0134': DtcInfo('O2 Sensor No Activity (Bank 1 Sensor 1)', 'Replace O2 sensor', 'Medium'),
    
    // EGR System
    'P0401': DtcInfo('EGR Flow Insufficient', 'Clean or replace EGR valve', 'Medium'),
    'P0402': DtcInfo('EGR Flow Excessive', 'Check EGR valve', 'Medium'),
    'P0403': DtcInfo('EGR Control Circuit', 'Check EGR valve wiring', 'Medium'),
    
    // Transmission
    'P0700': DtcInfo('Transmission Control System', 'Scan transmission for codes', 'High'),
    'P0715': DtcInfo('Input/Turbine Speed Sensor', 'Check transmission sensor', 'High'),
    'P0720': DtcInfo('Output Speed Sensor Circuit', 'Check transmission sensor', 'High'),
    'P0730': DtcInfo('Incorrect Gear Ratio', 'Transmission problem', 'High'),
    
    // Throttle/Pedal
    'P0120': DtcInfo('Throttle Position Sensor Circuit', 'Clean or replace TPS', 'Medium'),
    'P0121': DtcInfo('TPS Range/Performance', 'Check TPS', 'Medium'),
    'P0122': DtcInfo('TPS Circuit Low', 'Check TPS wiring', 'Medium'),
    'P0123': DtcInfo('TPS Circuit High', 'Check TPS wiring', 'Medium'),
    
    // Sensors
    'P0110': DtcInfo('Intake Air Temp Sensor Circuit', 'Check IAT sensor', 'Low'),
    'P0115': DtcInfo('Coolant Temp Sensor Circuit', 'Check coolant sensor', 'Medium'),
    'P0125': DtcInfo('Insufficient Coolant Temp', 'Check thermostat', 'Low'),
    'P0335': DtcInfo('Crankshaft Position Sensor', 'Replace crank sensor', 'High'),
    'P0340': DtcInfo('Camshaft Position Sensor', 'Replace cam sensor', 'High'),
    'P0500': DtcInfo('Vehicle Speed Sensor', 'Check VSS', 'Medium'),
    'P0505': DtcInfo('Idle Air Control', 'Clean IAC valve', 'Medium'),
    'P0506': DtcInfo('Idle RPM Lower Than Expected', 'Check IAC valve', 'Low'),
    'P0507': DtcInfo('Idle RPM Higher Than Expected', 'Check for vacuum leaks', 'Low'),
    
    // Additional Common Codes
    'P0606': DtcInfo('ECM/PCM Processor', 'ECU may need replacement', 'High'),
    'P0607': DtcInfo('ECM/PCM Performance', 'ECU issue', 'High'),
    'P0850': DtcInfo('Park/Neutral Switch', 'Check park/neutral switch', 'Medium'),
    'P1000': DtcInfo('OBD System Readiness', 'Drive cycle not complete', 'Low'),
  };
  
  static DtcInfo getDtcInfo(String code) {
    return dtcDescriptions[code] ?? DtcInfo(
      'Unknown DTC Code',
      'Consult service manual for details',
      'Unknown',
    );
  }
}

class DtcInfo {
  final String description;
  final String recommendation;
  final String priority;
  
  DtcInfo(this.description, this.recommendation, this.priority);
}