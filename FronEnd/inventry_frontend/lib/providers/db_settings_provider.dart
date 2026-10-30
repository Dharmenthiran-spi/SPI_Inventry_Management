import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/db_helper.dart';

class DbSettingsProvider extends ChangeNotifier {
  final SharedPreferences _prefs;

  String _host = '127.0.0.1';
  int _port = 3306;
  String _user = 'sde1';
  String _password = 'sde100';
  String _dbName = 'CompanentsInventry';

  // Serial barcode scanner settings
  String _barcodePort = '';
  int _barcodeBaudrate = 9600;

  String get host => _host;
  int get port => _port;
  String get user => _user;
  String get password => _password;
  String get dbName => _dbName;
  String get barcodePort => _barcodePort;
  int get barcodeBaudrate => _barcodeBaudrate;

  DbSettingsProvider(this._prefs) {
    _host = _prefs.getString('db_host') ?? '127.0.0.1';
    _port = _prefs.getInt('db_port') ?? 3306;
    _user = _prefs.getString('db_user') ?? 'sde1';
    _password = _prefs.getString('db_password') ?? 'sde100';
    _dbName = _prefs.getString('db_name') ?? 'CompanentsInventry';
    _barcodePort = _prefs.getString('barcode_port') ?? '';
    _barcodeBaudrate = _prefs.getInt('barcode_baudrate') ?? 9600;

    DBHelper.setupConnection(
      host: _host,
      port: _port,
      user: _user,
      password: _password,
      database: _dbName,
    );
  }

  Future<void> saveSettings({
    required String host,
    required int port,
    required String user,
    required String password,
    required String dbName,
    required String barcodePort,
    required int barcodeBaudrate,
  }) async {
    try {
      await _prefs.setString('db_host', host);
      await _prefs.setInt('db_port', port);
      await _prefs.setString('db_user', user);
      await _prefs.setString('db_password', password);
      await _prefs.setString('db_name', dbName);
      await _prefs.setString('barcode_port', barcodePort);
      await _prefs.setInt('barcode_baudrate', barcodeBaudrate);

      _host = host;
      _port = port;
      _user = user;
      _password = password;
      _dbName = dbName;
      _barcodePort = barcodePort;
      _barcodeBaudrate = barcodeBaudrate;

      DBHelper.setupConnection(
        host: _host,
        port: _port,
        user: _user,
        password: _password,
        database: _dbName,
      );

      await DBHelper.close();

      notifyListeners();
    } catch (e) {
      debugPrint('Failed to save DB settings: $e');
      rethrow;
    }
  }
}
