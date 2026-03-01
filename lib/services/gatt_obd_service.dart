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
  
  // Track last response time to avoid hanging
  DateTime? _lastResponseTime;
  Timer? _timeoutTimer;

  Future<bool> connect(BluetoothDevice device) async {
    try {
      _device = device;
      
      print('[OBD] ═══════════════════════════════');
      print('[OBD] Starting OBD connection process');
      print('[OBD] ═══════════════════════════════');
      
      print('[OBD] Getting services...');
      List<BluetoothService> services = await device.discoverServices();
      print('[OBD] Found ${services.length} services');
      
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
          obdService = services[2];
        }
      }
      
      if (obdService == null) {
        print('[OBD] ❌ No suitable service found');
        return false;
      }
      
      print('[OBD] Using service: ${obdService.uuid}');
      print('[OBD] Analyzing characteristics...');
      
      for (var char in obdService.characteristics) {
        final uuid = char.uuid.toString().toLowerCase();
        print('[OBD] ─────────────────────────────');
        print('[OBD] Char UUID: $uuid');
        print('[OBD]   Read: ${char.properties.read}');
        print('[OBD]   Write: ${char.properties.write}');
        print('[OBD]   WriteWithoutResponse: ${char.properties.writeWithoutResponse}');
        print('[OBD]   Notify: ${char.properties.notify}');
        print('[OBD]   Indicate: ${char.properties.indicate}');
        
        if (uuid.contains('fff1')) {
          _txCharacteristic = char;
          _rxCharacteristic = char;
          print('[OBD] ✓ Using fff1 for BOTH TX and RX');
        } else if (uuid.contains('fff2') && _txCharacteristic == null) {
          _txCharacteristic = char;
          print('[OBD] ✓ Using fff2 for TX');
        }
        
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
      
      if (_rxCharacteristic != null) {
        try {
          if (_rxCharacteristic!.properties.notify || 
              _rxCharacteristic!.properties.indicate) {
            print('[OBD] Enabling notifications...');
            
            _notificationSubscription = _rxCharacteristic!.onValueReceived.listen(
              (value) {
                if (value.isNotEmpty) {
                  _lastResponseTime = DateTime.now();
                  _handleIncomingData(value);
                }
              },
              onError: (error) {
                print('[OBD] Notification error: $error');
              },
            );
            
            await _rxCharacteristic!.setNotifyValue(true);
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

  void _handleIncomingData(List<int> data) {
    try {
      _rawBuffer.addAll(data);
      
      final hexData = data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
      print('[OBD] << RAW: $hexData');
      
      try {
        final text = utf8.decode(data, allowMalformed: true);
        print('[OBD] << ASCII: $text');
        _buffer += text;
        
        // Check for complete response (ends with '>' or contains specific patterns)
        if (_buffer.contains('>') || _buffer.contains('OK') || _buffer.contains('ELM')) {
          final response = _buffer.replaceAll('>', '').trim();
          if (response.isNotEmpty) {
            print('[OBD] << COMPLETE: $response');
            _dataController.add(response);
          }
          _buffer = '';
          _rawBuffer.clear();
        } else if (_buffer.length > 100) {
          // Force flush if buffer gets too large
          final response = _buffer.trim();
          if (response.isNotEmpty) {
            print('[OBD] << FORCE FLUSH: $response');
            _dataController.add(response);
          }
          _buffer = '';
          _rawBuffer.clear();
        }
      } catch (e) {
        print('[OBD] << Decode error: $e');
      }
    } catch (e) {
      print('[OBD] Error parsing incoming data: $e');
    }
  }

  Future<void> sendCommand(String command) async {
    if (_device == null || _txCharacteristic == null) {
      throw Exception('Not connected to device');
    }
    
    try {
      // Clear buffers before sending
      _buffer = '';
      _rawBuffer.clear();
      _lastResponseTime = null;
      
      String cmd = command.trim();
      if (!cmd.endsWith('\r')) {
        cmd += '\r';
      }
      
      print('[OBD] ═══════════════════════════════');
      print('[OBD] >> SENDING: ${cmd.replaceAll('\r', '<CR>')}');
      
      final data = utf8.encode(cmd);
      final hexData = data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
      print('[OBD] >> HEX: $hexData');
      
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

  Future<String?> readResponse({Duration timeout = const Duration(seconds: 2)}) async {
    try {
      print('[OBD] Waiting for response (timeout: ${timeout.inSeconds}s)...');
      final startTime = DateTime.now();
      String? lastValidResponse;
      
      while (DateTime.now().difference(startTime) < timeout) {
        // Check buffer first
        if (_buffer.isNotEmpty) {
          final response = _buffer.replaceAll('>', '').trim();
          if (response.isNotEmpty && 
              !response.contains('SEARCHING') && 
              response.length > 2) {
            _buffer = '';
            _rawBuffer.clear();
            print('[OBD] ✓ Got response from buffer: $response');
            return response;
          }
        }
        
        // Check raw buffer
        if (_rawBuffer.isNotEmpty && _rawBuffer.length > 5) {
          try {
            final text = utf8.decode(_rawBuffer, allowMalformed: true);
            final cleaned = text.replaceAll('>', '').replaceAll('\r', '').replaceAll('\n', '').trim();
            if (cleaned.isNotEmpty && 
                !cleaned.contains('SEARCHING') && 
                cleaned.length > 2) {
              _rawBuffer.clear();
              _buffer = '';
              print('[OBD] ✓ Got response from raw buffer: $cleaned');
              return cleaned;
            }
          } catch (e) {
            print('[OBD] Raw buffer decode error: $e');
          }
        }
        
        // Try direct read as last resort
        if (DateTime.now().difference(startTime).inMilliseconds > timeout.inMilliseconds ~/ 2) {
          if (_rxCharacteristic != null && _rxCharacteristic!.properties.read) {
            try {
              final value = await _rxCharacteristic!.read();
              if (value.isNotEmpty) {
                final text = utf8.decode(value, allowMalformed: true).trim();
                final cleaned = text.replaceAll('>', '').replaceAll('\r', '').replaceAll('\n', '').trim();
                if (cleaned.isNotEmpty && !cleaned.contains('SEARCHING')) {
                  print('[OBD] ✓ Got response from direct read: $cleaned');
                  return cleaned;
                }
              }
            } catch (e) {
              // Ignore read errors
            }
          }
        }
        
        await Future.delayed(const Duration(milliseconds: 50));
      }
      
      // If we got any partial response, return it
      if (_buffer.isNotEmpty) {
        final response = _buffer.replaceAll('>', '').trim();
        _buffer = '';
        if (response.isNotEmpty) {
          print('[OBD] ⚠️ Timeout but got partial: $response');
          return response;
        }
      }
      
      print('[OBD] ⏱️ Timeout - No response received');
      return null;
      
    } catch (e) {
      print('[OBD] ❌ Read error: $e');
      return null;
    }
  }

  Future<void> disconnect() async {
    try {
      print('[OBD] Disconnecting...');
      
      _timeoutTimer?.cancel();
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
    _timeoutTimer?.cancel();
    _notificationSubscription?.cancel();
    _dataController.close();
  }
}