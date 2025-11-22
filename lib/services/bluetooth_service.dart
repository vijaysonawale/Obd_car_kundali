import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BluetoothService {
  BluetoothCharacteristic? _writeChar;
  BluetoothCharacteristic? _readChar;
  BluetoothDevice? _device;

  Future<List<ScanResult>> scanForDevices() async {
    List<ScanResult> results = [];
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
    await for (final scan in FlutterBluePlus.scanResults) {
      results = scan;
      break;
    }
    await FlutterBluePlus.stopScan();
    return results;
  }

  Future<void> connect(BluetoothDevice device) async {
    _device = device;
    await device.connect(autoConnect: false).catchError((_) {});
    final services = await device.discoverServices();

    for (var s in services) {
      for (var c in s.characteristics) {
        if (c.properties.write) _writeChar = c;
        if (c.properties.notify || c.properties.read) _readChar = c;
      }
    }
  }

  Future<String> sendCommand(String command) async {
    if (_writeChar == null) return "Write characteristic not found";

    final cmd = ascii.encode("$command\r");
    await _writeChar!.write(cmd, withoutResponse: false);

    await Future.delayed(const Duration(milliseconds: 500));

    if (_readChar != null) {
      List<int> value = await _readChar!.read();
      return ascii.decode(value);
    }

    return "No response";
  }
}
