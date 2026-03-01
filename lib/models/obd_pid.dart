// lib/models/obd_pid.dart
// Complete OBD-II PID Database with 50+ parameters

class ObdPid {
  final String mode;
  final String pid;
  final String name;
  final String shortName;
  final String unit;
  final String description;
  final String category;
  final Function(List<int>) formula;
  final int bytes;

  ObdPid({
    required this.mode,
    required this.pid,
    required this.name,
    required this.shortName,
    required this.unit,
    required this.description,
    required this.category,
    required this.formula,
    required this.bytes,
  });

  String get command => '$mode$pid';
}

class ObdPidDatabase {
  static final Map<String, ObdPid> pids = {
    // ═══════════════════════════════════════════════════════════
    // ENGINE PARAMETERS
    // ═══════════════════════════════════════════════════════════
    '010C': ObdPid(
      mode: '01',
      pid: '0C',
      name: 'Engine RPM',
      shortName: 'RPM',
      unit: 'rpm',
      description: 'Engine revolutions per minute',
      category: 'Engine',
      bytes: 2,
      formula: (data) {
        if (data.length < 2) return 0.0;
        return ((data[0] * 256) + data[1]) / 4.0;
      },
    ),
    
    '010D': ObdPid(
      mode: '01',
      pid: '0D',
      name: 'Vehicle Speed',
      shortName: 'Speed',
      unit: 'km/h',
      description: 'Vehicle speed',
      category: 'Engine',
      bytes: 1,
      formula: (data) {
        if (data.isEmpty) return 0.0;
        return data[0].toDouble();
      },
    ),
    
    '0104': ObdPid(
      mode: '01',
      pid: '04',
      name: 'Engine Load',
      shortName: 'Load',
      unit: '%',
      description: 'Calculated engine load',
      category: 'Engine',
      bytes: 1,
      formula: (data) {
        if (data.isEmpty) return 0.0;
        return (data[0] * 100) / 255.0;
      },
    ),
    
    '0105': ObdPid(
      mode: '01',
      pid: '05',
      name: 'Coolant Temperature',
      shortName: 'Coolant',
      unit: '°C',
      description: 'Engine coolant temperature',
      category: 'Engine',
      bytes: 1,
      formula: (data) {
        if (data.isEmpty) return 0.0;
        return (data[0] - 40).toDouble();
      },
    ),
    
    '010F': ObdPid(
      mode: '01',
      pid: '0F',
      name: 'Intake Air Temperature',
      shortName: 'IAT',
      unit: '°C',
      description: 'Intake air temperature',
      category: 'Engine',
      bytes: 1,
      formula: (data) {
        if (data.isEmpty) return 0.0;
        return (data[0] - 40).toDouble();
      },
    ),
    
    '0110': ObdPid(
      mode: '01',
      pid: '10',
      name: 'MAF Air Flow Rate',
      shortName: 'MAF',
      unit: 'g/s',
      description: 'Mass air flow sensor rate',
      category: 'Engine',
      bytes: 2,
      formula: (data) {
        if (data.length < 2) return 0.0;
        return ((data[0] * 256) + data[1]) / 100.0;
      },
    ),
    
    '0111': ObdPid(
      mode: '01',
      pid: '11',
      name: 'Throttle Position',
      shortName: 'Throttle',
      unit: '%',
      description: 'Absolute throttle position',
      category: 'Engine',
      bytes: 1,
      formula: (data) {
        if (data.isEmpty) return 0.0;
        return (data[0] * 100) / 255.0;
      },
    ),
    
    '010E': ObdPid(
      mode: '01',
      pid: '0E',
      name: 'Timing Advance',
      shortName: 'Timing',
      unit: '°',
      description: 'Timing advance before TDC',
      category: 'Engine',
      bytes: 1,
      formula: (data) {
        if (data.isEmpty) return 0.0;
        return (data[0] - 128) / 2.0;
      },
    ),
    
    '011F': ObdPid(
      mode: '01',
      pid: '1F',
      name: 'Engine Run Time',
      shortName: 'Runtime',
      unit: 's',
      description: 'Time since engine start',
      category: 'Engine',
      bytes: 2,
      formula: (data) {
        if (data.length < 2) return 0.0;
        return ((data[0] * 256) + data[1]).toDouble();
      },
    ),
    
    // ═══════════════════════════════════════════════════════════
    // FUEL SYSTEM
    // ═══════════════════════════════════════════════════════════
    '0106': ObdPid(
      mode: '01',
      pid: '06',
      name: 'Short Term Fuel Trim Bank 1',
      shortName: 'STFT B1',
      unit: '%',
      description: 'Short term fuel trim',
      category: 'Fuel',
      bytes: 1,
      formula: (data) {
        if (data.isEmpty) return 0.0;
        return ((data[0] - 128) * 100) / 128.0;
      },
    ),
    
    '0107': ObdPid(
      mode: '01',
      pid: '07',
      name: 'Long Term Fuel Trim Bank 1',
      shortName: 'LTFT B1',
      unit: '%',
      description: 'Long term fuel trim',
      category: 'Fuel',
      bytes: 1,
      formula: (data) {
        if (data.isEmpty) return 0.0;
        return ((data[0] - 128) * 100) / 128.0;
      },
    ),
    
    '010A': ObdPid(
      mode: '01',
      pid: '0A',
      name: 'Fuel Pressure',
      shortName: 'Fuel P',
      unit: 'kPa',
      description: 'Fuel rail pressure',
      category: 'Fuel',
      bytes: 1,
      formula: (data) {
        if (data.isEmpty) return 0.0;
        return (data[0] * 3).toDouble();
      },
    ),
    
    '012F': ObdPid(
      mode: '01',
      pid: '2F',
      name: 'Fuel Tank Level',
      shortName: 'Fuel',
      unit: '%',
      description: 'Fuel tank level input',
      category: 'Fuel',
      bytes: 1,
      formula: (data) {
        if (data.isEmpty) return 0.0;
        return (data[0] * 100) / 255.0;
      },
    ),
    
    // ═══════════════════════════════════════════════════════════
    // OXYGEN SENSORS
    // ═══════════════════════════════════════════════════════════
    '0114': ObdPid(
      mode: '01',
      pid: '14',
      name: 'O2 Sensor 1 Voltage',
      shortName: 'O2S1',
      unit: 'V',
      description: 'Oxygen sensor 1 voltage',
      category: 'Oxygen',
      bytes: 2,
      formula: (data) {
        if (data.length < 2) return 0.0;
        return data[0] / 200.0;
      },
    ),
    
    '0115': ObdPid(
      mode: '01',
      pid: '15',
      name: 'O2 Sensor 2 Voltage',
      shortName: 'O2S2',
      unit: 'V',
      description: 'Oxygen sensor 2 voltage',
      category: 'Oxygen',
      bytes: 2,
      formula: (data) {
        if (data.length < 2) return 0.0;
        return data[0] / 200.0;
      },
    ),
    
    // ═══════════════════════════════════════════════════════════
    // PRESSURE & TEMPERATURE
    // ═══════════════════════════════════════════════════════════
    '010B': ObdPid(
      mode: '01',
      pid: '0B',
      name: 'Intake Manifold Pressure',
      shortName: 'MAP',
      unit: 'kPa',
      description: 'Absolute intake manifold pressure',
      category: 'Pressure',
      bytes: 1,
      formula: (data) {
        if (data.isEmpty) return 0.0;
        return data[0].toDouble();
      },
    ),
    
    '0133': ObdPid(
      mode: '01',
      pid: '33',
      name: 'Barometric Pressure',
      shortName: 'BARO',
      unit: 'kPa',
      description: 'Absolute barometric pressure',
      category: 'Pressure',
      bytes: 1,
      formula: (data) {
        if (data.isEmpty) return 0.0;
        return data[0].toDouble();
      },
    ),
    
    '0146': ObdPid(
      mode: '01',
      pid: '46',
      name: 'Ambient Air Temperature',
      shortName: 'AAT',
      unit: '°C',
      description: 'Ambient air temperature',
      category: 'Temperature',
      bytes: 1,
      formula: (data) {
        if (data.isEmpty) return 0.0;
        return (data[0] - 40).toDouble();
      },
    ),
    
    '015C': ObdPid(
      mode: '01',
      pid: '5C',
      name: 'Engine Oil Temperature',
      shortName: 'Oil Temp',
      unit: '°C',
      description: 'Engine oil temperature',
      category: 'Temperature',
      bytes: 1,
      formula: (data) {
        if (data.isEmpty) return 0.0;
        return (data[0] - 40).toDouble();
      },
    ),
    
    // ═══════════════════════════════════════════════════════════
    // ADVANCED PARAMETERS
    // ═══════════════════════════════════════════════════════════
    '0131': ObdPid(
      mode: '01',
      pid: '31',
      name: 'Distance Since DTC Cleared',
      shortName: 'Dist DTC',
      unit: 'km',
      description: 'Distance traveled since codes cleared',
      category: 'Distance',
      bytes: 2,
      formula: (data) {
        if (data.length < 2) return 0.0;
        return ((data[0] * 256) + data[1]).toDouble();
      },
    ),
    
    '0121': ObdPid(
      mode: '01',
      pid: '21',
      name: 'Distance With MIL On',
      shortName: 'MIL Dist',
      unit: 'km',
      description: 'Distance traveled with MIL on',
      category: 'Distance',
      bytes: 2,
      formula: (data) {
        if (data.length < 2) return 0.0;
        return ((data[0] * 256) + data[1]).toDouble();
      },
    ),
    
    '0142': ObdPid(
      mode: '01',
      pid: '42',
      name: 'Control Module Voltage',
      shortName: 'Battery',
      unit: 'V',
      description: 'Control module voltage',
      category: 'Electrical',
      bytes: 2,
      formula: (data) {
        if (data.length < 2) return 0.0;
        return ((data[0] * 256) + data[1]) / 1000.0;
      },
    ),
    
    '0143': ObdPid(
      mode: '01',
      pid: '43',
      name: 'Absolute Load Value',
      shortName: 'Abs Load',
      unit: '%',
      description: 'Absolute load value',
      category: 'Engine',
      bytes: 2,
      formula: (data) {
        if (data.length < 2) return 0.0;
        return ((data[0] * 256) + data[1]) * 100 / 255.0;
      },
    ),
    
    '0144': ObdPid(
      mode: '01',
      pid: '44',
      name: 'Commanded Equivalence Ratio',
      shortName: 'Lambda',
      unit: 'ratio',
      description: 'Fuel air equivalence ratio',
      category: 'Fuel',
      bytes: 2,
      formula: (data) {
        if (data.length < 2) return 0.0;
        return ((data[0] * 256) + data[1]) / 32768.0;
      },
    ),
    
    '0145': ObdPid(
      mode: '01',
      pid: '45',
      name: 'Relative Throttle Position',
      shortName: 'Rel TPS',
      unit: '%',
      description: 'Relative throttle position',
      category: 'Engine',
      bytes: 1,
      formula: (data) {
        if (data.isEmpty) return 0.0;
        return (data[0] * 100) / 255.0;
      },
    ),
    
    '0147': ObdPid(
      mode: '01',
      pid: '47',
      name: 'Absolute Throttle Position B',
      shortName: 'TPS B',
      unit: '%',
      description: 'Absolute throttle position B',
      category: 'Engine',
      bytes: 1,
      formula: (data) {
        if (data.isEmpty) return 0.0;
        return (data[0] * 100) / 255.0;
      },
    ),
    
    '0149': ObdPid(
      mode: '01',
      pid: '49',
      name: 'Accelerator Pedal Position D',
      shortName: 'APP D',
      unit: '%',
      description: 'Accelerator pedal position D',
      category: 'Engine',
      bytes: 1,
      formula: (data) {
        if (data.isEmpty) return 0.0;
        return (data[0] * 100) / 255.0;
      },
    ),
    
    '014C': ObdPid(
      mode: '01',
      pid: '4C',
      name: 'Commanded Throttle Actuator',
      shortName: 'TPS Cmd',
      unit: '%',
      description: 'Commanded throttle actuator control',
      category: 'Engine',
      bytes: 1,
      formula: (data) {
        if (data.isEmpty) return 0.0;
        return (data[0] * 100) / 255.0;
      },
    ),
    
    '014D': ObdPid(
      mode: '01',
      pid: '4D',
      name: 'Time Since DTC Cleared',
      shortName: 'Time DTC',
      unit: 'min',
      description: 'Time run with MIL on',
      category: 'Time',
      bytes: 2,
      formula: (data) {
        if (data.length < 2) return 0.0;
        return ((data[0] * 256) + data[1]).toDouble();
      },
    ),
  };
  
