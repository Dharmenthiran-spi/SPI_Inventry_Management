import 'package:mysql_client/mysql_client.dart';

class DBConfig {
  static const String host = '127.0.0.1';
  static const int port = 3306;
  static const String user = 'sde1';
  static const String password = 'sde100';
  static const String db = 'CompanentsInventry';
}

class DBHelper {
  static MySQLConnection? _connection;

  // Dynamic connection parameters, initialized with DBConfig values
  static String _host = DBConfig.host;
  static int _port = DBConfig.port;
  static String _user = DBConfig.user;
  static String _password = DBConfig.password;
  static String _database = DBConfig.db;

  static void setupConnection({
    required String host,
    required int port,
    required String user,
    required String password,
    required String database,
  }) {
    _host = host;
    _port = port;
    _user = user;
    _password = password;
    _database = database;
  }

  // A direct test connection function
  static Future<MySQLConnection> testConnection({
    required String host,
    required int port,
    required String user,
    required String password,
    required String database,
  }) async {
    final conn = await MySQLConnection.createConnection(
      host: host,
      port: port,
      userName: user,
      password: password,
      databaseName: database,
    );
    await conn.connect();
    return conn;
  }

  static Future<MySQLConnection> get connection async {
    if (_connection != null && _connection!.connected) return _connection!;
    _connection = await MySQLConnection.createConnection(
      host: _host,
      port: _port,
      userName: _user,
      password: _password,
      databaseName: _database,
    );
    await _connection!.connect();
    return _connection!;
  }

  static Future<void> close() async {
    await _connection?.close();
    _connection = null;
  }
}
