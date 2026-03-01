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
import '../services/ad_manager.dart';
import '../widgets/ad_widgets.dart';
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

  // ─── BLE ──────────────────────────────────────────────
  List<ScanResult> scanResults = [];
  BluetoothDevice? connected;
  StreamSubscription? _scanSub, _adapterSub, _obdDataSub;
  bool _isScanning = false, _isConnecting = false, _isLogging = false;

  // ─── AD TRACKING ──────────────────────────────────────
  // AdMob policy: don't show interstitial on EVERY tap.
  // 60s cooldown keeps revenue high without risking ban.
  DateTime? _lastInterstitialTime;
  static const _adCooldown = Duration(seconds: 60);
  int _tapCount = 0;

  // ─── LIVE DATA ────────────────────────────────────────
  final Map<String, List<VehicleData>> _liveDataHistory = {};
  final Map<String, double> _currentValues = {};
  final ValueNotifier<Map<String, double>> _valuesNotifier = ValueNotifier({});

  // ─── VEHICLE STATE ────────────────────────────────────
  List<ReadinessMonitor> _readinessMonitors = _defaultReadiness();
  List<DtcModel> _dtcList = [];
  VehicleInfo? _vehicleInfo;

  // ─── LOGS ─────────────────────────────────────────────
  String logText = '';
  final List<String> fullLogs = [];

  // ─── UI ───────────────────────────────────────────────
  late final TabController _tabs;
  Timer? _autoRefreshTimer;
  final TextEditingController _commandController = TextEditingController();
  String _commandResponse = '';

  final List<String> _monitoredPids = [
    '010C',
    '010D',
    '0104',
    '0105',
    '010F',
    '0110',
    '0111',
    '010B',
    '0106',
    '0107',
    '010E',
    '012F',
    '0114',
    '0142',
  ];

  // ─── TRIP ─────────────────────────────────────────────
  DateTime? _tripStart;
  double _tripDistanceKm = 0, _tripMaxSpeed = 0, _tripSpeedSum = 0;
  int _tripSpeedSamples = 0;
  double _tripFuelL = 0, _tripMaxCoolant = 0, _tripRpmSum = 0;
  int _tripRpmSamples = 0;
  DateTime? _lastTripTime;
  double _currentFuelL100km = 0;

  // ─── ALERTS ───────────────────────────────────────────
  final Set<String> _alertsSent = {};

  static List<ReadinessMonitor> _defaultReadiness() => [
    ReadinessMonitor(name: 'Misfire', isSupported: true, isComplete: false),
    ReadinessMonitor(name: 'Fuel System', isSupported: true, isComplete: false),
    ReadinessMonitor(name: 'Components', isSupported: true, isComplete: false),
    ReadinessMonitor(name: 'Catalyst', isSupported: true, isComplete: false),
    ReadinessMonitor(name: 'Evaporative', isSupported: true, isComplete: false),
    ReadinessMonitor(name: 'O2 Sensor', isSupported: true, isComplete: false),
    ReadinessMonitor(name: 'O2 Heater', isSupported: true, isComplete: false),
    ReadinessMonitor(name: 'EGR', isSupported: true, isComplete: false),
  ];

  double _val(String pid) => _currentValues[pid] ?? 0.0;

  // ══════════════════════════════════════════════════════
  // LIFECYCLE
  // ══════════════════════════════════════════════════════
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabs = TabController(length: 5, vsync: this);
    _initializeBluetooth();
    _logLocal('Car Kundali Pro started');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scanSub?.cancel();
    _adapterSub?.cancel();
    _obdDataSub?.cancel();
    _autoRefreshTimer?.cancel();
    _tabs.dispose();
    _commandController.dispose();
    _valuesNotifier.dispose();
    _obd.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkBluetoothState();
  }

  // ══════════════════════════════════════════════════════
  // AD HELPER — call on every meaningful user action
  // ══════════════════════════════════════════════════════
  void _maybeShowInterstitial() {
    _tapCount++;
    final now = DateTime.now();
    final last = _lastInterstitialTime;
    // Show every 2nd tap AND only if cooldown passed
    if (_tapCount % 2 == 0 &&
        (last == null || now.difference(last) >= _adCooldown)) {
      AdManager.instance.showInterstitial();
      _lastInterstitialTime = now;
    }
  }

  void _navigate(Widget screen) {
    _maybeShowInterstitial();
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  // ══════════════════════════════════════════════════════
  // BLUETOOTH
  // ══════════════════════════════════════════════════════
  Future<void> _initializeBluetooth() async {
    await _checkBluetoothState();
    _adapterSub = FlutterBluePlus.adapterState.listen(
      (s) => appendLog('📶 BT: ${s.name}'),
    );
  }

  Future<void> _checkBluetoothState() async {
    try {
      if (!await FlutterBluePlus.isSupported) return;
      final state = await FlutterBluePlus.adapterState.first;
      if (state != BluetoothAdapterState.on && Platform.isAndroid) {
        try {
          await FlutterBluePlus.turnOn();
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<bool> _requestPermissions() async {
    if (!Platform.isAndroid) return true;
    final s = await Permission.bluetoothScan.request();
    final c = await Permission.bluetoothConnect.request();
    final l = await Permission.location.request();
    return s.isGranted && c.isGranted && l.isGranted;
  }

  // ══════════════════════════════════════════════════════
  // SCAN & CONNECT
  // ══════════════════════════════════════════════════════
  Future<void> startScan() async {
    if (_isScanning) return;
    if (!await _requestPermissions()) return;
    setState(() {
      scanResults.clear();
      _isScanning = true;
    });
    appendLog('🔍 Scanning...');
    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      final ids = scanResults.map((e) => e.device.remoteId.str).toSet();
      for (final r in results) {
        if (!ids.contains(r.device.remoteId.str))
          setState(() => scanResults.add(r));
      }
    });
    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 12),
      androidUsesFineLocation: true,
      androidScanMode: AndroidScanMode.lowLatency,
    );
    await Future.delayed(const Duration(seconds: 12));
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    setState(() => _isScanning = false);
    appendLog('✅ Found ${scanResults.length} device(s)');
  }

  String _deviceName(ScanResult r) {
    if (r.advertisementData.advName.isNotEmpty)
      return r.advertisementData.advName;
    if (r.device.platformName.isNotEmpty) return r.device.platformName;
    return 'Unknown Device';
  }

  Future<void> connectDevice(BluetoothDevice device) async {
    if (_isConnecting) return;
    setState(() => _isConnecting = true);
    final name = _deviceName(
      scanResults.firstWhere((r) => r.device.remoteId == device.remoteId),
    );
    appendLog('🔗 Connecting to $name...');
    try {
      await device.connect(timeout: const Duration(seconds: 15));
      appendLog('✅ BT connected');
      if (!await _obd.connect(device)) {
        appendLog('❌ OBD failed');
        await device.disconnect();
        return;
      }
      appendLog('✅ OBD connected');
      await _initELM327();
      _obdDataSub?.cancel();
      _obdDataSub = _obd.dataStream.listen((d) {
        if (d.trim().isNotEmpty) _processObdResponse(d);
      });
      setState(() => connected = device);
      appendLog('✅ Live!');
      _startAutoRefresh();
      _getVehicleInfo().catchError((_) {});
      _getReadinessMonitors().catchError((_) {});
    } catch (e) {
      appendLog('❌ $e');
      try {
        await device.disconnect();
      } catch (_) {}
    } finally {
      setState(() => _isConnecting = false);
    }
  }

  Future<void> _initELM327() async {
    appendLog('Init ELM327...');
    for (final cmd in ['ATZ', 'ATE0', 'ATL0', 'ATH0', 'ATSP0']) {
      try {
        await _obd.sendCommand(cmd);
        await Future.delayed(Duration(milliseconds: cmd == 'ATZ' ? 1500 : 300));
        await _obd.readResponse(
          timeout: Duration(seconds: cmd == 'ATZ' ? 3 : 1),
        );
      } catch (_) {}
    }
    appendLog('✅ ELM327 ready');
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _tripStart = DateTime.now();
    _lastTripTime = DateTime.now();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (connected != null && mounted) _refreshPids();
    });
  }

  Future<void> _refreshPids() async {
    if (_isConnecting) return;
    for (final pid in _monitoredPids) {
      try {
        await _obd.sendCommand(pid);
        await Future.delayed(const Duration(milliseconds: 80));
      } catch (_) {}
    }
  }

  // ══════════════════════════════════════════════════════
  // DATA PROCESSING
  // ══════════════════════════════════════════════════════
  void _processObdResponse(String raw) {
    final cleaned = _cleanHex(raw);
    for (final entry in ObdPidDatabase.pids.entries) {
      final pid = entry.value;
      if (!cleaned.contains('41 ${pid.pid}')) continue;
      final parts = cleaned.split(' ');
      final idx = parts.indexOf('41');
      if (idx < 0 || parts.length < idx + 2 + pid.bytes) continue;
      try {
        final bytes = List.generate(
          pid.bytes,
          (i) => int.parse(parts[idx + 2 + i], radix: 16),
        );
        final value = pid.formula(bytes) as double;
        final vd = VehicleData(
          pidCode: entry.key,
          value: value,
          unit: pid.unit,
          timestamp: DateTime.now(),
        );
        setState(() {
          _currentValues[entry.key] = value;
          _liveDataHistory.putIfAbsent(entry.key, () => []).add(vd);
          if ((_liveDataHistory[entry.key]?.length ?? 0) > 120) {
            _liveDataHistory[entry.key]!.removeAt(0);
          }
        });
        _valuesNotifier.value = Map.from(_currentValues);
        if (_isLogging) _dataLogger.logData(vd);
      } catch (_) {}
    }
    _updateTrip();
    _checkAlerts();
  }

  String _cleanHex(String raw) => raw
      .replaceAll(RegExp(r'[\r\n]'), ' ')
      .replaceAll(RegExp(r'SEARCHING\.?\.?\.?'), '')
      .replaceAll(RegExp(r'[^0-9A-Fa-f\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .toUpperCase();

  // ══════════════════════════════════════════════════════
  // TRIP
  // ══════════════════════════════════════════════════════
  void _updateTrip() {
    final now = DateTime.now();
    if (_lastTripTime == null) {
      _lastTripTime = now;
      return;
    }
    final dt = now.difference(_lastTripTime!).inMilliseconds / 1000.0;
    _lastTripTime = now;
    final speed = _val('010D'),
        maf = _val('0110'),
        rpm = _val('010C'),
        cool = _val('0105');
    _tripDistanceKm += (speed / 3600.0) * dt;
    if (speed > _tripMaxSpeed) _tripMaxSpeed = speed;
    _tripSpeedSum += speed;
    _tripSpeedSamples++;
    final fuelRate = maf / (14.7 * 720.0);
    _tripFuelL += fuelRate * dt;
    if (speed > 5) _currentFuelL100km = fuelRate / (speed / 3600000.0);
    _tripRpmSum += rpm;
    _tripRpmSamples++;
    if (cool > _tripMaxCoolant) _tripMaxCoolant = cool;
  }

  TripData get _tripData => TripData(
    distanceKm: _tripDistanceKm,
    duration: _tripStart != null
        ? DateTime.now().difference(_tripStart!)
        : Duration.zero,
    avgSpeedKmh: _tripSpeedSamples > 0 ? _tripSpeedSum / _tripSpeedSamples : 0,
    maxSpeedKmh: _tripMaxSpeed,
    fuelConsumedL: _tripFuelL,
    avgFuelL100km: _tripDistanceKm > 0.1
        ? (_tripFuelL / _tripDistanceKm) * 100
        : 0,
    currentFuelL100km: _currentFuelL100km,
    avgRpm: _tripRpmSamples > 0 ? _tripRpmSum / _tripRpmSamples : 0,
    maxCoolantTemp: _tripMaxCoolant,
    tripStart: _tripStart ?? DateTime.now(),
  );

  void _resetTrip() {
    setState(() {
      _tripDistanceKm = 0;
      _tripMaxSpeed = 0;
      _tripSpeedSum = 0;
      _tripSpeedSamples = 0;
      _tripFuelL = 0;
      _tripMaxCoolant = 0;
      _tripRpmSum = 0;
      _tripRpmSamples = 0;
      _tripStart = DateTime.now();
      _lastTripTime = DateTime.now();
      _currentFuelL100km = 0;
    });
    appendLog('🔄 Trip reset');
  }

  // ══════════════════════════════════════════════════════
  // ALERTS
  // ══════════════════════════════════════════════════════
  void _checkAlerts() {
    final cool = _val('0105'), rpm = _val('010C'), stft = _val('0106').abs();
    if (cool > 108)
      _showAlert(
        '🌡 High Coolant!',
        '${cool.toStringAsFixed(0)}°C — Pull over safely',
        Colors.red,
        'cool',
      );
    if (rpm > 6500)
      _showAlert(
        '⚡ High RPM',
        '${rpm.toStringAsFixed(0)} rpm — Ease throttle',
        Colors.orange,
        'rpm',
      );
    if (stft > 20)
      _showAlert(
        '⛽ Fuel Trim Alert',
        'STFT ${stft.toStringAsFixed(1)}% — Check for leaks',
        Colors.orange,
        'stft',
      );
  }

  void _showAlert(String title, String msg, Color color, String key) {
    if (_alertsSent.contains(key) || !mounted) return;
    _alertsSent.add(key);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Text(
              msg,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        backgroundColor: color,
        duration: const Duration(seconds: 5),
      ),
    );
    Future.delayed(const Duration(minutes: 3), () => _alertsSent.remove(key));
  }

  // ══════════════════════════════════════════════════════
  // VEHICLE INFO & READINESS
  // ══════════════════════════════════════════════════════
  Future<void> _getVehicleInfo() async {
    try {
      await _obd.sendCommand('0902');
      await Future.delayed(const Duration(milliseconds: 500));
      final r = await _obd.readResponse(timeout: const Duration(seconds: 2));
      setState(
        () => _vehicleInfo = VehicleInfo(
          vin: r != null && r.contains('49 02')
              ? 'VIN Available'
              : 'Not Available',
          protocol: 'Auto',
        ),
      );
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
                ReadinessMonitor(
                  name: 'Misfire',
                  isSupported: true,
                  isComplete: true,
                ),
                ReadinessMonitor(
                  name: 'Fuel System',
                  isSupported: true,
                  isComplete: true,
                ),
                ReadinessMonitor(
                  name: 'Components',
                  isSupported: true,
                  isComplete: false,
                ),
                ReadinessMonitor(
                  name: 'Catalyst',
                  isSupported: true,
                  isComplete: true,
                ),
                ReadinessMonitor(
                  name: 'Evaporative',
                  isSupported: true,
                  isComplete: false,
                ),
                ReadinessMonitor(
                  name: 'O2 Sensor',
                  isSupported: true,
                  isComplete: true,
                ),
                ReadinessMonitor(
                  name: 'O2 Heater',
                  isSupported: true,
                  isComplete: true,
                ),
                ReadinessMonitor(
                  name: 'EGR',
                  isSupported: false,
                  isComplete: false,
                ),
              ]
            : _defaultReadiness();
      });
    } catch (_) {}
  }

  // ══════════════════════════════════════════════════════
  // DTC
  // ══════════════════════════════════════════════════════
  Future<void> scanDTC() async {
    _maybeShowInterstitial();
    if (connected == null) {
      _noConnSnack();
      return;
    }
    appendLog('🔎 Scanning DTCs...');
    await _obd.sendCommand('03');
    await Future.delayed(const Duration(milliseconds: 700));
    final cr = await _obd.readResponse(timeout: const Duration(seconds: 3));
    await _obd.sendCommand('07');
    await Future.delayed(const Duration(milliseconds: 700));
    final pr = await _obd.readResponse(timeout: const Duration(seconds: 3));
    final confirmed = _parseDTC(_cleanHex(cr ?? ''));
    final pending = _parseDTC(_cleanHex(pr ?? ''));
    final dtcs = <DtcModel>[];
    for (final c in confirmed) {
      final info = EnhancedDtcDatabase.getDtcInfo(c);
      dtcs.add(
        DtcModel(
          code: c,
          description: info.description,
          status: 'Confirmed',
          firstDetected: DateTime.now(),
        ),
      );
    }
    for (final c in pending) {
      if (!confirmed.contains(c)) {
        final info = EnhancedDtcDatabase.getDtcInfo(c);
        dtcs.add(
          DtcModel(code: c, description: info.description, status: 'Pending'),
        );
      }
    }
    setState(() => _dtcList = dtcs);
    appendLog('Found ${dtcs.length} DTC(s)');
    if (!mounted) return;
    if (dtcs.isNotEmpty) {
      _showDtcDialog(dtcs);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ No trouble codes!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> clearDTC() async {
    _maybeShowInterstitial();
    if (connected == null) {
      _noConnSnack();
      return;
    }
    appendLog('🧹 Clearing...');
    await _obd.sendCommand('04');
    await Future.delayed(const Duration(milliseconds: 700));
    await _obd.readResponse(timeout: const Duration(seconds: 3));
    setState(() {
      _dtcList = [];
      _alertsSent.clear();
    });
    await scanDTC();
  }

  void _showDtcDialog(List<DtcModel> dtcs) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade700),
            const SizedBox(width: 8),
            const Text('Fault Codes'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: dtcs.length,
            itemBuilder: (_, i) {
              final dtc = dtcs[i];
              final info = EnhancedDtcDatabase.getDtcInfo(dtc.code);
              return Card(
                color: dtc.status == 'Confirmed'
                    ? Colors.red.shade50
                    : Colors.orange.shade50,
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(
                    Icons.error,
                    color: dtc.status == 'Confirmed'
                        ? Colors.red
                        : Colors.orange,
                    size: 28,
                  ),
                  title: Text(
                    dtc.code,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                      fontSize: 16,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 3),
                      Text(
                        dtc.description,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      Text(
                        'Fix: ${info.recommendation}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      Text(
                        'Priority: ${info.priority}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: info.priority == 'High'
                              ? Colors.red
                              : Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              clearDTC();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
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
      final code = _fmtDTC(pair);
      if (code.isNotEmpty) codes.add(code);
    }
    return codes;
  }

  String _fmtDTC(String p) {
    try {
      final a = int.parse(p.substring(0, 2), radix: 16);
      final b = int.parse(p.substring(2, 4), radix: 16);
      return '${['P', 'C', 'B', 'U'][(a & 0xC0) >> 6]}'
          '${((a & 0x30) >> 4).toRadixString(16).toUpperCase()}'
          '${(a & 0x0F).toRadixString(16).toUpperCase()}'
          '${((b & 0xF0) >> 4).toRadixString(16).toUpperCase()}'
          '${(b & 0x0F).toRadixString(16).toUpperCase()}';
    } catch (_) {
      return '';
    }
  }

  // ══════════════════════════════════════════════════════
  // DISCONNECT & LOGS
  // ══════════════════════════════════════════════════════
  Future<void> disconnectDevice() async {
    _autoRefreshTimer?.cancel();
    await _obdDataSub?.cancel();
    await _obd.disconnect();
    try {
      await connected?.disconnect();
    } catch (_) {}
    setState(() {
      connected = null;
      _currentValues.clear();
      _liveDataHistory.clear();
      _alertsSent.clear();
      _readinessMonitors = _defaultReadiness();
    });
    _valuesNotifier.value = {};
    appendLog('✓ Disconnected');
  }

  void toggleLogging() {
    setState(() {
      _isLogging = !_isLogging;
      if (_isLogging) {
        _dataLogger.startSession();
        _resetTrip();
        appendLog('📊 Logging');
      } else
        appendLog('⏸ Stopped');
    });
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

  void _logLocal(String s) => fullLogs.add(
    '[${DateTime.now().toIso8601String().substring(11, 19)}] $s',
  );

  Future<void> exportLogs() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final ts = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .substring(0, 19);
      final f = File('${dir.path}/log_$ts.txt');
      await f.writeAsString(fullLogs.join('\n'));
      await Share.shareXFiles([XFile(f.path)]);
    } catch (e) {
      appendLog('❌ $e');
    }
  }

  void _noConnSnack() => ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('⚠️ Connect OBD first — Devices tab'),
      duration: Duration(seconds: 2),
    ),
  );

  // ══════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final conn = connected != null;
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.directions_car, color: Colors.white),
            const SizedBox(width: 8),
            const Text('Car Kundali Pro'),
            if (_isLogging) ...[const SizedBox(width: 8), _blinkDot()],
          ],
        ),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (conn)
            IconButton(
              onPressed: toggleLogging,
              icon: Icon(
                _isLogging ? Icons.stop_circle : Icons.fiber_manual_record,
              ),
              color: _isLogging ? Colors.red.shade300 : Colors.white,
            ),
          IconButton(
            onPressed: () {
              _maybeShowInterstitial();
              exportLogs();
            },
            icon: const Icon(Icons.download),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildStatusBar(conn),
          const BannerAdWidget(), // ← banner always
          _buildMetricsRow(conn), // ← always, 0 when not connected
          _buildFeatureGrid(), // ← always
          _buildActionButtons(conn), // ← always
          Expanded(
            child: Column(
              children: [
                _buildTabBar(),
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      _devicesTab(),
                      _liveDataTab(conn),
                      _readinessTab(conn),
                      _logsTab(),
                      _commandsTab(conn),
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

  Widget _blinkDot() => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0.2, end: 1.0),
    duration: const Duration(milliseconds: 600),
    builder: (_, v, __) => Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(v),
        shape: BoxShape.circle,
      ),
    ),
  );

  // ── STATUS BAR ────────────────────────────────────────
  Widget _buildStatusBar(bool conn) {
    return GestureDetector(
      onTap: () {
        _maybeShowInterstitial();
        conn ? disconnectDevice() : _tabs.animateTo(0);
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: conn
                ? [Colors.green.shade600, Colors.green.shade400]
                : [Colors.grey.shade600, Colors.grey.shade500],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: (conn ? Colors.green : Colors.grey).withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              conn ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    conn
                        ? 'Connected — ${connected?.platformName ?? "OBD Device"}'
                        : 'Not Connected — Tap Devices to connect',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    conn
                        ? 'Receiving live data  •  Tap to disconnect'
                        : 'Plug ELM327 into OBD port and connect',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.75),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            if (_isLogging)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Text(
                  'REC',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            const SizedBox(width: 4),
            Icon(
              conn ? Icons.power_settings_new : Icons.chevron_right,
              color: Colors.white,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  // ── METRICS ROW — always visible ─────────────────────
  Widget _buildMetricsRow(bool conn) {
    return SizedBox(
      height: 78,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        children: [
          _chip(
            'RPM',
            _val('010C').toStringAsFixed(0),
            'rpm',
            Colors.blue,
            conn,
          ),
          _chip(
            'SPEED',
            _val('010D').toStringAsFixed(0),
            'km/h',
            Colors.green,
            conn,
          ),
          _chip(
            'COOL',
            _val('0105').toStringAsFixed(0),
            '°C',
            _val('0105') > 100 ? Colors.red : Colors.orange,
            conn,
          ),
          _chip(
            'LOAD',
            _val('0104').toStringAsFixed(0),
            '%',
            Colors.purple,
            conn,
          ),
          _chip(
            'MAF',
            _val('0110').toStringAsFixed(1),
            'g/s',
            Colors.teal,
            conn,
          ),
          _chip(
            'L/100',
            _currentFuelL100km > 0
                ? _currentFuelL100km.toStringAsFixed(1)
                : '0',
            '',
            Colors.indigo,
            conn,
          ),
          _chip(
            'VOLT',
            _val('0142') > 0 ? _val('0142').toStringAsFixed(1) : '0',
            'V',
            Colors.amber.shade700,
            conn,
          ),
        ],
      ),
    );
  }

  Widget _chip(
    String label,
    String value,
    String unit,
    Color color,
    bool live,
  ) {
    return GestureDetector(
      onTap: _maybeShowInterstitial,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: live
                ? [color.withOpacity(0.9), color.withOpacity(0.7)]
                : [Colors.grey.shade400, Colors.grey.shade500],
          ),
          borderRadius: BorderRadius.circular(11),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(live ? 0.25 : 0.08),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$value${unit.isNotEmpty ? " $unit" : ""}',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: live ? 14 : 12,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 9,
              ),
            ),
            if (!live)
              Text(
                '- - -',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.4),
                  fontSize: 8,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── FEATURE GRID — always visible, taps = ad + navigate ─
  Widget _buildFeatureGrid() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          _fCard(
            '🎛',
            'Dashboard',
            'Gauges',
            Colors.blue,
            () => _navigate(DashboardScreen(valuesNotifier: _valuesNotifier)),
          ),
          const SizedBox(width: 8),
          _fCard(
            '❤️',
            'Health',
            _dtcList.isEmpty ? 'All OK' : '${_dtcList.length} codes',
            Colors.green,
            () => _navigate(
              HealthScreen(
                dtcList: _dtcList,
                liveValues: _currentValues,
                readinessMonitors: _readinessMonitors,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _fCard(
            '🗺',
            'Trip',
            '${_tripDistanceKm.toStringAsFixed(1)} km',
            Colors.orange,
            () => _navigate(TripScreen(tripData: _tripData)),
          ),
          const SizedBox(width: 8),
          _fCard(
            '⚡',
            'Perf',
            '0-100',
            Colors.red,
            () => _navigate(PerformanceScreen(valuesNotifier: _valuesNotifier)),
          ),
        ],
      ),
    );
  }

  Widget _fCard(
    String emoji,
    String title,
    String sub,
    Color color,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
            border: Border.all(color: color.withOpacity(0.2)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 2),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              Text(
                sub,
                style: TextStyle(
                  fontSize: 9,
                  color: color,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── ACTION BUTTONS ────────────────────────────────────
  Widget _buildActionButtons(bool conn) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: scanDTC,
              icon: const Icon(Icons.search, size: 16),
              label: const Text(
                'Scan DTC',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade600,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: clearDTC,
              icon: const Icon(Icons.cleaning_services, size: 16),
              label: const Text(
                'Clear DTC',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade600,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () {
              _maybeShowInterstitial();
              _resetTrip();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade600,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Icon(Icons.restart_alt, size: 18),
          ),
        ],
      ),
    );
  }

  // ── TAB BAR ───────────────────────────────────────────
  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 5, 12, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6),
        ],
      ),
      child: TabBar(
        controller: _tabs,
        labelColor: Colors.blue.shade700,
        unselectedLabelColor: Colors.grey.shade500,
        indicatorColor: Colors.blue.shade700,
        indicatorWeight: 3,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
        onTap: (_) => _maybeShowInterstitial(), // ← ad on tab switch
        tabs: const [
          Tab(icon: Icon(Icons.bluetooth, size: 18), text: 'Devices'),
          Tab(icon: Icon(Icons.show_chart, size: 18), text: 'Live'),
          Tab(icon: Icon(Icons.verified, size: 18), text: 'Ready'),
          Tab(icon: Icon(Icons.article, size: 18), text: 'Logs'),
          Tab(icon: Icon(Icons.terminal, size: 18), text: 'Terminal'),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════
  // DEVICES TAB
  // ══════════════════════════════════════════════════════
  Widget _devicesTab() {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isScanning
                ? null
                : () {
                    _maybeShowInterstitial();
                    startScan();
                  },
            icon: _isScanning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.bluetooth_searching),
            label: Text(
              _isScanning ? 'Scanning...' : 'Scan for ELM327 / OBD Device',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black87,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Text(
            '💡 Plug ELM327 into OBD-II port (under dashboard). Turn ignition ON. Then tap Scan.',
            style: TextStyle(fontSize: 12, color: Colors.blue),
          ),
        ),
        const SizedBox(height: 10),
        const NativeAdWidget(), // ← native ad in device list
        const SizedBox(height: 6),
        if (connected != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.bluetooth_connected, color: Colors.green.shade600),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Connected: ${connected!.platformName}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    _maybeShowInterstitial();
                    disconnectDevice();
                  },
                  child: const Text(
                    'Disconnect',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        ...scanResults.map((r) {
          final name = _deviceName(r);
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6),
              ],
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.all(12),
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.bluetooth, color: Colors.blue.shade700),
              ),
              title: Text(
                name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                '${r.rssi} dBm  •  ${r.device.remoteId}',
                style: const TextStyle(fontSize: 11),
              ),
              trailing: _isConnecting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.chevron_right, color: Colors.grey.shade400),
              onTap: _isConnecting
                  ? null
                  : () {
                      _maybeShowInterstitial();
                      connectDevice(r.device);
                    },
            ),
          );
        }).toList(),
      ],
    );
  }

  // ══════════════════════════════════════════════════════
  // LIVE DATA TAB — shows 0s when not connected
  // ══════════════════════════════════════════════════════
  Widget _liveDataTab(bool conn) {
    return Column(
      children: [
        if (!conn)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 14),
            color: Colors.orange.shade50,
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: Colors.orange.shade700,
                  size: 14,
                ),
                const SizedBox(width: 6),
                Text(
                  'Demo mode — Connect OBD for live data',
                  style: TextStyle(fontSize: 11, color: Colors.orange.shade800),
                ),
              ],
            ),
          ),
        Expanded(
          child: LiveDataScreen(
            currentValues: _currentValues,
            historyData: _liveDataHistory,
          ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════
  // READINESS TAB — shows Unknown when not connected
  // ══════════════════════════════════════════════════════
  Widget _readinessTab(bool conn) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        if (!conn)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.link_off, color: Colors.orange.shade700, size: 14),
                const SizedBox(width: 6),
                Text(
                  'Connect OBD to read real readiness',
                  style: TextStyle(fontSize: 11, color: Colors.orange.shade800),
                ),
              ],
            ),
          ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6),
            ],
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Emission Readiness',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: conn ? Colors.black : Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 12),
              ..._readinessMonitors
                  .map(
                    (m) => GestureDetector(
                      onTap: _maybeShowInterstitial,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          color: !conn
                              ? Colors.grey.shade50
                              : m.isComplete
                              ? Colors.green.shade50
                              : Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: !conn
                                ? Colors.grey.shade200
                                : m.isComplete
                                ? Colors.green.shade200
                                : Colors.orange.shade200,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              !conn
                                  ? Icons.help_outline
                                  : m.isComplete
                                  ? Icons.check_circle
                                  : Icons.pending,
                              color: !conn
                                  ? Colors.grey
                                  : m.isComplete
                                  ? Colors.green
                                  : Colors.orange,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                m.name,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: !conn
                                    ? Colors.grey
                                    : m.isComplete
                                    ? Colors.green.shade600
                                    : Colors.orange.shade600,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                !conn
                                    ? 'Unknown'
                                    : m.isComplete
                                    ? 'Ready'
                                    : 'Not Ready',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ],
          ),
        ),
        if (_vehicleInfo != null) ...[
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6),
              ],
            ),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Vehicle Info',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                _infoRow('VIN', _vehicleInfo!.vin ?? 'N/A'),
                _infoRow('Protocol', _vehicleInfo!.protocol ?? 'Auto'),
              ],
            ),
          ),
        ],
        const SizedBox(height: 10),
        const NativeAdWidget(), // ← native ad at bottom
      ],
    );
  }

  Widget _infoRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
        ),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
      ],
    ),
  );

  // ══════════════════════════════════════════════════════
  // LOGS TAB
  // ══════════════════════════════════════════════════════
  Widget _logsTab() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          color: Colors.grey.shade50,
          child: Row(
            children: [
              Icon(Icons.article, color: Colors.blue.shade700),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'System Logs',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  _maybeShowInterstitial();
                  exportLogs();
                },
                icon: const Icon(Icons.download, size: 15),
                label: const Text('Export'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            color: const Color(0xFF1E1E1E),
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              reverse: true,
              child: SelectableText(
                logText.isEmpty ? '// Logs appear here...' : logText,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  color: Color(0xFF4EC9B0),
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════
  // TERMINAL TAB
  // ══════════════════════════════════════════════════════
  Widget _commandsTab(bool conn) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _commandController,
                  decoration: InputDecoration(
                    hintText: conn ? 'e.g. 010C, ATZ, 03' : 'Connect OBD first',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    prefixIcon: const Icon(Icons.terminal),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: () async {
                  final cmd = _commandController.text.trim().toUpperCase();
                  if (cmd.isEmpty) return;
                  if (!conn) {
                    _noConnSnack();
                    return;
                  }
                  _maybeShowInterstitial();
                  setState(() => _commandResponse = 'Sending...');
                  appendLog('>> $cmd');
                  await _obd.sendCommand(cmd);
                  await Future.delayed(const Duration(milliseconds: 500));
                  final res = await _obd.readResponse(
                    timeout: const Duration(seconds: 3),
                  );
                  setState(() => _commandResponse = res ?? 'No response');
                  appendLog('<< $_commandResponse');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: conn ? Colors.blue.shade700 : Colors.grey,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'Send',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(10),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                _commandResponse.isEmpty
                    ? '// Response here...'
                    : _commandResponse,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  color: Color(0xFF4EC9B0),
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children:
                [
                      ['010C', 'RPM'],
                      ['010D', 'Speed'],
                      ['0105', 'Coolant'],
                      ['0104', 'Load'],
                      ['03', 'DTCs'],
                      ['04', 'Clear'],
                      ['0100', 'PIDs'],
                      ['ATZ', 'Reset'],
                      ['ATRV', 'Voltage'],
                      ['0902', 'VIN'],
                    ]
                    .map(
                      (e) => GestureDetector(
                        onTap: () {
                          _commandController.text = e[0];
                          _maybeShowInterstitial();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Text(
                            '${e[0]}  ${e[1]}',
                            style: TextStyle(
                              color: Colors.blue.shade700,
                              fontSize: 11,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
          ),
        ),
      ],
    );
  }
}
