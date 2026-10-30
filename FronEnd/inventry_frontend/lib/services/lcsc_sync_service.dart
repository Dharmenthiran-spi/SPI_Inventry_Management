import 'dart:async';
import 'package:flutter/foundation.dart';
import '../providers/inventory_provider.dart';
import '../services/lcsc_service.dart';
import '../database/db_helper.dart';

class LcscSyncService {
  static bool _isRunning = false;
  static int _currentIndex = 0;
  static int _totalItems = 0;
  static Timer? _periodicTimer;

  static const int batchSize = 500;

  static bool get isRunning => _isRunning;
  static int get currentIndex => _currentIndex;
  static int get totalItems => _totalItems;

  /// Starts the LCSC background synchronization process (immediate run on startup + 30-min timer).
  static void start(InventoryProvider provider) {
    // 1. Trigger immediate initial sync run on startup
    if (!_isRunning) {
      _runSync(provider);
    }

    // 2. Set up periodic timer for every 30 minutes if not already scheduled
    _periodicTimer ??= Timer.periodic(const Duration(minutes: 30), (_) {
      if (!_isRunning) {
        debugPrint('⏰ 30-Min Periodic Sync Triggered...');
        _runSync(provider);
      }
    });
  }

  static Future<void> _runSync(InventoryProvider provider) async {
    _isRunning = true;
    try {
      final conn = await DBHelper.connection;
      // Fetch top 500 oldest LCSC parts that haven't been updated in the last 30 minutes (Multi-User Cooldown Batch Rotation)
      final result = await conn.execute(
        'SELECT ID, LCSCPart, ReferelLink, CurrentPrice, OldPrice, InStock '
        'FROM Inventry WHERE LCSCPart IS NOT NULL AND LCSCPart != "" '
        'AND (LastUpdatedDateTime IS NULL OR LastUpdatedDateTime < NOW() - INTERVAL 30 MINUTE) '
        'ORDER BY LastUpdatedDateTime IS NULL DESC, LastUpdatedDateTime ASC, ID ASC '
        'LIMIT :b',
        {'b': batchSize},
      );
      
      final dbRows = result.rows;
      _totalItems = dbRows.length;
      _currentIndex = 0;

      debugPrint('🔄 LCSC Sync: Checking $_totalItems LCSC components for stock & price updates...');

      for (final row in dbRows) {
        if (!_isRunning) {
          debugPrint('🔄 LCSC Sync: Cancelled (stopped externally).');
          break;
        }
        
        final id = int.tryParse((row.colAt(0) ?? '').toString()) ?? 0;
        if (id == 0) continue;
        final lcsc = (row.colAt(1) ?? '').toString().trim();
        final dbLink = (row.colAt(2) ?? '').toString().trim();
        final dbPrice = (row.colAt(3) ?? '').toString().trim();
        final dbOldPrice = (row.colAt(4) ?? '').toString().trim();
        final dbInStock = int.tryParse((row.colAt(5) ?? '0').toString()) ?? 0;

        _currentIndex++;

        if (lcsc.isEmpty) continue;

        // Fetch current online LCSC info
        final info = await LcscService.fetch(lcsc);
        if (info != null) {
          final ftLink = info.url.trim();
          final ftPrice = info.unitPrice.trim();
          final ftInStock = info.inStock;

          bool changed = false;
          String currentPrice = dbPrice;
          String oldPrice = dbOldPrice;
          String referelLink = dbLink;
          int inStock = dbInStock;

          if (ftLink.isNotEmpty && ftLink != dbLink) {
            referelLink = ftLink;
            changed = true;
          }
          if (ftPrice.isNotEmpty && ftPrice != dbPrice) {
            oldPrice = dbPrice;
            currentPrice = ftPrice;
            changed = true;
          }
          if (ftInStock != dbInStock) {
            inStock = ftInStock;
            changed = true;
          }

          if (changed) {
            debugPrint('🔄 LCSC Sync: Updating $lcsc - Price: "$dbPrice" -> "$currentPrice", Stock: $dbInStock -> $inStock');
            await conn.execute(
              'UPDATE Inventry SET ReferelLink = :rl, CurrentPrice = :cp, OldPrice = :op, InStock = :is_, LastUpdatedDateTime = NOW() '
              'WHERE ID = :id',
              {
                'rl': referelLink,
                'cp': currentPrice,
                'op': oldPrice,
                'is_': inStock,
                'id': id,
              },
            );

            // Update in-memory provider item reactively so UI refreshes without lag
            provider.updateItemInMemory(
              id,
              referelLink: referelLink,
              currentPrice: currentPrice,
              oldPrice: oldPrice,
              inStock: inStock,
            );
          } else {
            // Touch LastUpdatedDateTime anyway so timestamps stay up to date
            await conn.execute(
              'UPDATE Inventry SET LastUpdatedDateTime = NOW() WHERE ID = :id',
              {'id': id},
            );
          }
        }

        // Throttled delay of 300ms per queried item to ensure zero rate limit, main lag, or DB locking
        await Future.delayed(const Duration(milliseconds: 300));
      }
      debugPrint('🔄 LCSC Sync: Finished sync of $_totalItems items.');
    } catch (e) {
      debugPrint('❌ LCSC Sync Error: $e');
    } finally {
      _isRunning = false;
    }
  }

  /// Cancels sync execution and periodic timer.
  static void stop() {
    _isRunning = false;
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }
}
