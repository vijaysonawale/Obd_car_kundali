// lib/screens/home_screen.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
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
import 'live_data_screen.dart';
import 'dtc_screen.dart';
import '../widgets/exit_dialog.dart';
import '../theme/app_theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const _playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.nextintinc.car_kundali';
  final GattObdService _obd = GattObdService();
  final DataLogger _dataLogger = DataLogger();

  // ─── BLE ──────────────────────────────────────────────
  List<ScanResult> scanResults = [];
  BluetoothDevice? connected;
  StreamSubscription? _scanSub, _adapterSub, _obdDataSub, _deviceStateSub;
  bool _isScanning = false,
      _isConnecting = false,
      _isDisconnecting = false,
      _isRefreshing = false,
      _isLogging = false;
  String? _connectingDeviceId;
  final ValueNotifier<int> _deviceSheetTick = ValueNotifier(0);

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
  DateTime? _lastObdDataAt;

  // ─── VEHICLE STATE ────────────────────────────────────
  List<ReadinessMonitor> _readinessMonitors = _defaultReadiness();
  List<DtcModel> _dtcList = [];
  final ValueNotifier<List<DtcModel>> _dtcNotifier = ValueNotifier([]);
  VehicleInfo? _vehicleInfo;

  // ─── LOGS ─────────────────────────────────────────────
  String logText = '';
  final List<String> fullLogs = [];

  // ─── UI ───────────────────────────────────────────────
  late final TabController _tabs;
  int _navIndex = 0;
  Timer? _autoRefreshTimer;
  final TextEditingController _commandController = TextEditingController();
  String _commandResponse = '';

  late final List<String> _monitoredPids = ObdPidDatabase.pids.keys.toList();

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
    _tabs = TabController(length: 4, vsync: this);
    _tabs.addListener(_syncNavIndex);
    _initializeBluetooth();
    _logLocal('Car Kundali Pro started');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scanSub?.cancel();
    _adapterSub?.cancel();
    _obdDataSub?.cancel();
    _deviceStateSub?.cancel();
    _autoRefreshTimer?.cancel();
    _tabs.removeListener(_syncNavIndex);
    _tabs.dispose();
    _commandController.dispose();
    _deviceSheetTick.dispose();
    _valuesNotifier.dispose();
    _dtcNotifier.dispose();
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

  void _syncNavIndex() {
    if (!mounted || _navIndex == _tabs.index) return;
    setState(() => _navIndex = _tabs.index);
  }

  void _selectNav(int index) {
    _maybeShowInterstitial();
    setState(() => _navIndex = index);
    _tabs.animateTo(index);
  }

  void _showDeviceSheet() {
    _maybeShowInterstitial();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => ValueListenableBuilder<int>(
        valueListenable: _deviceSheetTick,
        builder: (context, _, __) {
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.72,
            minChildSize: 0.42,
            maxChildSize: 0.92,
            builder: (context, controller) {
              return Column(
                children: [
                  Container(
                    width: 42,
                    height: 4,
                    margin: const EdgeInsets.only(top: 10, bottom: 8),
                    decoration: BoxDecoration(
                      color: AppColors.line,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Connect OBD adapter',
                            style: TextStyle(
                              color: AppColors.text,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  Expanded(child: _devicesTab(controller: controller)),
                ],
              );
            },
          );
        },
      ),
    );
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
    _notifyDeviceSheet();
    appendLog('🔍 Scanning...');
    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      final ids = scanResults.map((e) => e.device.remoteId.str).toSet();
      for (final r in results) {
        if (!ids.contains(r.device.remoteId.str)) {
          setState(() => scanResults.add(r));
          ids.add(r.device.remoteId.str);
          _notifyDeviceSheet();
        }
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
    _notifyDeviceSheet();
    appendLog('✅ Found ${scanResults.length} device(s)');
  }

  void _notifyDeviceSheet() {
    if (!mounted) return;
    _deviceSheetTick.value++;
  }

  String _deviceName(ScanResult r) {
    if (r.advertisementData.advName.isNotEmpty)
      return r.advertisementData.advName;
    if (r.device.platformName.isNotEmpty) return r.device.platformName;
    return 'Unknown Device';
  }

  Future<void> connectDevice(BluetoothDevice device) async {
    if (_isConnecting) return;
    setState(() {
      _isConnecting = true;
      _connectingDeviceId = device.remoteId.str;
    });
    _notifyDeviceSheet();
    final match = scanResults.where(
      (r) => r.device.remoteId == device.remoteId,
    );
    final name = match.isNotEmpty
        ? _deviceName(match.first)
        : device.platformName;
    appendLog('🔗 Connecting to $name...');
    try {
      try {
        await device.disconnect();
      } catch (_) {}
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
      _watchDeviceConnection(device);
      _notifyDeviceSheet();
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
      setState(() {
        _isConnecting = false;
        _connectingDeviceId = null;
      });
      _notifyDeviceSheet();
    }
  }

  void _watchDeviceConnection(BluetoothDevice device) {
    _deviceStateSub?.cancel();
    _deviceStateSub = device.connectionState.listen((state) {
      if (state != BluetoothConnectionState.disconnected) return;
      if (_isDisconnecting || connected?.remoteId != device.remoteId) return;
      _handleUnexpectedDisconnect();
    });
  }

  Future<void> _handleUnexpectedDisconnect({
    String message = 'OBD disconnected. Live data and DTCs cleared.',
  }) async {
    if (!mounted || connected == null) return;
    appendLog('⚠️ OBD connection lost');
    _autoRefreshTimer?.cancel();
    await _obdDataSub?.cancel();
    await _deviceStateSub?.cancel();
    _deviceStateSub = null;
    await _obd.disconnect();
    _clearConnectionState();
    _notifyDeviceSheet();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 3),
      ),
    );
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
    _lastObdDataAt = DateTime.now();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (connected != null && mounted && !_isRefreshing) _refreshPids();
    });
  }

  Future<void> _refreshPids() async {
    if (_isConnecting || _isDisconnecting || _isRefreshing) return;
    _isRefreshing = true;
    try {
      for (final pid in _monitoredPids) {
        if (connected == null) return;
        try {
          await _obd.sendCommand(pid);
          await Future.delayed(const Duration(milliseconds: 90));
        } catch (_) {}
      }
      final lastData = _lastObdDataAt;
      if (connected != null &&
          lastData != null &&
          DateTime.now().difference(lastData) > const Duration(seconds: 15)) {
        await _handleObdTimeout();
      }
    } finally {
      _isRefreshing = false;
    }
  }

  Future<void> _handleObdTimeout() async {
    if (!mounted || connected == null || _isDisconnecting) return;
    appendLog('⚠️ No OBD data. Disconnecting.');
    await _handleUnexpectedDisconnect(
      message: 'No OBD data received. Connection cleared.',
    );
  }

  // ══════════════════════════════════════════════════════
  // DATA PROCESSING
  // ══════════════════════════════════════════════════════
  void _processObdResponse(String raw) {
    _lastObdDataAt = DateTime.now();
    final parts = _hexBytes(raw);
    for (final entry in ObdPidDatabase.pids.entries) {
      final pid = entry.value;
      final idx = _responseIndex(parts, pid.pid);
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

  List<String> _hexBytes(String raw) {
    final cleaned = _cleanHex(raw);
    final bytes = <String>[];
    for (final token in cleaned.split(' ')) {
      if (token.length == 2) {
        bytes.add(token);
      } else if (token.length > 2 && token.length.isEven) {
        for (var i = 0; i + 1 < token.length; i += 2) {
          bytes.add(token.substring(i, i + 2));
        }
      }
    }
    return bytes;
  }

  int _responseIndex(List<String> parts, String pid) {
    for (var i = 0; i + 1 < parts.length; i++) {
      if (parts[i] == '41' && parts[i + 1] == pid) return i;
    }
    return -1;
  }

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
  Future<void> scanDTC({bool showResultDialog = true}) async {
    _maybeShowInterstitial();
    if (connected == null) {
      _noConnSnack();
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Scanning DTCs...'),
          duration: Duration(seconds: 1),
        ),
      );
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
    _dtcNotifier.value = List.unmodifiable(dtcs);
    appendLog('Found ${dtcs.length} DTC(s)');
    if (!mounted) return;
    if (dtcs.isNotEmpty && showResultDialog) {
      _showDtcDialog(dtcs);
    } else if (dtcs.isEmpty && showResultDialog) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ No trouble codes!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> clearDTC({bool rescanAfterClear = true}) async {
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
    _dtcNotifier.value = const [];
    if (rescanAfterClear) await scanDTC(showResultDialog: false);
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
  void _clearConnectionState() {
    if (!mounted) return;
    setState(() {
      connected = null;
      _isLogging = false;
      _dtcList = [];
      _vehicleInfo = null;
      _isRefreshing = false;
      _lastObdDataAt = null;
      _currentValues.clear();
      _liveDataHistory.clear();
      _alertsSent.clear();
      _readinessMonitors = _defaultReadiness();
    });
    _valuesNotifier.value = {};
    _dtcNotifier.value = const [];
  }

  Future<void> disconnectDevice() async {
    if (_isDisconnecting) return;
    _isDisconnecting = true;
    _autoRefreshTimer?.cancel();
    await _obdDataSub?.cancel();
    await _deviceStateSub?.cancel();
    _deviceStateSub = null;
    try {
      await _obd.disconnect();
      await connected?.disconnect();
    } catch (_) {
    } finally {
      _clearConnectionState();
      _isDisconnecting = false;
      _notifyDeviceSheet();
      appendLog('✓ Disconnected');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Disconnected. Live data and DTCs cleared.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
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

  Future<void> shareApp() async {
    _maybeShowInterstitial();
    await Share.share(
      'Try Car Kundali Pro for OBD diagnostics, live car data, DTC scan/clear, trip stats, and vehicle health checks.\n\nDownload it here:\n$_playStoreUrl',
      subject: 'Car Kundali Pro - OBD diagnostics app',
    );
  }

  Future<void> requestReview() async {
    _maybeShowInterstitial();
    try {
      final review = InAppReview.instance;
      if (await review.isAvailable()) {
        await review.requestReview();
      } else {
        await review.openStoreListing();
      }
    } catch (e) {
      appendLog('Review failed: $e');
      await Share.share(_playStoreUrl);
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
    return PopScope(
      canPop: false, // ← intercept back button
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldExit = await ExitDialog.show(context);
        if (shouldExit && context.mounted) {
          SystemNavigator.pop(); // exits app cleanly on Android
        }
      },

      child: Scaffold(
        backgroundColor: AppColors.ink,
        appBar: AppBar(
          backgroundColor: AppColors.ink,
          surfaceTintColor: Colors.transparent,
          title: Row(
            children: [
              const Icon(Icons.directions_car, color: AppColors.blue),
              const SizedBox(width: 8),
              const Text('Car Kundali'),
              if (_isLogging) ...[const SizedBox(width: 8), _blinkDot()],
            ],
          ),
          foregroundColor: AppColors.text,
          elevation: 0,
          actions: [
            if (conn)
              IconButton(
                tooltip: 'Disconnect adapter',
                onPressed: disconnectDevice,
                icon: const Icon(Icons.bluetooth_disabled),
                color: AppColors.red,
              ),
            if (conn)
              IconButton(
                onPressed: toggleLogging,
                icon: Icon(
                  _isLogging ? Icons.stop_circle : Icons.fiber_manual_record,
                ),
                color: _isLogging ? AppColors.red : AppColors.text,
              ),
          ],
        ),
        body: Column(
          children: [
            const BannerAdWidget(), // ← banner always
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _overviewTab(conn),
                  _dtcTab(conn),
                  _liveDataTab(conn),
                  _moreTab(conn),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _navIndex,
          onDestinationSelected: _selectNav,
          height: 72,
          backgroundColor: AppColors.panel,
          indicatorColor: AppColors.blue.withOpacity(0.16),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.car_repair_outlined),
              selectedIcon: Icon(Icons.car_repair),
              label: 'DTC',
            ),
            NavigationDestination(
              icon: Icon(Icons.monitor_heart_outlined),
              selectedIcon: Icon(Icons.monitor_heart),
              label: 'Live',
            ),
            NavigationDestination(
              icon: Icon(Icons.more_horiz),
              selectedIcon: Icon(Icons.more_horiz),
              label: 'More',
            ),
          ],
        ),
      ),
    );
  }

  Widget _overviewTab(bool conn) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        _homeSummary(conn),
        const SizedBox(height: 10),
        _connectionAction(conn),
        const SizedBox(height: 10),
        _primaryActions(conn),
        const SizedBox(height: 10),
        _sectionTitle('Live essentials'),
        const SizedBox(height: 10),
        _wideMetricGrid(conn),
        const SizedBox(height: 10),
        _readinessCompact(conn),
      ],
    );
  }

  Widget _homeSummary(bool conn) {
    final codeCount = _dtcList.length;
    final hasCodes = codeCount > 0;
    final color = !conn
        ? AppColors.blue
        : hasCodes
        ? AppColors.red
        : AppColors.green;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  !conn
                      ? Icons.bluetooth_searching
                      : hasCodes
                      ? Icons.warning_amber
                      : Icons.verified_outlined,
                  color: color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      !conn
                          ? 'Ready to connect'
                          : hasCodes
                          ? 'DTC found'
                          : 'Vehicle looks okay',
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      conn
                          ? codeCount == 0
                                ? 'Connected. No stored DTCs in current scan.'
                                : '$codeCount trouble code${codeCount == 1 ? '' : 's'} found.'
                          : 'Connect your OBD adapter to start scanning.',
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _summaryMetric(
                  'RPM',
                  conn ? _val('010C').toStringAsFixed(0) : '--',
                  'rpm',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _summaryMetric(
                  'Speed',
                  conn ? _val('010D').toStringAsFixed(0) : '--',
                  'km/h',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryMetric(String label, String value, String unit) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.panelSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              fontFamily: 'monospace',
            ),
          ),
          Text(
            unit,
            style: const TextStyle(color: AppColors.muted, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _connectionAction(bool conn) {
    final deviceName = connected?.platformName.isNotEmpty == true
        ? connected!.platformName
        : 'OBD adapter';

    return Material(
      color: conn ? AppColors.green.withOpacity(0.12) : AppColors.panel,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: conn ? disconnectDevice : _showDeviceSheet,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minHeight: 58),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: conn ? AppColors.green.withOpacity(0.45) : AppColors.line,
            ),
          ),
          child: Row(
            children: [
              Icon(
                conn ? Icons.bluetooth_connected : Icons.bluetooth_searching,
                color: conn ? AppColors.green : AppColors.blue,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      conn ? 'Connected: $deviceName' : 'Disconnected',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      conn
                          ? 'Tap to disconnect and clear current data'
                          : 'Tap to scan and connect adapter',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                conn ? Icons.power_settings_new : Icons.chevron_right,
                color: conn ? AppColors.red : AppColors.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.text,
        fontSize: 16,
        fontWeight: FontWeight.w900,
      ),
    );
  }

  Widget _cockpitReadouts(bool conn) {
    return Row(
      children: [
        Expanded(
          child: _bigReadout(
            label: 'Engine',
            value: _val('010C').toStringAsFixed(0),
            unit: 'rpm',
            icon: Icons.settings_input_component,
            color: AppColors.blue,
            live: conn,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _bigReadout(
            label: 'Speed',
            value: _val('010D').toStringAsFixed(0),
            unit: 'km/h',
            icon: Icons.speed,
            color: AppColors.green,
            live: conn,
          ),
        ),
      ],
    );
  }

  Widget _bigReadout({
    required String label,
    required String value,
    required String unit,
    required IconData icon,
    required Color color,
    required bool live,
  }) {
    return Container(
      height: 172,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: live ? color.withOpacity(0.44) : AppColors.line,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: live ? color : AppColors.muted, size: 22),
              const Spacer(),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: live ? AppColors.green : AppColors.muted,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              live ? value : '--',
              style: TextStyle(
                color: live ? AppColors.text : AppColors.muted,
                fontSize: 54,
                fontWeight: FontWeight.w900,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$label  /  $unit',
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _primaryActions(bool conn) {
    return Row(
      children: [
        Expanded(
          child: _overviewAction(
            icon: conn ? Icons.manage_search : Icons.bluetooth_searching,
            label: conn ? 'Scan DTC' : 'Connect device',
            color: conn ? AppColors.red : AppColors.blue,
            onTap: conn ? () => scanDTC() : _showDeviceSheet,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _overviewAction(
            icon: _isLogging
                ? Icons.stop_circle_outlined
                : Icons.radio_button_checked,
            label: _isLogging ? 'Stop Log' : 'Start Log',
            color: _isLogging ? AppColors.red : AppColors.green,
            onTap: conn ? toggleLogging : _noConnSnack,
          ),
        ),
      ],
    );
  }

  Widget _readinessCompact(bool conn) {
    final supported = _readinessMonitors.where((m) => m.isSupported).length;
    final ready = _readinessMonitors
        .where((m) => m.isSupported && m.isComplete)
        .length;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Icon(
            conn ? Icons.verified_outlined : Icons.link_off,
            color: conn ? AppColors.green : AppColors.muted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              conn
                  ? 'Readiness monitors: $ready/$supported ready'
                  : 'Readiness available after connection',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _overviewAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppColors.panel,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.34)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _wideMetricGrid(bool conn) {
    final metrics = [
      (
        'Coolant',
        _val('0105').toStringAsFixed(0),
        'C',
        _val('0105') > 100 ? AppColors.red : AppColors.amber,
      ),
      ('Load', _val('0104').toStringAsFixed(0), '%', AppColors.blue),
      ('MAF', _val('0110').toStringAsFixed(1), 'g/s', AppColors.green),
      ('Voltage', _val('0142').toStringAsFixed(1), 'V', AppColors.amber),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: metrics.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 2.4,
      ),
      itemBuilder: (context, index) {
        final item = metrics[index];
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.panelSoft,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  item.$1,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ),
              Text(
                conn ? '${item.$2} ${item.$3}' : '--',
                style: TextStyle(
                  color: conn ? item.$4 : AppColors.muted,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        );
      },
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
        conn ? disconnectDevice() : _showDeviceSheet();
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: conn
                ? [AppColors.green, const Color(0xFF159B76)]
                : [AppColors.panelSoft, AppColors.panel],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: conn ? AppColors.green : AppColors.line),
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
                ? [color.withOpacity(0.86), color.withOpacity(0.58)]
                : [AppColors.panelSoft, AppColors.panel],
          ),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: live ? color.withOpacity(0.3) : AppColors.line,
          ),
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
                color: Colors.white.withOpacity(0.78),
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
  Widget _buildFeatureGrid(bool conn) {
    return SizedBox(
      height: 86,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        children: [
          _fCard(
            Icons.speed,
            'Dashboard',
            'Gauges',
            AppColors.blue,
            () => _navigate(DashboardScreen(valuesNotifier: _valuesNotifier)),
          ),
          _fCard(
            Icons.car_repair,
            'DTC',
            _dtcList.isEmpty ? 'Scan ECU' : '${_dtcList.length} codes',
            _dtcList.isEmpty ? AppColors.green : AppColors.red,
            () => _navigate(
              DtcScreen(
                dtcNotifier: _dtcNotifier,
                liveValues: _currentValues,
                isConnected: conn,
                onScan: () => scanDTC(),
                onClear: () => clearDTC(rescanAfterClear: true),
              ),
            ),
          ),
          _fCard(
            Icons.health_and_safety_outlined,
            'Health',
            _dtcList.isEmpty ? 'All OK' : '${_dtcList.length} codes',
            AppColors.green,
            () => _navigate(
              HealthScreen(
                dtcList: _dtcList,
                liveValues: _currentValues,
                readinessMonitors: _readinessMonitors,
              ),
            ),
          ),
          _fCard(
            Icons.route_outlined,
            'Trip',
            '${_tripDistanceKm.toStringAsFixed(1)} km',
            AppColors.amber,
            () => _navigate(TripScreen(tripData: _tripData)),
          ),
          _fCard(
            Icons.bolt,
            'Perf',
            '0-100',
            AppColors.red,
            () => _navigate(PerformanceScreen(valuesNotifier: _valuesNotifier)),
          ),
        ],
      ),
    );
  }

  Widget _fCard(
    IconData icon,
    String title,
    String sub,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 112,
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const Spacer(),
            Text(
              title,
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              sub,
              style: TextStyle(
                fontSize: 10,
                color: color,
                fontWeight: FontWeight.w700,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
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
                backgroundColor: AppColors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
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
                backgroundColor: AppColors.amber,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
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
              backgroundColor: AppColors.panelSoft,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: AppColors.line),
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
        color: AppColors.panel,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
        border: Border.all(color: AppColors.line),
      ),
      child: TabBar(
        controller: _tabs,
        labelColor: AppColors.blue,
        unselectedLabelColor: AppColors.muted,
        indicatorColor: AppColors.blue,
        indicatorWeight: 3,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
        onTap: (_) => _maybeShowInterstitial(), // ← ad on tab switch
        tabs: const [
          Tab(icon: Icon(Icons.bluetooth, size: 18), text: 'Devices'),
          Tab(icon: Icon(Icons.car_repair, size: 18), text: 'DTC'),
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
  Widget _devicesTab({ScrollController? controller}) {
    return ListView(
      controller: controller,
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
          final isThisDeviceConnecting =
              _connectingDeviceId == r.device.remoteId.str;
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
              trailing: isThisDeviceConnecting
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

  Widget _dtcTab(bool conn) {
    return DtcScreen(
      dtcNotifier: _dtcNotifier,
      liveValues: _currentValues,
      isConnected: conn,
      onScan: () => scanDTC(),
      onClear: () => clearDTC(rescanAfterClear: true),
      showAppBar: false,
    );
  }

  Widget _moreTab(bool conn) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: _utilityTile(
                    icon: Icons.ios_share,
                    label: 'Share App',
                    onTap: shareApp,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _utilityTile(
                    icon: Icons.star_rate,
                    label: 'Rate App',
                    onTap: requestReview,
                  ),
                ),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            decoration: BoxDecoration(
              color: AppColors.panel,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.line),
            ),
            child: const TabBar(
              labelColor: AppColors.blue,
              unselectedLabelColor: AppColors.muted,
              indicatorColor: AppColors.blue,
              tabs: [
                Tab(icon: Icon(Icons.verified_outlined), text: 'Ready'),
                Tab(icon: Icon(Icons.article_outlined), text: 'Logs'),
                Tab(icon: Icon(Icons.terminal), text: 'Terminal'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [_readinessTab(conn), _logsTab(), _commandsTab(conn)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _utilityTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppColors.panel,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 50,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: AppColors.blue, size: 19),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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
            valuesNotifier: _valuesNotifier,
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: AppColors.panel,
          child: Row(
            children: [
              const Icon(Icons.article, color: AppColors.blue),
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
                  backgroundColor: AppColors.blue,
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
            width: double.infinity,
            color: AppColors.panel,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SingleChildScrollView(
              reverse: true,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0B1220),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF1F2937)),
                ),
                child: SelectableText(
                  logText.isEmpty ? '// Logs appear here...' : logText,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    color: Color(0xFF7DD3FC),
                    fontSize: 12,
                    height: 1.45,
                  ),
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
        Container(
          width: double.infinity,
          color: AppColors.panel,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
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
                  backgroundColor: conn ? AppColors.blue : AppColors.muted,
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
            width: double.infinity,
            color: AppColors.panel,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SingleChildScrollView(
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 220),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0B1220),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF1F2937)),
                ),
                child: SelectableText(
                  _commandResponse.isEmpty
                      ? '// Response will appear here...'
                      : _commandResponse,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    color: Color(0xFF86EFAC),
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ),
            ),
          ),
        ),
        Container(
          width: double.infinity,
          color: AppColors.panel,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
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
                            color: AppColors.panelSoft,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.line),
                          ),
                          child: Text(
                            '${e[0]}  ${e[1]}',
                            style: const TextStyle(
                              color: AppColors.blue,
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
