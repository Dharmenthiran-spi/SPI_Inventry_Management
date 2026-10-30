import 'package:flutter/material.dart';
import '../database/db_helper.dart';

enum AuthRole { none, defaultUser, dbUser }

class AuthProvider extends ChangeNotifier {
  bool _isLoggedIn = false;
  String _userName = '';
  int _userId = 0;
  AuthRole _role = AuthRole.none;

  bool get isLoggedIn => _isLoggedIn;
  String get userName => _userName;
  int get userId => _userId;
  AuthRole get role => _role;

  // Default credential: spi / 12345  → insert-only (can only add users)
  static const String _defaultUser = 'spi';
  static const String _defaultPass = '12345';

  Future<String?> login(String username, String password) async {
    // Check default credential first
    if (username == _defaultUser && password == _defaultPass) {
      _isLoggedIn = true;
      _userName = username;
      _userId = 0;
      _role = AuthRole.defaultUser;
      notifyListeners();
      return null; // success
    }

    // Check DB user
    try {
      final conn = await DBHelper.connection;
      final result = await conn.execute(
        'SELECT ID, Name FROM User WHERE UserName = :u AND PassWord = :p LIMIT 1',
        {'u': username, 'p': password},
      );

      if (result.rows.isNotEmpty) {
        final row = result.rows.first;
        _isLoggedIn = true;
        _userName = username;
        _userId = int.tryParse(row.colAt(0)?.toString() ?? '0') ?? 0;
        _role = AuthRole.dbUser;
        notifyListeners();
        return null; // success
      }
      return 'Invalid username or password';
    } catch (e) {
      return 'Connection error: $e';
    }
  }

  void logout() {
    _isLoggedIn = false;
    _userName = '';
    _userId = 0;
    _role = AuthRole.none;
    notifyListeners();
  }
}
