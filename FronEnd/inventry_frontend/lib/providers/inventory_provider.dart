import 'package:flutter/material.dart';
import '../database/db_helper.dart';
import '../models/inventry_model.dart';
import '../models/event_model.dart';

class InventoryProvider extends ChangeNotifier {
  List<InventryModel> _items = [];
  List<EventModel> _events = [];
  bool _loading = false;
  String? _error;

  List<InventryModel> get items => _items;
  List<EventModel> get events => _events;
  bool get loading => _loading;
  String? get error => _error;

  // ─── Fetch all ───────────────────────────────────────────────────────────
  Future<void> fetchAll() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final conn = await DBHelper.connection;
      final result = await conn.execute(
          'SELECT ID, LCSCPart, MPNPart, Description, Type, Package, CurrentQTY, UsedQTY, InStock, '
          'ReferelLink, CurrentPrice, OldPrice, '
          'CreatedDate, LastUpdatedDateTime FROM Inventry ORDER BY LastUpdatedDateTime DESC, ID DESC');
      _items = result.rows
          .map((r) => InventryModel.fromMap({
                'ID': r.colAt(0),
                'LCSCPart': r.colAt(1),
                'MPNPart': r.colAt(2),
                'Description': r.colAt(3),
                'Type': r.colAt(4),
                'Package': r.colAt(5),
                'CurrentQTY': r.colAt(6),
                'UsedQTY': r.colAt(7),
                'InStock': r.colAt(8),
                'ReferelLink': r.colAt(9),
                'CurrentPrice': r.colAt(10),
                'OldPrice': r.colAt(11),
                'CreatedDate': r.colAt(12),
                'LastUpdatedDateTime': r.colAt(13),
              }))
          .toList();
    } catch (e) {
      _error = 'Failed to fetch: $e';
    }
    _loading = false;
    notifyListeners();
  }

  // ─── Check if LCSCPart exists ─────────────────────────────────────────────
  Future<InventryModel?> findByLCSC(String lcsc) async {
    try {
      final conn = await DBHelper.connection;
      final result = await conn.execute(
          'SELECT ID, LCSCPart, MPNPart, Description, Type, Package, CurrentQTY, UsedQTY, InStock, '
          'ReferelLink, CurrentPrice, OldPrice, '
          'CreatedDate, LastUpdatedDateTime FROM Inventry WHERE LCSCPart = :l LIMIT 1',
          {'l': lcsc});
      if (result.rows.isEmpty) return null;
      final r = result.rows.first;
      return InventryModel.fromMap({
        'ID': r.colAt(0),
        'LCSCPart': r.colAt(1),
        'MPNPart': r.colAt(2),
        'Description': r.colAt(3),
        'Type': r.colAt(4),
        'Package': r.colAt(5),
        'CurrentQTY': r.colAt(6),
        'UsedQTY': r.colAt(7),
        'InStock': r.colAt(8),
        'ReferelLink': r.colAt(9),
        'CurrentPrice': r.colAt(10),
        'OldPrice': r.colAt(11),
        'CreatedDate': r.colAt(12),
        'LastUpdatedDateTime': r.colAt(13),
      });
    } catch (e) {
      return null;
    }
  }

  // ─── Add new item ─────────────────────────────────────────────────────────
  Future<bool> addNew({
    required String lcsc,
    required String mpn,
    required String desc,
    required String type,
    required String pkg,
    required int qty,
    required int userId,
    String referelLink = '',
    String currentPrice = '',
    String oldPrice = '',
    int inStock = 0,
  }) async {
    try {
      final conn = await DBHelper.connection;
      final ins = await conn.execute(
          'INSERT INTO Inventry (LCSCPart, MPNPart, Description, Type, Package, CurrentQTY, UsedQTY, InStock, ReferelLink, CurrentPrice, OldPrice) '
          'VALUES (:l, :m, :d, :t, :pkg, :q, 0, :is_, :rl, :cp, :op)',
          {'l': lcsc, 'm': mpn, 'd': desc, 't': type, 'pkg': pkg, 'q': qty,
           'is_': inStock, 'rl': referelLink, 'cp': currentPrice, 'op': oldPrice});
      final newId = ins.lastInsertID.toInt();
      await _logEvent(stockId: newId, action: 'ADD', qty: qty, userId: userId);
      await fetchAll();
      return true;
    } catch (e) {
      _error = 'Add failed: $e';
      notifyListeners();
      return false;
    }
  }

  // ─── Add qty to existing ──────────────────────────────────────────────────
  Future<bool> addQty({
    required InventryModel item,
    required int qty,
    required int userId,
  }) async {
    try {
      final conn = await DBHelper.connection;
      await conn.execute(
          'UPDATE Inventry SET CurrentQTY = CurrentQTY + :q WHERE ID = :id',
          {'q': qty, 'id': item.id});
      await _logEvent(stockId: item.id!, action: 'ADD', qty: qty, userId: userId);
      await fetchAll();
      return true;
    } catch (e) {
      _error = 'Add qty failed: $e';
      notifyListeners();
      return false;
    }
  }

  // ─── Use/minus qty from existing ─────────────────────────────────────────
  Future<bool> minusQty({
    required InventryModel item,
    required int qty,
    required int userId,
  }) async {
    if (qty > item.currentQty) {
      _error = 'Cannot use more than current stock (${item.currentQty})';
      notifyListeners();
      return false;
    }
    try {
      final conn = await DBHelper.connection;
      await conn.execute(
          'UPDATE Inventry SET CurrentQTY = CurrentQTY - :q, UsedQTY = UsedQTY + :q WHERE ID = :id',
          {'q': qty, 'id': item.id});
      await _logEvent(stockId: item.id!, action: 'USED', qty: qty, userId: userId);
      await fetchAll();
      return true;
    } catch (e) {
      _error = 'Minus qty failed: $e';
      notifyListeners();
      return false;
    }
  }

  // ─── Edit item details ────────────────────────────────────────────────────
  Future<bool> editItem({
    required int id,
    required String mpn,
    required String desc,
    required String type,
    required String pkg,
    String referelLink = '',
    String currentPrice = '',
    String oldPrice = '',
    int inStock = 0,
  }) async {
    try {
      final conn = await DBHelper.connection;
      await conn.execute(
          'UPDATE Inventry SET MPNPart = :m, Description = :d, Type = :t, Package = :pkg, '
          'InStock = :is_, ReferelLink = :rl, CurrentPrice = :cp, OldPrice = :op WHERE ID = :id',
          {'m': mpn, 'd': desc, 't': type, 'pkg': pkg, 'id': id,
           'is_': inStock, 'rl': referelLink, 'cp': currentPrice, 'op': oldPrice});
      await fetchAll();
      return true;
    } catch (e) {
      _error = 'Edit failed: $e';
      notifyListeners();
      return false;
    }
  }

  // ─── Delete item ─────────────────────────────────────────────────────────
  Future<bool> deleteItem(int id) async {
    try {
      final conn = await DBHelper.connection;
      await conn.execute('DELETE FROM Inventry WHERE ID = :id', {'id': id});
      await fetchAll();
      return true;
    } catch (e) {
      _error = 'Delete failed: $e';
      notifyListeners();
      return false;
    }
  }

  // ─── Add User (default spi credential) ───────────────────────────────────
  Future<bool> addUser({
    required String name,
    required String userName,
    required String password,
  }) async {
    try {
      final conn = await DBHelper.connection;
      await conn.execute(
          'INSERT INTO User (Name, UserName, PassWord) VALUES (:n, :u, :p)',
          {'n': name, 'u': userName, 'p': password});
      return true;
    } catch (e) {
      _error = 'Add user failed: $e';
      notifyListeners();
      return false;
    }
  }

  // ─── Internal: log event ──────────────────────────────────────────────────
  Future<void> _logEvent({
    required int stockId,
    required String action,
    required int qty,
    required int userId,
  }) async {
    try {
      final conn = await DBHelper.connection;
      // Use userId=1 as fallback if spi default user (ID=0)
      final uid = userId == 0 ? 1 : userId;
      await conn.execute(
          'INSERT INTO Event (StockID, Action, QTY, UserID) VALUES (:s, :a, :q, :u)',
          {'s': stockId, 'a': action, 'q': qty, 'u': uid});
    } catch (_) {}
  }

  // ─── Fetch Events ────────────────────────────────────────────────────────
  Future<void> fetchEvents() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final conn = await DBHelper.connection;
      final result = await conn.execute(
          'SELECT e.ID, e.StockID, e.Action, e.QTY, e.DateTime, e.UserID, '
          'i.LCSCPart, i.MPNPart, i.Package, u.UserName '
          'FROM Event e '
          'LEFT JOIN Inventry i ON e.StockID = i.ID '
          'LEFT JOIN User u ON e.UserID = u.ID '
          'ORDER BY e.DateTime DESC');
      _events = result.rows
          .map((r) => EventModel.fromMap({
                'ID': r.colAt(0),
                'StockID': r.colAt(1),
                'Action': r.colAt(2),
                'QTY': r.colAt(3),
                'DateTime': r.colAt(4),
                'UserID': r.colAt(5),
                'LCSCPart': r.colAt(6),
                'MPNPart': r.colAt(7),
                'Package': r.colAt(8),
                'UserName': r.colAt(9),
              }))
          .toList();
    } catch (e) {
      _error = 'Failed to fetch events: $e';
    }
    _loading = false;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void updateItemInMemory(
    int id, {
    required String referelLink,
    required String currentPrice,
    required String oldPrice,
    required int inStock,
  }) {
    final idx = _items.indexWhere((k) => k.id == id);
    if (idx != -1) {
      final oldItem = _items[idx];
      _items[idx] = InventryModel(
        id: oldItem.id,
        lcscPart: oldItem.lcscPart,
        mpnPart: oldItem.mpnPart,
        description: oldItem.description,
        type: oldItem.type,
        package: oldItem.package,
        currentQty: oldItem.currentQty,
        usedQty: oldItem.usedQty,
        inStock: inStock,
        referelLink: referelLink,
        currentPrice: currentPrice,
        oldPrice: oldPrice,
        createdDate: oldItem.createdDate,
        lastUpdated: DateTime.now(),
      );
      notifyListeners();
    }
  }
}