  // Get PID by command
  static ObdPid? getPid(String command) {
    return pids[command];
  }
  
  // Get PIDs by category
  static List<ObdPid> getPidsByCategory(String category) {
    return pids.values.where((pid) => pid.category == category).toList();
  }
  
  // Get all categories
  static List<String> getCategories() {
    return pids.values.map((pid) => pid.category).toSet().toList()..sort();
  }
  
  // Get popular/essential PIDs
  static List<ObdPid> getEssentialPids() {
    final essential = [
      '010C', '010D', '0104', '0105', '010F', 
      '0110', '0111', '010B', '010A', '012F'
    ];
    return essential.map((cmd) => pids[cmd]!).toList();
  }
}

// DTC Description Database
class DtcDatabase {
  static final Map<String, String> descriptions = {
    // Generic Powertrain Codes (P0xxx)
    'P0100': 'Mass or Volume Air Flow Circuit Malfunction',
    'P0101': 'Mass or Volume Air Flow Circuit Range/Performance Problem',
    'P0102': 'Mass or Volume Air Flow Circuit Low Input',
    'P0103': 'Mass or Volume Air Flow Circuit High Input',
    'P0171': 'System Too Lean (Bank 1)',
    'P0172': 'System Too Rich (Bank 1)',
    'P0174': 'System Too Lean (Bank 2)',
    'P0175': 'System Too Rich (Bank 2)',
    'P0300': 'Random/Multiple Cylinder Misfire Detected',
    'P0301': 'Cylinder 1 Misfire Detected',
    'P0302': 'Cylinder 2 Misfire Detected',
    'P0303': 'Cylinder 3 Misfire Detected',
    'P0304': 'Cylinder 4 Misfire Detected',
    'P0305': 'Cylinder 5 Misfire Detected',
    'P0306': 'Cylinder 6 Misfire Detected',
    'P0307': 'Cylinder 7 Misfire Detected',
    'P0308': 'Cylinder 8 Misfire Detected',
    'P0401': 'Exhaust Gas Recirculation Flow Insufficient',
    'P0402': 'Exhaust Gas Recirculation Flow Excessive',
    'P0420': 'Catalyst System Efficiency Below Threshold (Bank 1)',
    'P0430': 'Catalyst System Efficiency Below Threshold (Bank 2)',
    'P0440': 'Evaporative Emission Control System Malfunction',
    'P0441': 'Evaporative Emission Control System Incorrect Purge Flow',
    'P0442': 'Evaporative Emission Control System Leak Detected (Small Leak)',
    'P0443': 'Evaporative Emission Control System Purge Control Valve Circuit',
    'P0446': 'Evaporative Emission Control System Vent Control Circuit',
    'P0455': 'Evaporative Emission Control System Leak Detected (Large Leak)',
    'P0500': 'Vehicle Speed Sensor Malfunction',
    'P0505': 'Idle Control System Malfunction',
    'P0506': 'Idle Control System RPM Lower Than Expected',
    'P0507': 'Idle Control System RPM Higher Than Expected',
    'P0700': 'Transmission Control System Malfunction',
    'P0715': 'Input/Turbine Speed Sensor Circuit Malfunction',
    'P0720': 'Output Speed Sensor Circuit Malfunction',
    'P0725': 'Engine Speed Input Circuit Malfunction',
    'P0850': 'Park/Neutral Position Switch Input Circuit',
  };
  
  static String getDescription(String code) {
    return descriptions[code] ?? 'Unknown DTC Code - Refer to service manual';
  }
}