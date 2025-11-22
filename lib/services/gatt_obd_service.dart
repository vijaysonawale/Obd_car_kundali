import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class GattObdService {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _txCharacteristic;
  BluetoothCharacteristic? _rxCharacteristic;
  
  final StreamController<String> _dataController = StreamController<String>.broadcast();
  Stream<String> get dataStream => _dataController.stream;
  
  StreamSubscription? _notificationSubscription;
  String _buffer = '';
  List<int> _rawBuffer = [];

  /// Connect to device and find OBD characteristics
  Future<bool> connect(BluetoothDevice device) async {
    try {
      _device = device;
      
      print('[OBD] ═══════════════════════════════');
      print('[OBD] Starting OBD connection process');
      print('[OBD] ═══════════════════════════════');
      
      // Get services (already discovered)
      print('[OBD] Getting services...');
      List<BluetoothService> services = await device.discoverServices();
      print('[OBD] Found ${services.length} services');
      
      // Find OBD service - look for fff0 first (your device uses this)
      BluetoothService? obdService;
      
      for (var service in services) {
        final uuid = service.uuid.toString().toLowerCase();
        print('[OBD] Service: $uuid');
        
        if (uuid.contains('fff0') || 
            uuid.contains('ffe0') ||
            uuid.contains('e7810a71') ||
            uuid.contains('fef3')) {
          obdService = service;
          print('[OBD] ✓ Found OBD service: $uuid');
          break;
        }
      }
      
      if (obdService == null) {
        print('[OBD] ❌ No OBD service found, trying first available service');
        if (services.length > 2) {
          obdService = services[2]; // Skip Generic Access and Generic Attribute
        }
      }
      
      if (obdService == null) {
        print('[OBD] ❌ No suitable service found');
        return false;
      }
      
      print('[OBD] Using service: ${obdService.uuid}');
      print('[OBD] Analyzing characteristics...');
      
      // Analyze all characteristics
      for (var char in obdService.characteristics) {
        final uuid = char.uuid.toString().toLowerCase();
        print('[OBD] ─────────────────────────────');
        print('[OBD] Char UUID: $uuid');
        print('[OBD]   Read: ${char.properties.read}');
        print('[OBD]   Write: ${char.properties.write}');
        print('[OBD]   WriteWithoutResponse: ${char.properties.writeWithoutResponse}');
        print('[OBD]   Notify: ${char.properties.notify}');
        print('[OBD]   Indicate: ${char.properties.indicate}');
        
        // For fff0 service (your device):
        // fff1 = Write + Notify (this is BOTH TX and RX!)
        // fff2 = Write only
        
        if (uuid.contains('fff1')) {
          // This characteristic has BOTH write and notify
          // Use it for BOTH sending and receiving
          _txCharacteristic = char;
          _rxCharacteristic = char;
          print('[OBD] ✓ Using fff1 for BOTH TX and RX');
        } else if (uuid.contains('fff2') && _txCharacteristic == null) {
          // Fallback TX only
          _txCharacteristic = char;
          print('[OBD] ✓ Using fff2 for TX');
        }
        
        // Fallback logic for other devices
        if (_txCharacteristic == null && 
            (char.properties.write || char.properties.writeWithoutResponse)) {
          _txCharacteristic = char;
          print('[OBD] ✓ Using ${uuid.substring(0, 8)} as TX (fallback)');
        }
        
        if (_rxCharacteristic == null && 
            (char.properties.notify || char.properties.indicate)) {
          _rxCharacteristic = char;
          print('[OBD] ✓ Using ${uuid.substring(0, 8)} as RX (fallback)');
        }
      }
      
      if (_txCharacteristic == null) {
        print('[OBD] ❌ No TX characteristic found');
        return false;
      }
      
      print('[OBD] ═══════════════════════════════');
      print('[OBD] Configuration:');
      print('[OBD]   TX Char: ${_txCharacteristic!.uuid}');
      print('[OBD]   RX Char: ${_rxCharacteristic?.uuid ?? "NONE (will poll)"}');
      print('[OBD] ═══════════════════════════════');
      
      // Enable notifications if RX supports it
      if (_rxCharacteristic != null) {
        try {
          if (_rxCharacteristic!.properties.notify || 
              _rxCharacteristic!.properties.indicate) {
            print('[OBD] Enabling notifications...');
            
            // Subscribe to notifications FIRST
            _notificationSubscription = _rxCharacteristic!.onValueReceived.listen(
              (value) {
                if (value.isNotEmpty) {
                  _handleIncomingData(value);
                }
              },
              onError: (error) {
                print('[OBD] Notification error: $error');
              },
            );
            
            // Then enable notifications
            await _rxCharacteristic!.setNotifyValue(true);
            
            // Wait a bit for notification to be enabled
            await Future.delayed(const Duration(milliseconds: 300));
            
            print('[OBD] ✓ Notifications enabled');
          }
        } catch (e) {
          print('[OBD] ⚠️ Notification setup error: $e');
          print('[OBD] Will use polling mode instead');
        }
      }
      
      print('[OBD] ═══════════════════════════════');
      print('[OBD] ✅ Connection successful!');
      print('[OBD] Ready to send commands');
      print('[OBD] ═══════════════════════════════');
      
      return true;
      
    } catch (e, stackTrace) {
      print('[OBD] ❌ Connection error: $e');
      print('[OBD] Stack trace: $stackTrace');
      return false;
    }
  }

  /// Handle incoming data from notifications
  void _handleIncomingData(List<int> data) {
    try {
      _rawBuffer.addAll(data);
      
      // Print raw hex data
      final hexData = data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
      print('[OBD] << RAW: $hexData');
      
      // Try to decode as ASCII
      try {
        final text = utf8.decode(data, allowMalformed: true);
        print('[OBD] << ASCII: $text');
        _buffer += text;
        
        // Check if we have a complete response
        // ELM327 responses end with '>' or contain '\r'
        if (_buffer.contains('>')) {
          final lines = _buffer.split('>');
          for (int i = 0; i < lines.length - 1; i++) {
            final response = lines[i].trim();
            if (response.isNotEmpty) {
              print('[OBD] << COMPLETE: $response');
              _dataController.add(response);
            }
          }
          _buffer = lines.last;
        } else if (_buffer.contains('\r') || _buffer.contains('\n')) {
          // Alternative: split by line breaks
          final lines = _buffer.split(RegExp(r'[\r\n]+'));
          for (int i = 0; i < lines.length - 1; i++) {
            final response = lines[i].trim();
            if (response.isNotEmpty && response != '>') {
              print('[OBD] << COMPLETE: $response');
              _dataController.add(response);
            }
          }
          _buffer = lines.last;
        }
      } catch (e) {
        print('[OBD] << Decode error: $e');
      }
    } catch (e) {
      print('[OBD] Error parsing incoming data: $e');
    }
  }

  /// Send command to OBD adapter
  Future<void> sendCommand(String command) async {
    if (_device == null || _txCharacteristic == null) {
      throw Exception('Not connected to device');
    }
    
    try {
      // Clear buffers
      _buffer = '';
      _rawBuffer.clear();
      
      // Prepare command
      String cmd = command.trim();
      if (!cmd.endsWith('\r')) {
        cmd += '\r';
      }
      
      print('[OBD] ═══════════════════════════════');
      print('[OBD] >> SENDING: $cmd');
      
      final data = utf8.encode(cmd);
      final hexData = data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
      print('[OBD] >> HEX: $hexData');
      
      // Try write WITH response first (more reliable)
      try {
        if (_txCharacteristic!.properties.write) {
          print('[OBD] >> Method: Write with response');
          await _txCharacteristic!.write(data, withoutResponse: false);
          print('[OBD] ✓ Sent with response');
        } else if (_txCharacteristic!.properties.writeWithoutResponse) {
          print('[OBD] >> Method: Write without response');
          await _txCharacteristic!.write(data, withoutResponse: true);
          print('[OBD] ✓ Sent without response');
        } else {
          throw Exception('No write method available');
        }
      } catch (e) {
        print('[OBD] ⚠️ First write method failed: $e');
        print('[OBD] >> Trying alternative write method...');
        
        // Try the opposite method
        try {
          await _txCharacteristic!.write(data, withoutResponse: true);
          print('[OBD] ✓ Sent with alternative method');
        } catch (e2) {
          print('[OBD] ❌ All write methods failed: $e2');
          throw e2;
        }
      }
      
      print('[OBD] ═══════════════════════════════');
      
    } catch (e) {
      print('[OBD] ❌ Send command error: $e');
      rethrow;
    }
  }

  /// Read response from OBD adapter
  Future<String?> readResponse({Duration timeout = const Duration(seconds: 3)}) async {
    try {
      print('[OBD] Waiting for response (timeout: ${timeout.inSeconds}s)...');
      final startTime = DateTime.now();
      
      // First, wait for notification data
      while (DateTime.now().difference(startTime) < timeout) {
        // Check if we have data in buffer
        if (_buffer.isNotEmpty && (_buffer.contains('>') || _buffer.length > 10)) {
          final response = _buffer.replaceAll('>', '').trim();
          _buffer = '';
          print('[OBD] ✓ Got response from buffer: $response');
          return response;
        }
        
        // Also check raw buffer
        if (_rawBuffer.isNotEmpty) {
          try {
            final text = utf8.decode(_rawBuffer, allowMalformed: true);
            if (text.isNotEmpty) {
              _rawBuffer.clear();
              final response = text.replaceAll('>', '').trim();
              print('[OBD] ✓ Got response from raw buffer: $response');
              return response;
            }
          } catch (e) {
            print('[OBD] Raw buffer decode error: $e');
          }
        }
        
        await Future.delayed(const Duration(milliseconds: 100));
      }
      
      // Try direct read if characteristic supports it
      if (_rxCharacteristic != null && _rxCharacteristic!.properties.read) {
        print('[OBD] Attempting direct read...');
        try {
          final value = await _rxCharacteristic!.read();
          if (value.isNotEmpty) {
            final text = utf8.decode(value, allowMalformed: true).trim();
            print('[OBD] ✓ Got response from direct read: $text');
            return text;
          }
        } catch (e) {
          print('[OBD] Direct read error: $e');
        }
      }
      
      print('[OBD] ⏱️ Timeout - No response received');
      return null;
      
    } catch (e) {
      print('[OBD] ❌ Read error: $e');
      return null;
    }
  }

  /// Disconnect from device
  Future<void> disconnect() async {
    try {
      print('[OBD] Disconnecting...');
      
      await _notificationSubscription?.cancel();
      _notificationSubscription = null;
      
      if (_rxCharacteristic != null) {
        try {
          if (_rxCharacteristic!.properties.notify || 
              _rxCharacteristic!.properties.indicate) {
            await _rxCharacteristic!.setNotifyValue(false);
          }
        } catch (e) {
          print('[OBD] Error disabling notifications: $e');
        }
      }
      
      _txCharacteristic = null;
      _rxCharacteristic = null;
      _device = null;
      _buffer = '';
      _rawBuffer.clear();
      
      print('[OBD] ✓ Disconnected');
    } catch (e) {
      print('[OBD] Disconnect error: $e');
    }
  }

  void dispose() {
    _notificationSubscription?.cancel();
    _dataController.close();
  }
}