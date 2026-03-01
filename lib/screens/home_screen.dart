// lib/screens/home_screen.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/gatt_obd_service.dart';
import '../services/data_logger.dart';
import '../models/obd_pid.dart';
import '../models/vehicle_data.dart';
import '../models/dtc_model.dart';
import 'dashboard_screen.dart';
import 'health_screen.dart';
import 'trip_screen.dart';
import 'performance_screen.dart';
import 'freeze_frame_screen.dart';
import 'live_data_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final GattObdService _obd = GattObdService();
  final DataLogger _dataLogger = DataLogger();

  // BLE
  List<ScanResult> scanResults = [];
  BluetoothDevice? connected;
  StreamSubscription? _scanSub, _adapterSub, _obdDataSub;
  bool _isScanning = false, _isConnecting = false, _isLogging = false;

  // Live Data
  final Map<String, List<VehicleData>> _liveDataHistory = {};
  final Map<String, double> _currentValues = {};
  final ValueNotifier<Map<String, double>> _valuesNotifier =
      ValueNotifier({});

  // Readiness / DTC / Vehicle info
  List<ReadinessMonitor> _readinessMonitors = [];
  List<DtcModel> _dtcList = [];
  VehicleInfo? _vehicleInfo;

  // Logs
  String logText = '';
  final List<String> fullLogs = [];

  // UI
  late final TabController _tabs;
  Timer? _autoRefreshTimer;
  final TextEditingController _commandController = TextEditingController();
  String _commandResponse = '';

  // Monitored PIDs
  final List<String> _monitoredPids = [
    '010C', '010D', '0104', '0105', '010F', '0110',
    '0111', '010B', '0106', '0107', '010E', '012F',
    '0114', '0142',
  ];

  // ─── TRIP TRACKING ────────────────────────────────────
  DateTime? _tripStart;
  double _tripDistanceKm = 0;
  double _tripMaxSpeed = 0;
  double _tripSpeedSum = 0;
  int _tripSpeedSamples = 0;
  double _tripFuelL = 0;
  double _tripMaxCoolant = 0;
  double _tripRpmSum = 0;
  int _tripRpmSamples = 0;
  DateTime? _lastTripTime;
  double _currentFuelL100km = 0;

  // ─── ALERTS ───────────────────────────────────────────
  final Set<String> _alertsSent = {};

  // ─── LIFECYCLE ────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabs = TabController(length: 5, vsync: this);
    _initializeBluetooth();
    _logLocal('═══════════════════════════');
    _logLocal('CAR KUNDALI PRO — Started');
    _logLocal('═══════════════════════════');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scanSub?.cancel(); _adapterSub?.cancel(); _obdDataSub?.cancel();
    _autoRefreshTimer?.cancel();
    _tabs.dispose(); _commandController.dispose();
    _valuesNotifier.dispose();
    _obd.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkBluetoothState();
  }

  // ─── BLUETOOTH INIT ────────────────────────────────────
  Future<void> _initializeBluetooth() async {
    await _checkBluetoothState();
    _adapterSub = FlutterBluePlus.adapterState.listen((s) {
      appendLog('📶 Bluetooth: ${s.name}');
    });
  }

  Future<void> _checkBluetoothState() async {
    try {
      if (!await FlutterBluePlus.isSupported) { appendLog('❌ BT not supported'); return; }
      final state = await FlutterBluePlus.adapterState.first;
      if (state != BluetoothAdapterState.on) {
        appendLog('⚠️ Bluetooth OFF');
        if (Platform.isAndroid) { try { await FlutterBluePlus.turnOn(); } catch (_) {} }
      } else { appendLog('✅ Bluetooth ON'); }
    } catch (e) { appendLog('BT error: $e'); }
  }

  Future<bool> _requestPermissions() async {
    try {
      if (Platform.isAndroid) {
        final s = await Permission.bluetoothScan.request();
        final c = await Permission.bluetoothConnect.request();
        final l = await Permission.location.request();
        return s.isGranted && c.isGranted && l.isGranted;
      }
      return true;
    } catch (_) { return false; }
  }

  // ─── SCAN & CONNECT ────────────────────────────────────
  Future<void> startScan() async {
    if (_isScanning) return;
    if (!await _requestPermissions()) return;
    setState(() { scanResults.clear(); _isScanning = true; });
    appendLog('🔍 Scanning...');

    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      final ids = scanResults.map((e) => e.device.remoteId.str).toSet();
      for (final r in results) {
        if (!ids.contains(r.device.remoteId.str)) setState(() => scanResults.add(r));
      }
    });

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 12), androidUsesFineLocation: true, androidScanMode: AndroidScanMode.lowLatency);
    await Future.delayed(const Duration(seconds: 12));
    try { await FlutterBluePlus.stopScan(); } catch (_) {}
    setState(() => _isScanning = false);
    appendLog('✅ Found ${scanResults.length} devices');
  }

  String _getDeviceName(ScanResult r) {
    if (r.advertisementData.advName.isNotEmpty) return r.advertisementData.advName;
    if (r.device.platformName.isNotEmpty) return r.device.platformName;
    return 'Unknown Device';
  }

  Future<void> connectDevice(BluetoothDevice device) async {
    if (_isConnecting) return;
    setState(() => _isConnecting = true);
    final name = _getDeviceName(scanResults.firstWhere((r) => r.device.remoteId == device.remoteId));
    appendLog('🔗 Connecting to $name...');
    try {
      await device.connect(timeout: const Duration(seconds: 15));
      appendLog('✅ BT connected');
      final ok = await _obd.connect(device);
      if (!ok) { appendLog('❌ OBD failed'); await device.disconnect(); setState(() => _isConnecting = false); return; }
      appendLog('✅ OBD connected');
      await _initELM327();
      _obdDataSub?.cancel();
      _obdDataSub = _obd.dataStream.listen((d) { if (d.trim().isNotEmpty) _processObdResponse(d); });
      setState(() => connected = device);
      appendLog('✅ Ready!');
      _startAutoRefresh();
      _getVehicleInfo().catchError((_) {});
      _getReadinessMonitors().catchError((_) {});
    } catch (e) {
      appendLog('❌ Error: $e');
      try { await device.disconnect(); } catch (_) {}
    } finally {
      setState(() => _isConnecting = false);
    }
  }

  Future<void> _initELM327() async {
    appendLog('Initializing ELM327...');
    for (final cmd in ['ATZ', 'ATE0', 'ATL0', 'ATH0', 'ATSP0']) {
      try {
        await _obd.sendCommand(cmd);
        await Future.delayed(Duration(milliseconds: cmd == 'ATZ' ? 1500 : 300));
        await _obd.readResponse(timeout: Duration(seconds: cmd == 'ATZ' ? 3 : 1));
      } catch (_) {}
    }
    appendLog('✅ ELM327 ready');
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (connected != null && mounted) _refreshMonitoredPids();
    });
    // Start trip when logging begins — but also track silently
    _tripStart = DateTime.now();
    _lastTripTime = DateTime.now();
  }

  Future<void> _refreshMonitoredPids() async {
    if (_isConnecting) return;
    for (final pid in _monitoredPids) {
      try {
        await _obd.sendCommand(pid);
        await Future.delayed(const Duration(milliseconds: 80));
      } catch (_) {}
    }
  }

  // ─── DATA PROCESSING ──────────────────────────────────
  void _processObdResponse(String raw) {
    final cleaned = _cleanHex(raw);
    for (final entry in ObdPidDatabase.pids.entries) {
      final pid = entry.value;
      if (cleaned.contains('41 ${pid.pid}')) {
        final parts = cleaned.split(' ');
        final idx = parts.indexOf('41');
        if (idx >= 0 && parts.length >= idx + 2 + pid.bytes) {
          try {
            final bytes = List.generate(pid.bytes, (i) => int.parse(parts[idx + 2 + i], radix: 16));
            final value = pid.formula(bytes) as double;
            final vd = VehicleData(pidCode: entry.key, value: value, unit: pid.unit, timestamp: DateTime.now());
            setState(() {
              _currentValues[entry.key] = value;
              _liveDataHistory.putIfAbsent(entry.key, () => []).add(vd);
              if (_liveDataHistory[entry.key]!.length > 120) _liveDataHistory[entry.key]!.removeAt(0);
            });
            // Update notifier for real-time screens
            _valuesNotifier.value = Map.from(_currentValues);
            if (_isLogging) _dataLogger.logData(vd);
          } catch (_) {}
        }
      }
    }
    _updateTripData();
    _checkAlerts();
  }

  // ─── TRIP TRACKING ────────────────────────────────────
  void _updateTripData() {
    final now = DateTime.now();
    if (_lastTripTime == null) { _lastTripTime = now; return; }
    final dt = now.difference(_lastTripTime!).inMilliseconds / 1000.0;
    _lastTripTime = now;

    final speed = _currentValues['010D'] ?? 0;
    final maf = _currentValues['0110'] ?? 0;
    final rpm = _currentValues['010C'] ?? 0;
    final coolant = _currentValues['0105'] ?? 0;

    // Distance (km)
    _tripDistanceKm += (speed / 3600.0) * dt;
    if (speed > _tripMaxSpeed) _tripMaxSpeed = speed;
    _tripSpeedSum += speed; _tripSpeedSamples++;

    // Fuel from MAF: L = MAF(g/s) / (AFR * density) * dt
    // Gasoline: AFR=14.7, density=720 g/L
    final fuelRate = maf / (14.7 * 720.0); // L/s
    _tripFuelL += fuelRate * dt;

    // Current instant fuel economy L/100km
    if (speed > 5) {
      _currentFuelL100km = fuelRate / (speed / 3600000.0); // L/100km
    }

    // Engine stats
    _tripRpmSum += rpm; _tripRpmSamples++;
    if (coolant > _tripMaxCoolant) _tripMaxCoolant = coolant;
  }

  TripData get _tripData => TripData(
    distanceKm: _tripDistanceKm,
    duration: _tripStart != null ? DateTime.now().difference(_tripStart!) : Duration.zero,
    avgSpeedKmh: _tripSpeedSamples > 0 ? _tripSpeedSum / _tripSpeedSamples : 0,
    maxSpeedKmh: _tripMaxSpeed,
    fuelConsumedL: _tripFuelL,
    avgFuelL100km: _tripDistanceKm > 0.1 ? (_tripFuelL / _tripDistanceKm) * 100 : 0,
    currentFuelL100km: _currentFuelL100km,
    avgRpm: _tripRpmSamples > 0 ? _tripRpmSum / _tripRpmSamples : 0,
    maxCoolantTemp: _tripMaxCoolant,
    tripStart: _tripStart ?? DateTime.now(),
  );

  void _resetTrip() {
    setState(() {
      _tripDistanceKm = 0; _tripMaxSpeed = 0;
      _tripSpeedSum = 0; _tripSpeedSamples = 0;
      _tripFuelL = 0; _tripMaxCoolant = 0;
      _tripRpmSum = 0; _tripRpmSamples = 0;
      _tripStart = DateTime.now(); _lastTripTime = DateTime.now();
      _currentFuelL100km = 0;
    });
    appendLog('🔄 Trip data reset');
  }

  // ─── ALERT SYSTEM ─────────────────────────────────────
  void _checkAlerts() {
    final coolant = _currentValues['0105'] ?? 0;
    final rpm = _currentValues['010C'] ?? 0;
    final stft = (_currentValues['0106'] ?? 0).abs();

    if (coolant > 108) _showAlert('🌡 High Coolant Temperature!', '${coolant.toStringAsFixed(0)}°C — Stop engine safely!', Colors.red, 'coolant_high');
    if (rpm > 6500) _showAlert('⚡ High RPM Warning', '${rpm.toStringAsFixed(0)} rpm — Ease off throttle', Colors.orange, 'rpm_high');
    if (stft > 20) _showAlert('⛽ Fuel Trim Alert', 'STFT ${stft.toStringAsFixed(1)}% — Possible vacuum leak', Colors.orange, 'stft_high');
  }

  void _showAlert(String title, String msg, Color color, String key) {
    if (_alertsSent.contains(key) || !mounted) return;
    _alertsSent.add(key);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          Text(msg, style: const TextStyle(fontSize: 12, color: Colors.white70)),
        ]),
        backgroundColor: color,
        duration: const Duration(seconds: 6),
        action: SnackBarAction(label: 'OK', textColor: Colors.white, onPressed: () {}),
      ),
    );
    Future.delayed(const Duration(minutes: 3), () => _alertsSent.remove(key));
  }

  // ─── VEHICLE INFO ──────────────────────────────────────
  Future<void> _getVehicleInfo() async {
    try {
      await _obd.sendCommand('0902');
      await Future.delayed(const Duration(milliseconds: 500));
      final r = await _obd.readResponse(timeout: const Duration(seconds: 2));
      setState(() {
        _vehicleInfo = VehicleInfo(
          vin: r != null && r.contains('49 02') ? 'VIN Available' : 'Not Available',
          protocol: 'Auto',
        );
      });
    } catch (_) {
      setState(() => _vehicleInfo = VehicleInfo(vin: 'N/A', protocol: 'Auto'));
    }
  }

  Future<void> _getReadinessMonitors() async {
    try {
      await _obd.sendCommand('0101');
      await Future.delayed(const Duration(milliseconds: 500));
      final r = await _obd.readResponse(timeout: const Duration(seconds: 2));
      setState(() {
        _readinessMonitors = r != null && r.contains('41 01')
            ? [
                ReadinessMonitor(name: 'Misfire', isSupported: true, isComplete: true),
                ReadinessMonitor(name: 'Fuel System', isSupported: true, isComplete: true),
                ReadinessMonitor(name: 'Components', isSupported: true, isComplete: false),
                ReadinessMonitor(name: 'Catalyst', isSupported: true, isComplete: true),
                ReadinessMonitor(name: 'Evaporative', isSupported: true, isComplete: false),
                ReadinessMonitor(name: 'O2 Sensor', isSupported: true, isComplete: true),
                ReadinessMonitor(name: 'O2 Heater', isSupported: true, isComplete: true),
                ReadinessMonitor(name: 'EGR', isSupported: false, isComplete: false),
              ]
            : [ReadinessMonitor(name: 'System Ready', isSupported: true, isComplete: true)];
      });
    } catch (_) {}
  }

  // ─── DTC ──────────────────────────────────────────────
  Future<void> scanDTC() async {
    if (connected == null) return;
    appendLog('🔎 Scanning DTCs...');
    await _obd.sendCommand('03');
    await Future.delayed(const Duration(milliseconds: 700));
    final confirmedRes = await _obd.readResponse(timeout: const Duration(seconds: 3));
    await _obd.sendCommand('07');
    await Future.delayed(const Duration(milliseconds: 700));
    final pendingRes = await _obd.readResponse(timeout: const Duration(seconds: 3));

    final confirmed = _parseDTC(_cleanHex(confirmedRes ?? ''));
    final pending = _parseDTC(_cleanHex(pendingRes ?? ''));
    final dtcs = <DtcModel>[];

    for (final code in confirmed) {
      final info = EnhancedDtcDatabase.getDtcInfo(code);
      dtcs.add(DtcModel(code: code, description: info.description, status: 'Confirmed', firstDetected: DateTime.now()));
    }
    for (final code in pending) {
      if (!confirmed.contains(code)) {
        final info = EnhancedDtcDatabase.getDtcInfo(code);
        dtcs.add(DtcModel(code: code, description: info.description, status: 'Pending'));
      }
    }
    setState(() => _dtcList = dtcs);
    appendLog('Found ${dtcs.length} DTC(s)');
    if (dtcs.isNotEmpty && mounted) _showDtcDialog(dtcs);
    else if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ No trouble codes!'), backgroundColor: Colors.green));
  }

  void _showDtcDialog(List<DtcModel> dtcs) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(children: [Icon(Icons.error_outline, color: Colors.red.shade700), const SizedBox(width: 8), const Text('Fault Codes Found')]),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: dtcs.length,
            itemBuilder: (_, i) {
              final dtc = dtcs[i];
              final info = EnhancedDtcDatabase.getDtcInfo(dtc.code);
              return Card(
                color: dtc.status == 'Confirmed' ? Colors.red.shade50 : Colors.orange.shade50,
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(Icons.error, color: dtc.status == 'Confirmed' ? Colors.red : Colors.orange, size: 28),
                  title: Text(dtc.code, style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 16)),
                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const SizedBox(height: 4),
                    Text(dtc.description, style: const TextStyle(fontWeight: FontWeight.w500)),
                    Text('Fix: ${info.recommendation}', style: const TextStyle(fontSize: 11)),
                    Text('Priority: ${info.priority}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: info.priority == 'High' ? Colors.red : Colors.orange)),
                  ]),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ElevatedButton(
            onPressed: () { Navigator.pop(context); clearDTC(); },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }

  Future<void> clearDTC() async {
    if (connected == null) return;
    appendLog('🧹 Clearing DTCs...');
    await _obd.sendCommand('04');
    await Future.delayed(const Duration(milliseconds: 700));
    await _obd.readResponse(timeout: const Duration(seconds: 3));
    setState(() { _dtcList = []; _alertsSent.clear(); });
    await scanDTC();
  }

  List<String> _parseDTC(String raw) {
    final s = raw.replaceAll(' ', '');
    if (!s.contains('43') && !s.contains('47')) return [];
    final idx = s.contains('43') ? s.indexOf('43') : s.indexOf('47');
    final body = s.substring(idx + 2);
    final codes = <String>[];
    for (var i = 0; i + 3 < body.length; i += 4) {
      final pair = body.substring(i, i + 4);
      if (pair == '0000') continue;
      final code = _formatDTC(pair);
      if (code.isNotEmpty) codes.add(code);
    }
    return codes;
  }

  String _formatDTC(String p) {
    try {
      final a = int.parse(p.substring(0, 2), radix: 16);
      final b = int.parse(p.substring(2, 4), radix: 16);
      final letter = ['P', 'C', 'B', 'U'][(a & 0xC0) >> 6];
      return '$letter${((a & 0x30) >> 4).toRadixString(16).toUpperCase()}${(a & 0x0F).toRadixString(16).toUpperCase()}${((b & 0xF0) >> 4).toRadixString(16).toUpperCase()}${(b & 0x0F).toRadixString(16).toUpperCase()}';
    } catch (_) { return ''; }
  }

  String _cleanHex(String raw) {
    var s = raw.replaceAll(RegExp(r'[\r\n]'), ' ').replaceAll('SEARCHING...', '').replaceAll('SEARCHING', '');
    s = s.replaceAll(RegExp(r'[^0-9A-Fa-f\s]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim().toUpperCase();
    return s;
  }

  // ─── DISCONNECT & LOGGING ─────────────────────────────
  Future<void> disconnectDevice() async {
    _autoRefreshTimer?.cancel();
    await _obdDataSub?.cancel();
    await _obd.disconnect();
    try { await connected?.disconnect(); } catch (_) {}
    setState(() { connected = null; _currentValues.clear(); _liveDataHistory.clear(); _alertsSent.clear(); });
    _valuesNotifier.value = {};
    appendLog('✓ Disconnected');
  }

  void toggleLogging() {
    setState(() {
      _isLogging = !_isLogging;
      if (_isLogging) { _dataLogger.startSession(); _resetTrip(); appendLog('📊 Started logging + trip'); }
      else appendLog('⏸️ Stopped logging');
    });
  }

  Future<void> exportData() async {
    try {
      final file = await _dataLogger.exportToCSV();
      await Share.shareXFiles([XFile(file.path)]);
      appendLog('✅ Data exported');
    } catch (e) { appendLog('❌ Export error: $e'); }
  }

  void appendLog(String s) {
    final t = DateTime.now().toIso8601String().substring(11, 19);
    final line = '[$t] $s';
    fullLogs.add(line);
    setState(() {
      logText = '$line\n$logText';
      if (logText.length > 20000) logText = logText.substring(0, 16000);
    });
  }

  void _logLocal(String s) { fullLogs.add('[${DateTime.now().toIso8601String().substring(11, 19)}] $s'); }

  Future<void> exportLogs() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final ts = DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);
      final f = File('${dir.path}/obd_log_$ts.txt');
      await f.writeAsString(fullLogs.join('\n'));
      await Share.shareXFiles([XFile(f.path)]);
    } catch (e) { appendLog('❌ Log export error: $e'); }
  }

  // ─── UI ───────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Row(children: [
          const Icon(Icons.directions_car, color: Colors.white),
          const SizedBox(width: 8),
          const Text('Car Kundali Pro'),
          if (_isLogging) ...[const SizedBox(width: 8), _blinkingDot()],
        ]),
        backgroundColor: Colors.blue.shade800,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (connected != null)
            IconButton(
              onPressed: toggleLogging,
              icon: Icon(_isLogging ? Icons.stop_circle : Icons.fiber_manual_record),
              color: _isLogging ? Colors.red.shade300 : Colors.white,
              tooltip: _isLogging ? 'Stop Logging' : 'Start Logging',
            ),
          IconButton(onPressed: exportLogs, icon: const Icon(Icons.download), tooltip: 'Export Logs'),
        ],
      ),
      body: Column(
        children: [
          if (connected != null) _buildConnectionBanner(),
          if (connected != null) _buildCompactMetrics(),
          if (connected != null) _buildFeatureGrid(),
          if (connected != null) _buildActionButtons(),
          if (connected == null) _buildScanButton(),
          Expanded(
            child: Column(
              children: [
                _buildTabBar(),
                Expanded(
                  child: TabBarView(controller: _tabs, children: [
                    _devicesTab(),
                    _liveDataTab(),
                    _readinessTab(),
                    _logsTab(),
                    _commandsTab(),
                  ]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _blinkingDot() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 800),
      builder: (_, v, __) => Container(
        width: 8, height: 8,
        decoration: BoxDecoration(color: Colors.red.withOpacity(v), shape: BoxShape.circle),
      ),
    );
  }

  Widget _buildConnectionBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.green.shade600, Colors.green.shade400], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.green.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          const Icon(Icons.bluetooth_connected, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Connected', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              Text(connected?.platformName ?? 'OBD-II Device', style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 12)),
            ]),
          ),
          if (_isLogging)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(8)),
              child: const Text('REC', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          const SizedBox(width: 8),
          IconButton(onPressed: disconnectDevice, icon: const Icon(Icons.power_settings_new, color: Colors.white), tooltip: 'Disconnect'),
        ],
      ),
    );
  }

  Widget _buildCompactMetrics() {
    return SizedBox(
      height: 90,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        children: [
          _metricChip('RPM', _currentValues['010C']?.toStringAsFixed(0) ?? '--', Colors.blue),
          _metricChip('Speed', '${_currentValues['010D']?.toStringAsFixed(0) ?? '--'} km/h', Colors.green),
          _metricChip('Coolant', '${_currentValues['0105']?.toStringAsFixed(0) ?? '--'}°C', (_currentValues['0105'] ?? 0) > 100 ? Colors.red : Colors.orange),
          _metricChip('Load', '${_currentValues['0104']?.toStringAsFixed(0) ?? '--'}%', Colors.purple),
          _metricChip('MAF', '${_currentValues['0110']?.toStringAsFixed(1) ?? '--'} g/s', Colors.teal),
          _metricChip('L/100', _currentFuelL100km > 0 ? _currentFuelL100km.toStringAsFixed(1) : '--', Colors.indigo),
        ],
      ),
    );
  }

  Widget _metricChip(String label, String value, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [color.withOpacity(0.9), color.withOpacity(0.7)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: color.withOpacity(0.25), blurRadius: 6, offset: const Offset(0, 3))],
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        Text(label, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 10)),
      ]),
    );
  }

  Widget _buildFeatureGrid() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(
        children: [
          Expanded(child: _featureCard('🎛 Dashboard', 'Live Gauges', Colors.blue, () => Navigator.push(context, MaterialPageRoute(builder: (_) => DashboardScreen(valuesNotifier: _valuesNotifier))))),
          const SizedBox(width: 10),
          Expanded(child: _featureCard('❤️ Health', '${_dtcList.isEmpty ? "All OK" : "${_dtcList.length} codes"}', Colors.green, () => Navigator.push(context, MaterialPageRoute(builder: (_) => HealthScreen(dtcList: _dtcList, liveValues: _currentValues, readinessMonitors: _readinessMonitors))))),
          const SizedBox(width: 10),
          Expanded(child: _featureCard('🗺 Trip', '${_tripDistanceKm.toStringAsFixed(1)} km', Colors.orange, () => Navigator.push(context, MaterialPageRoute(builder: (_) => TripScreen(tripData: _tripData))))),
          const SizedBox(width: 10),
          Expanded(child: _featureCard('⚡ Perf', '0-100', Colors.red, () => Navigator.push(context, MaterialPageRoute(builder: (_) => PerformanceScreen(valuesNotifier: _valuesNotifier))))),
        ],
      ),
    );
  }

  Widget _featureCard(String title, String subtitle, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 2))],
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          const SizedBox(height: 3),
          Text(subtitle, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w500), textAlign: TextAlign.center, overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: scanDTC,
              icon: const Icon(Icons.search, size: 18),
              label: const Text('Scan DTC', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade600, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: clearDTC,
              icon: const Icon(Icons.cleaning_services, size: 18),
              label: const Text('Clear DTC', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade600, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: _resetTrip,
            icon: const Icon(Icons.restart_alt, size: 18),
            label: const Text('Trip', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade600, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          ),
        ],
      ),
    );
  }

  Widget _buildScanButton() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _isScanning ? null : startScan,
          icon: _isScanning ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.bluetooth_searching),
          label: Text(_isScanning ? 'Scanning...' : 'Scan for OBD Devices'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 4),
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
      ),
      child: TabBar(
        controller: _tabs,
        labelColor: Colors.blue.shade700,
        unselectedLabelColor: Colors.grey.shade500,
        indicatorColor: Colors.blue.shade700,
        indicatorWeight: 3,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
        tabs: const [
          Tab(icon: Icon(Icons.bluetooth, size: 20), text: 'Devices'),
          Tab(icon: Icon(Icons.show_chart, size: 20), text: 'Live'),
          Tab(icon: Icon(Icons.verified, size: 20), text: 'Readiness'),
          Tab(icon: Icon(Icons.article, size: 20), text: 'Logs'),
          Tab(icon: Icon(Icons.terminal, size: 20), text: 'Terminal'),
        ],
      ),
    );
  }

  // ─── TABS ─────────────────────────────────────────────
  Widget _devicesTab() {
    if (connected != null) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.green.shade50, shape: BoxShape.circle), child: Icon(Icons.bluetooth_connected, size: 64, color: Colors.green.shade600)),
          const SizedBox(height: 20),
          Text('Connected', style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
          const SizedBox(height: 6),
          Text(connected?.platformName ?? 'OBD Device', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 30),
          ElevatedButton.icon(
            onPressed: disconnectDevice,
            icon: const Icon(Icons.bluetooth_disabled),
            label: const Text('Disconnect'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade600, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          ),
        ]),
      );
    }

    if (scanResults.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.bluetooth_searching, size: 80, color: Colors.grey.shade300),
        const SizedBox(height: 20),
        Text('No devices found', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
        const SizedBox(height: 8),
        Text('Tap "Scan for OBD Devices"', style: TextStyle(color: Colors.grey.shade500)),
        const SizedBox(height: 20),
        // Tip card
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12)),
          child: const Text('💡 Make sure your ELM327 adapter is plugged into OBD-II port and Bluetooth is enabled on the adapter.', style: TextStyle(fontSize: 12, color: Colors.blue), textAlign: TextAlign.center),
        ),
      ]));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: scanResults.length,
      itemBuilder: (_, i) {
        final result = scanResults[i];
        final name = _getDeviceName(result);
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)]),
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(10)), child: Icon(Icons.bluetooth, color: Colors.blue.shade700, size: 26)),
            title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            subtitle: Text('${result.rssi} dBm  •  ${result.device.remoteId}', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            trailing: _isConnecting ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(Icons.chevron_right, color: Colors.grey.shade400),
            onTap: _isConnecting ? null : () => connectDevice(result.device),
          ),
        );
      },
    );
  }

  Widget _liveDataTab() {
    if (connected == null) return _notConnectedPlaceholder();
    if (_currentValues.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [CircularProgressIndicator(color: Colors.blue.shade700), const SizedBox(height: 20), const Text('Waiting for data...')]));

    return LiveDataScreen(currentValues: _currentValues, historyData: _liveDataHistory);
  }

  Widget _readinessTab() {
    if (connected == null) return _notConnectedPlaceholder();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_readinessMonitors.isNotEmpty)
          Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)]),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Readiness Monitors', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                ..._readinessMonitors.map((m) => Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: m.isComplete ? Colors.green.shade50 : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: m.isComplete ? Colors.green.shade200 : Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(m.isComplete ? Icons.check_circle : Icons.pending, color: m.isComplete ? Colors.green : Colors.orange),
                      const SizedBox(width: 12),
                      Expanded(child: Text(m.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: m.isComplete ? Colors.green.shade600 : Colors.orange.shade600, borderRadius: BorderRadius.circular(6)),
                        child: Text(m.isComplete ? 'Ready' : 'Not Ready', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                )).toList(),
              ],
            ),
          ),
        if (_vehicleInfo != null) ...[
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)]),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Vehicle Info', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _infoRow('VIN', _vehicleInfo!.vin ?? 'N/A'),
                _infoRow('Protocol', _vehicleInfo!.protocol ?? 'Auto'),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _infoRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [Text(label, style: TextStyle(color: Colors.grey.shade600)), Text(value, style: const TextStyle(fontWeight: FontWeight.bold))],
    ),
  );

  Widget _logsTab() {
    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(color: Colors.grey.shade50, border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
        child: Row(
          children: [
            Icon(Icons.article, color: Colors.blue.shade700),
            const SizedBox(width: 10),
            const Expanded(child: Text('System Logs', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
            ElevatedButton.icon(
              onPressed: exportLogs,
              icon: const Icon(Icons.download, size: 16),
              label: const Text('Export'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            ),
          ],
        ),
      ),
      Expanded(
        child: Container(
          color: const Color(0xFF1E1E1E),
          padding: const EdgeInsets.all(14),
          child: SingleChildScrollView(
            reverse: true,
            child: SelectableText(
              logText.isEmpty ? '// Waiting for logs...' : logText,
              style: const TextStyle(fontFamily: 'monospace', color: Color(0xFF4EC9B0), fontSize: 12, height: 1.5),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _commandsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _commandController,
                  decoration: InputDecoration(
                    hintText: 'e.g. 010C, ATZ, 03',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    prefixIcon: const Icon(Icons.terminal),
                    filled: true, fillColor: Colors.white,
                  ),
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: connected == null ? null : () async {
                  final cmd = _commandController.text.trim().toUpperCase();
                  if (cmd.isEmpty) return;
                  setState(() => _commandResponse = 'Sending...');
                  appendLog('>> $cmd');
                  await _obd.sendCommand(cmd);
                  await Future.delayed(const Duration(milliseconds: 500));
                  final res = await _obd.readResponse(timeout: const Duration(seconds: 3));
                  setState(() => _commandResponse = res ?? 'No response');
                  appendLog('<< $_commandResponse');
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: const Text('Send', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(10)),
            child: SingleChildScrollView(
              child: SelectableText(
                _commandResponse.isEmpty ? '// Response will appear here...' : _commandResponse,
                style: const TextStyle(fontFamily: 'monospace', color: Color(0xFF4EC9B0), fontSize: 14, height: 1.6),
              ),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Quick commands:', style: TextStyle(color: Colors.grey.shade600, fontSize: 12, fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6, runSpacing: 6,
                children: [
                  ['010C', 'RPM'], ['010D', 'Speed'], ['0105', 'Coolant'], ['0104', 'Load'],
                  ['03', 'DTCs'], ['04', 'Clear'], ['0100', 'PIDs'], ['ATZ', 'Reset'],
                  ['ATRV', 'Voltage'], ['0902', 'VIN'],
                ].map((e) => InkWell(
                  onTap: () => _commandController.text = e[0],
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.blue.shade200)),
                    child: Text('${e[0]}  ${e[1]}', style: TextStyle(color: Colors.blue.shade700, fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                  ),
                )).toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _notConnectedPlaceholder() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Icon(Icons.link_off, size: 80, color: Colors.grey.shade300),
    const SizedBox(height: 16),
    Text('Not Connected', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
    const SizedBox(height: 8),
    Text('Connect to an OBD device first', style: TextStyle(color: Colors.grey.shade500)),
  ]));
}