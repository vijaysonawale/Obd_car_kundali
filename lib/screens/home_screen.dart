import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/gatt_obd_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final GattObdService _obd = GattObdService();
  List<ScanResult> scanResults = [];
  BluetoothDevice? connected;
  String logText = '';
  List<String> fullLogs = [];
  StreamSubscription? _scanSubscription;
  StreamSubscription? _adapterSubscription;
  bool _isScanning = false;
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeBluetooth();
    _logToFile('═══════════════════════════════');
    _logToFile('APP STARTED');
    _logToFile('═══════════════════════════════');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkBluetoothState();
    }
  }

  Future<void> _initializeBluetooth() async {
    await _checkBluetoothState();

    _adapterSubscription = FlutterBluePlus.adapterState.listen((state) {
      appendLog('📶 Bluetooth: ${state.name}');
    });
  }

  Future<void> _checkBluetoothState() async {
    try {
      final isSupported = await FlutterBluePlus.isSupported;
      if (!isSupported) {
        appendLog('❌ Bluetooth not supported');
        return;
      }

      final adapterState = await FlutterBluePlus.adapterState.first;
      if (adapterState != BluetoothAdapterState.on) {
        appendLog('⚠️ Bluetooth is OFF');
        if (Platform.isAndroid) {
          try {
            await FlutterBluePlus.turnOn();
          } catch (e) {
            appendLog('Please enable Bluetooth manually');
          }
        }
      } else {
        appendLog('✅ Bluetooth is ON');
      }
    } catch (e) {
      appendLog('Bluetooth check error: $e');
    }
  }

  Future<bool> _requestPermissions() async {
    appendLog('━━━━━━━━━━━━━━━━━━━━━━━━');
    appendLog('🔐 Checking permissions...');

    try {
      if (Platform.isAndroid) {
        var scanStatus = await Permission.bluetoothScan.status;
        if (!scanStatus.isGranted) {
          scanStatus = await Permission.bluetoothScan.request();
        }

        if (scanStatus.isPermanentlyDenied) {
          appendLog('❌ Bluetooth Scan: Permanently Denied');
          await openAppSettings();
          return false;
        } else if (scanStatus.isGranted) {
          appendLog('✅ Bluetooth Scan: Granted');
        }

        var connectStatus = await Permission.bluetoothConnect.status;
        if (!connectStatus.isGranted) {
          connectStatus = await Permission.bluetoothConnect.request();
        }

        if (connectStatus.isPermanentlyDenied) {
          appendLog('❌ Bluetooth Connect: Permanently Denied');
          await openAppSettings();
          return false;
        } else if (connectStatus.isGranted) {
          appendLog('✅ Bluetooth Connect: Granted');
        }

        var locationStatus = await Permission.location.status;
        if (!locationStatus.isGranted) {
          appendLog('📍 Requesting Location permission...');
          locationStatus = await Permission.location.request();
        }

        if (locationStatus.isPermanentlyDenied) {
          appendLog('❌ Location: Permanently Denied');
          await openAppSettings();
          return false;
        } else if (locationStatus.isDenied) {
          appendLog('❌ Location: Denied');
          return false;
        } else if (locationStatus.isGranted) {
          appendLog('✅ Location: Granted');
        }

        final locationService =
            await Permission.locationWhenInUse.serviceStatus;
        if (!locationService.isEnabled) {
          appendLog('❌ LOCATION SERVICES ARE OFF!');
          return false;
        } else {
          appendLog('✅ Location Services: Enabled');
        }

        appendLog('━━━━━━━━━━━━━━━━━━━━━━━━');
        return scanStatus.isGranted &&
            connectStatus.isGranted &&
            locationStatus.isGranted &&
            locationService.isEnabled;
      }

      return true;
    } catch (e) {
      appendLog('❌ Permission error: $e');
      return false;
    }
  }

  Future<void> startScan() async {
    if (_isScanning) {
      appendLog('⚠️ Already scanning...');
      return;
    }

    appendLog('');
    appendLog('═══════════════════════════════');
    appendLog('🔍 STARTING NEW SCAN');
    appendLog('═══════════════════════════════');

    if (!await _requestPermissions()) {
      appendLog('❌ Cannot scan - permissions not granted');
      return;
    }

    try {
      setState(() {
        _isScanning = true;
        scanResults.clear();
      });

      final adapterState = await FlutterBluePlus.adapterState.first;
      appendLog('📶 Bluetooth State: ${adapterState.name}');

      if (adapterState != BluetoothAdapterState.on) {
        appendLog('❌ Bluetooth is OFF!');
        setState(() => _isScanning = false);
        return;
      }

      try {
        if (await FlutterBluePlus.isScanning.first) {
          appendLog('Stopping previous scan...');
          await FlutterBluePlus.stopScan();
          await Future.delayed(const Duration(milliseconds: 500));
        }
      } catch (e) {
        appendLog('Stop scan: $e');
      }

      appendLog('✅ Starting BLE scan (15 seconds)...');

      _scanSubscription?.cancel();
      Set<String> foundDevices = {};

      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (var result in results) {
          final deviceId = result.device.remoteId.str;
          if (!foundDevices.contains(deviceId)) {
            foundDevices.add(deviceId);
            final name = result.device.platformName.isNotEmpty
                ? result.device.platformName
                : '(Unknown)';
            appendLog('📱 Found: $name');
            appendLog('   MAC: $deviceId');
            appendLog('   RSSI: ${result.rssi} dBm');
          }
        }

        setState(() {
          scanResults = results;
        });
      });

      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        androidUsesFineLocation: true,
        androidScanMode: AndroidScanMode.lowLatency,
      );

      await Future.delayed(const Duration(seconds: 15));

      try {
        await FlutterBluePlus.stopScan();
      } catch (e) {
        appendLog('Stop scan error: $e');
      }

      appendLog('');
      appendLog('═══════════════════════════════');
      if (scanResults.isEmpty) {
        appendLog('❌ NO DEVICES FOUND');
      } else {
        appendLog('✅ SCAN COMPLETE');
        appendLog('Total devices found: ${scanResults.length}');
      }
      appendLog('═══════════════════════════════');
    } catch (e) {
      appendLog('❌ Scan error: $e');
    } finally {
      setState(() => _isScanning = false);
    }
  }

  Future<void> connectDevice(BluetoothDevice device) async {
    if (_isConnecting) {
      appendLog('⚠️ Already connecting...');
      return;
    }

    try {
      setState(() => _isConnecting = true);

      final deviceName = device.platformName.isNotEmpty
          ? device.platformName
          : device.remoteId.str;

      appendLog('');
      appendLog('═══════════════════════════════');
      appendLog('🔗 CONNECTING TO DEVICE');
      appendLog('═══════════════════════════════');
      appendLog('Device: $deviceName');
      appendLog('MAC: ${device.remoteId.str}');
      appendLog('');

      // Disconnect if already connected
      try {
        appendLog('[1/7] Checking existing connections...');
        final connectedDevices = await FlutterBluePlus.connectedDevices;
        for (var d in connectedDevices) {
          if (d.remoteId == device.remoteId) {
            appendLog('Device already connected, disconnecting first...');
            await d.disconnect();
            await Future.delayed(const Duration(seconds: 1));
          }
        }
        appendLog('✓ No existing connections');
      } catch (e) {
        appendLog('Disconnect check: $e');
      }

      // Connect
      appendLog('[2/7] Connecting to Bluetooth device...');
      await device.connect(timeout: const Duration(seconds: 15));
      appendLog('✓ Bluetooth connected');
      await Future.delayed(const Duration(milliseconds: 500));

      // Verify connection
      appendLog('[3/7] Verifying connection state...');
      final connectionState = await device.connectionState.first;
      appendLog('Connection state: $connectionState');

      if (connectionState != BluetoothConnectionState.connected) {
        appendLog('❌ Connection failed');
        setState(() => _isConnecting = false);
        return;
      }
      appendLog('✓ Connection verified');

      // Discover services
      appendLog('[4/7] Discovering GATT services...');
      final services = await device.discoverServices();
      appendLog('✓ Found ${services.length} services');

      for (var service in services) {
        appendLog('  Service: ${service.uuid}');
        for (var char in service.characteristics) {
          appendLog('    Char: ${char.uuid}');
          appendLog(
            '      Properties: R:${char.properties.read} W:${char.properties.write} N:${char.properties.notify}',
          );
        }
      }

      // Connect OBD
      appendLog('[5/7] Initializing OBD connection...');
      final ok = await _obd.connect(device);

      if (!ok) {
        appendLog('❌ OBD service connection failed');
        await device.disconnect();
        setState(() => _isConnecting = false);
        return;
      }
      appendLog('✓ OBD service connected');

      // Initialize ELM327
      appendLog('[6/7] Initializing ELM327 adapter...');
      appendLog('Sending ATZ (Reset)...');

      await _obd.sendCommand('ATZ');
      await Future.delayed(const Duration(milliseconds: 1500));
      var response = await _obd.readResponse(
        timeout: const Duration(seconds: 5),
      );
      appendLog('ATZ Response: ${response ?? "TIMEOUT"}');

      if (response == null || response.isEmpty) {
        appendLog('⚠️ WARNING: No response from ELM327');
        appendLog('Continuing anyway...');
      }

      // Additional init
      await Future.delayed(const Duration(milliseconds: 500));
      appendLog('Sending ATE0 (Echo Off)...');
      await _obd.sendCommand('ATE0');
      await Future.delayed(const Duration(milliseconds: 500));
      response = await _obd.readResponse(timeout: const Duration(seconds: 2));
      appendLog('ATE0 Response: ${response ?? "TIMEOUT"}');

      await Future.delayed(const Duration(milliseconds: 500));
      appendLog('Sending ATL0 (Line Feed Off)...');
      await _obd.sendCommand('ATL0');
      await Future.delayed(const Duration(milliseconds: 500));
      response = await _obd.readResponse(timeout: const Duration(seconds: 2));
      appendLog('ATL0 Response: ${response ?? "TIMEOUT"}');

      // Test connection
      appendLog('[7/7] Testing OBD communication...');
      await Future.delayed(const Duration(milliseconds: 500));
      appendLog('Sending 0100 (Supported PIDs)...');
      await _obd.sendCommand('0100');
      await Future.delayed(const Duration(milliseconds: 1000));
      response = await _obd.readResponse(timeout: const Duration(seconds: 3));
      appendLog('0100 Response: ${response ?? "TIMEOUT"}');

      if (response != null &&
          response.isNotEmpty &&
          !response.contains('NO DATA')) {
        appendLog('');
        appendLog('✅ CONNECTION SUCCESSFUL!');
        appendLog('ELM327 is responding correctly');

        connected = device;

        // Listen for data
        _obd.dataStream.listen((data) {
          appendLog('📥 RX: $data');
        });
      } else {
        appendLog('');
        appendLog('⚠️ WARNING: Limited Response');
        appendLog('Bluetooth: Connected ✓');
        appendLog('ELM327: Check connections');

        connected = device;
      }

      appendLog('═══════════════════════════════');
      setState(() {});
    } catch (e) {
      appendLog('❌ CONNECTION ERROR: $e');
      try {
        await device.disconnect();
      } catch (_) {}
    } finally {
      setState(() => _isConnecting = false);
    }
  }

  Future<void> sendCmd(String cmd) async {
    if (connected == null) {
      appendLog('❌ No device connected');
      return;
    }

    try {
      appendLog('');
      appendLog('📤 TX: $cmd');

      await _obd.sendCommand(cmd);
      await Future.delayed(const Duration(milliseconds: 800));

      final res = await _obd.readResponse(timeout: const Duration(seconds: 3));
      if (res != null && res.isNotEmpty) {
        appendLog('📥 RX: $res');

        if (cmd.startsWith('010C')) {
          _parseRPM(res);
        } else if (cmd.startsWith('010D')) {
          _parseSpeed(res);
        } else if (cmd.startsWith('0105')) {
          _parseTemp(res);
        }
      } else {
        appendLog('⏱️ TIMEOUT - No response');
      }
    } catch (e) {
      appendLog('❌ Send error: $e');
    }
  }

  void _parseRPM(String response) {
    try {
      final hex = response
          .replaceAll(' ', '')
          .replaceAll('41', '')
          .replaceAll('0C', '');
      if (hex.length >= 4) {
        final a = int.parse(hex.substring(0, 2), radix: 16);
        final b = int.parse(hex.substring(2, 4), radix: 16);
        final rpm = ((a * 256) + b) / 4;
        appendLog('💡 RPM: ${rpm.toStringAsFixed(0)}');
      }
    } catch (e) {
      appendLog('Parse error: $e');
    }
  }

  void _parseSpeed(String response) {
    try {
      final hex = response
          .replaceAll(' ', '')
          .replaceAll('41', '')
          .replaceAll('0D', '');
      if (hex.length >= 2) {
        final speed = int.parse(hex.substring(0, 2), radix: 16);
        appendLog('💡 Speed: $speed km/h');
      }
    } catch (e) {
      appendLog('Parse error: $e');
    }
  }

  void _parseTemp(String response) {
    try {
      final hex = response
          .replaceAll(' ', '')
          .replaceAll('41', '')
          .replaceAll('05', '');
      if (hex.length >= 2) {
        final temp = int.parse(hex.substring(0, 2), radix: 16) - 40;
        appendLog('💡 Coolant Temp: $temp°C');
      }
    } catch (e) {
      appendLog('Parse error: $e');
    }
  }

  void appendLog(String s) {
    setState(() {
      final timestamp = DateTime.now().toIso8601String().substring(11, 23);
      final logLine = '[$timestamp] $s';
      logText = '$logLine\n$logText';
      fullLogs.add(logLine);

      if (logText.length > 15000) {
        logText = logText.substring(0, 12000);
      }
    });
  }

  Future<void> _logToFile(String message) async {
    try {
      final timestamp = DateTime.now().toIso8601String().substring(11, 23);
      fullLogs.add('[$timestamp] $message');
    } catch (e) {
      print('Log file error: $e');
    }
  }

  Future<void> _exportLogs() async {
    try {
      appendLog('📝 Exporting logs...');

      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .substring(0, 19);
      final file = File('${directory.path}/obd_log_$timestamp.txt');

      final header =
          '''
═══════════════════════════════════════════════════════
CAR KUNDALI - OBD SCANNER LOG
═══════════════════════════════════════════════════════
Generated: ${DateTime.now()}
Device: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}
App Version: 1.0.0
═══════════════════════════════════════════════════════

''';

      await file.writeAsString(header + fullLogs.join('\n'));

      appendLog('✅ Log saved to: ${file.path}');

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Car Kundali OBD Log - $timestamp',
        text: 'OBD Scanner Debug Log',
      );

      appendLog('📤 Log file shared');
    } catch (e) {
      appendLog('❌ Export error: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scanSubscription?.cancel();
    _adapterSubscription?.cancel();
    _obd.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Car Kundali - OBD Scanner'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download),
            onPressed: _exportLogs,
            tooltip: 'Export Logs',
          ),
        ],
      ),
      body: Column(
        children: [
          // Top Action Bar
          Container(
            color: Colors.blue.shade700,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isScanning ? null : startScan,
                    icon: _isScanning
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.blue,
                            ),
                          )
                        : const Icon(Icons.search, size: 20),
                    label: Text(_isScanning ? 'Scanning...' : 'Scan Devices'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.blue.shade700,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: connected == null
                      ? null
                      : () async {
                          appendLog('🔌 Disconnecting...');
                          await _obd.disconnect();
                          await connected?.disconnect();
                          setState(() {
                            connected = null;
                          });
                          appendLog('✓ Disconnected');
                        },
                  icon: const Icon(Icons.bluetooth_disabled, size: 20),
                  label: const Text('Disconnect'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _exportLogs,
                  icon: const Icon(Icons.save_alt, size: 20),
                  label: const Text('Export'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Connection Status
          if (connected != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.green.shade400, Colors.green.shade600],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.green.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.3),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.bluetooth_connected,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Connected',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          connected!.platformName.isNotEmpty
                              ? connected!.platformName
                              : connected!.remoteId.str,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else if (_isConnecting)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade300, width: 2),
              ),
              child: const Row(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Connecting to device...',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                ],
              ),
            ),

          // Main Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  // Activity Log - Top Priority
                  Expanded(
                    flex: 1,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.grey.shade700,
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          // Header
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade900,
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(10),
                                topRight: Radius.circular(10),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.article,
                                  color: Colors.green.shade400,
                                  size: 22,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Activity Log',
                                  style: TextStyle(
                                    color: Colors.green.shade400,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const Spacer(),
                                IconButton(
                                  icon: const Icon(
                                    Icons.clear,
                                    color: Colors.white70,
                                    size: 20,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      logText = '';
                                    });
                                    appendLog('🗑️ Display cleared');
                                  },
                                  tooltip: 'Clear Display',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ],
                            ),
                          ),
                          // Log Content
                          Expanded(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(12),
                              reverse: false,
                              child: Text(
                                logText.isEmpty
                                    ? 'Waiting for activity...\n\nTap "Scan Devices" to start.'
                                    : logText,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  color: logText.isEmpty
                                      ? Colors.grey.shade600
                                      : Colors.green.shade300,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Bottom Row: Devices and Commands
                  Expanded(
                    flex: 1,
                    child: Row(
                      children: [
                        // Bluetooth Devices List
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                // Header
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    borderRadius: const BorderRadius.only(
                                      topLeft: Radius.circular(10),
                                      topRight: Radius.circular(10),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.devices_other,
                                        color: Colors.blue.shade700,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Devices (${scanResults.length})',
                                        style: TextStyle(
                                          color: Colors.blue.shade700,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Device List
                                Expanded(
                                  child: scanResults.isEmpty
                                      ? Center(
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                Icons.bluetooth_searching,
                                                size: 48,
                                                color: Colors.grey.shade400,
                                              ),
                                              const SizedBox(height: 12),
                                              Text(
                                                'No devices found',
                                                style: TextStyle(
                                                  color: Colors.grey.shade600,
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                      : ListView.builder(
                                          padding: const EdgeInsets.all(8),
                                          itemCount: scanResults.length,
                                          itemBuilder: (context, i) {
                                            final r = scanResults[i];
                                            final name =
                                                r
                                                    .advertisementData
                                                    .advName
                                                    .isNotEmpty
                                                ? r.advertisementData.advName
                                                : (r
                                                          .device
                                                          .platformName
                                                          .isNotEmpty
                                                      ? r.device.platformName
                                                      : r.device.remoteId.str);

                                            final isConnected =
                                                connected?.remoteId ==
                                                r.device.remoteId;

                                            return Card(
                                              elevation: isConnected ? 4 : 1,
                                              margin: const EdgeInsets.only(
                                                bottom: 8,
                                              ),
                                              color: isConnected
                                                  ? Colors.green.shade50
                                                  : Colors.white,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                side: BorderSide(
                                                  color: isConnected
                                                      ? Colors.green
                                                      : Colors.transparent,
                                                  width: 2,
                                                ),
                                              ),
                                              child: ListTile(
                                                dense: true,
                                                contentPadding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 4,
                                                    ),
                                                leading: Container(
                                                  padding: const EdgeInsets.all(
                                                    8,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: isConnected
                                                        ? Colors.green.shade100
                                                        : Colors.blue.shade50,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                  ),
                                                  child: Icon(
                                                    Icons.bluetooth,
                                                    color: isConnected
                                                        ? Colors.green
                                                        : Colors.blue,
                                                    size: 20,
                                                  ),
                                                ),
                                                title: Text(
                                                  name,
                                                  style: TextStyle(
                                                    fontWeight: isConnected
                                                        ? FontWeight.bold
                                                        : FontWeight.w600,
                                                    fontSize: 14,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                                subtitle: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      r.device.remoteId.str,
                                                      style: const TextStyle(
                                                        fontSize: 11,
                                                      ),
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Row(
                                                      children: [
                                                        Icon(
                                                          Icons
                                                              .signal_cellular_alt,
                                                          size: 12,
                                                          color: r.rssi > -70
                                                              ? Colors.green
                                                              : Colors.orange,
                                                        ),
                                                        const SizedBox(
                                                          width: 4,
                                                        ),
                                                        Text(
                                                          '${r.rssi} dBm',
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            color: r.rssi > -70
                                                                ? Colors.green
                                                                : Colors.orange,
                                                            fontWeight:
                                                                FontWeight.w500,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                                trailing: ElevatedButton(
                                                  onPressed:
                                                      (isConnected ||
                                                          _isConnecting)
                                                      ? null
                                                      : () => connectDevice(
                                                          r.device,
                                                        ),
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: isConnected
                                                        ? Colors.green
                                                        : Colors.blue.shade700,
                                                    foregroundColor:
                                                        Colors.white,
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 12,
                                                          vertical: 8,
                                                        ),
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                    ),
                                                  ),
                                                  child: Text(
                                                    isConnected
                                                        ? 'Active'
                                                        : 'Connect',
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(width: 12),
                      ],
                    ),
                  ),
                  // OBD Commands
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          // Header
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(10),
                                topRight: Radius.circular(10),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.terminal,
                                  color: Colors.orange.shade700,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'OBD Commands',
                                  style: TextStyle(
                                    color: Colors.orange.shade700,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Commands
                          Expanded(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _buildCommandCard(
                                    'ATZ',
                                    'Reset Adapter',
                                    Icons.refresh,
                                    Colors.blue,
                                    connected != null && !_isConnecting,
                                  ),
                                  const SizedBox(height: 8),
                                  _buildCommandCard(
                                    'ATE0',
                                    'Echo Off',
                                    Icons.speaker_notes_off,
                                    Colors.purple,
                                    connected != null && !_isConnecting,
                                  ),
                                  const SizedBox(height: 8),
                                  _buildCommandCard(
                                    'ATSP0',
                                    'Auto Protocol',
                                    Icons.settings_ethernet,
                                    Colors.indigo,
                                    connected != null && !_isConnecting,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Vehicle Data',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  _buildCommandCard(
                                    '010C',
                                    'Engine RPM',
                                    Icons.speed,
                                    Colors.red,
                                    connected != null && !_isConnecting,
                                  ),
                                  const SizedBox(height: 8),
                                  _buildCommandCard(
                                    '010D',
                                    'Vehicle Speed',
                                    Icons.directions_car,
                                    Colors.green,
                                    connected != null && !_isConnecting,
                                  ),
                                  const SizedBox(height: 8),
                                  _buildCommandCard(
                                    '0105',
                                    'Coolant Temp',
                                    Icons.thermostat,
                                    Colors.orange,
                                    connected != null && !_isConnecting,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommandCard(
    String cmd,
    String label,
    IconData icon,
    Color color,
    bool enabled,
  ) {
    return InkWell(
      onTap: enabled ? () => sendCmd(cmd) : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: enabled ? color.withOpacity(0.1) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: enabled ? color.withOpacity(0.3) : Colors.grey.shade300,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: enabled ? color.withOpacity(0.2) : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: enabled ? color : Colors.grey),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: enabled ? Colors.black87 : Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    cmd,
                    style: TextStyle(
                      fontSize: 11,
                      color: enabled
                          ? Colors.grey.shade600
                          : Colors.grey.shade400,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.play_arrow,
              size: 18,
              color: enabled ? color : Colors.grey,
            ),
          ],
        ),
      ),
    );
  }
}
