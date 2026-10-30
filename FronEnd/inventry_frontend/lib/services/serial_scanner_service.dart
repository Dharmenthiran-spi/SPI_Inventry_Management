import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:serial_port_win32/serial_port_win32.dart';

class SerialScannerService {
  SerialPort? _port;
  Timer? _pollingTimer;
  bool _running = false;
  final StringBuffer _buffer = StringBuffer();

  /// Returns all currently available COM ports on this machine.
  static List<String> availablePorts() {
    try {
      return SerialPort.getAvailablePorts();
    } catch (e) {
      debugPrint('SerialScannerService: getAvailablePorts error – $e');
      return [];
    }
  }

  /// Starts listening on [portName] at [baudRate].
  /// [onScan] fires when a full line (\r or \n terminated) is received.
  /// Returns true on success, false on failure.
  bool start({
    required String portName,
    required int baudRate,
    required Function(String) onScan,
  }) {
    if (portName.isEmpty) return false;

    // Close any stale port first
    stop();

    // NOTE: serial_port_win32 prepends \\.\\ internally.
    // Pass only "COM3", NOT "\\.\COM3" to avoid a double-prefix.
    final cleanName = portName.replaceFirst(RegExp(r'^\\\\\.\\'), '');
    debugPrint('SerialScannerService: opening $cleanName @ $baudRate baud');

    try {
      // Pass config directly to constructor to avoid calling setters on an unopened port
      _port = SerialPort(
        cleanName,
        openNow: true,
        BaudRate: baudRate,
        ByteSize: 8,
        StopBits: 0, // ONESTOPBIT = 0
        Parity: 0,   // NOPARITY   = 0
      );

      if (!_port!.isOpened) {
        debugPrint('SerialScannerService: isOpened=false after open() – port may be in use');
        _port = null;
        return false;
      }

      _running = true;
      _buffer.clear();

      _pollingTimer = Timer.periodic(const Duration(milliseconds: 50), (_) async {
        if (!_running) return;
        try {
          final bytes = await _port!.readBytes(256, timeout: const Duration(milliseconds: 40));
          if (bytes.isNotEmpty) {
            final chunk = String.fromCharCodes(bytes);
            for (final ch in chunk.runes) {
              final c = String.fromCharCode(ch);
              if (c == '\r' || c == '\n') {
                final line = _buffer.toString().trim();
                _buffer.clear();
                if (line.isNotEmpty) onScan(line);
              } else {
                _buffer.write(c);
              }
            }
          }
        } catch (_) {
          // Timeout / empty read – normal, ignore
        }
      });

      debugPrint('SerialScannerService: started on $cleanName');
      return true;
    } catch (e) {
      debugPrint('SerialScannerService: error starting – $e');
      _port = null;
      return false;
    }
  }

  /// Stops the listener and closes the port.
  void stop() {
    _running = false;
    _pollingTimer?.cancel();
    _pollingTimer = null;
    try { _port?.close(); } catch (_) {}
    _port = null;
    _buffer.clear();
    debugPrint('SerialScannerService: stopped');
  }

  bool get isRunning => _running;
}
