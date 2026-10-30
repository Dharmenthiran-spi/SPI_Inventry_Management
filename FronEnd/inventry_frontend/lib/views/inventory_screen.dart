import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:excel/excel.dart' as ex;
import 'package:csv/csv.dart';
import 'dart:io';

import '../providers/auth_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/db_settings_provider.dart';
import '../models/inventry_model.dart';
import '../services/serial_scanner_service.dart';
import '../services/lcsc_service.dart';
import '../services/lcsc_sync_service.dart';
import 'login_screen.dart';
import 'history_screen.dart';
import 'db_settings_screen.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});
  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  int _currentTab = 0; // 0 = Dashboard, 1 = LCSCPart, 2 = History, 3 = Settings
  final _searchCtrl = TextEditingController();
  final _scanInputCtrl = TextEditingController();
  final _dashboardScrollController = ScrollController();
  final _listScrollController = ScrollController();
  String _query = '';
  final _serialScanner = SerialScannerService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<InventoryProvider>();
      provider.fetchAll();
      _startSerialScanner();

      // Start throttled LCSC background sync on startup
      LcscSyncService.start(provider);
    });
  }

  void _startSerialScanner() {
    final settings = context.read<DbSettingsProvider>();
    if (settings.barcodePort.isEmpty) {
      if (mounted) setState(() {});
      return;
    }
    final ok = _serialScanner.start(
      portName: settings.barcodePort,
      baudRate: settings.barcodeBaudrate,
      onScan: (data) {
        if (mounted) _handleManualScanOrType(data);
      },
    );
    if (mounted) setState(() {});
    if (!ok && mounted) {
      _showSnack(
          'Could not open serial port ${settings.barcodePort}', isError: true);
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scanInputCtrl.dispose();
    _dashboardScrollController.dispose();
    _listScrollController.dispose();
    _serialScanner.stop();
    LcscSyncService.stop(); // Stop background sync task to release connections
    super.dispose();
  }

  // ─── QR Scan / Barcode Keyboard Scan ───────────────────────────────────────
  Future<void> _openScanner() async {
    Map<String, String>? result;
    if (defaultTargetPlatform == TargetPlatform.windows) {
      final rawInput = await showDialog<String>(
        context: context,
        builder: (_) => const _WindowsScanDialog(),
      );
      if (rawInput == null || rawInput
          .trim()
          .isEmpty) return;
      result = _parseInputText(rawInput);
    } else {
      final scanResult = await showDialog<Map<String, String>>(
        context: context,
        builder: (_) => const _QrScanDialog(),
      );
      result = scanResult;
    }
    if (result == null || !mounted) return;
    await _handleScanResult(result);
  }

  Future<void> _openManualAdd() async {
    await showDialog(
      context: context,
      builder: (_) => const _AddNewDialog(lcsc: '', mpn: '', qty: 0),
    );
    context.read<InventoryProvider>().fetchAll();
  }

  Future<void> _handleManualScanOrType(String input) async {
    final trimInput = input.trim();
    if (trimInput.isEmpty) return;
    _scanInputCtrl.clear();

    final data = _parseInputText(trimInput);
    await _handleScanResult(data);
  }

  // ── Key aliases from the barcode scanner hardware ──────────────────────────
  // pc  → LCSCPart
  // pm  → MPNPart
  // qty → Qty
  // Also accepts full names: LCSCPart, MPNPart, Quantity
  static String _normKey(String k) {
    switch (k.toLowerCase()) {
      case 'pc':
      case 'lcscpart':
      case 'lcsc':
        return 'LCSCPart';
      case 'pm':
      case 'mpnpart':
      case 'mpn':
        return 'MPNPart';
      case 'qty':
      case 'quantity':
        return 'Qty';
      case 'description':
      case 'desc':
        return 'Description';
      default:
        return k;
    }
  }

  /// Central parser — handles both scanner formats:
  ///   • {pc:C123,pm:MPNxxx,qty:5,...}  (curly-braced, comma-separated)
  ///   • LCSCPart:C123;MPNPart:MPNxxx;Qty:5
  ///   • bare LCSC string (fallback)
  static Map<String, String> _parseInputText(String raw) {
    // Strip surrounding { } and whitespace
    final clean = raw.trim().replaceAll(RegExp(r'^\{|\}$'), '').trim();
    final map = <String, String>{};

    // Split on comma OR semicolon OR & OR newline
    final parts = clean.split(RegExp(r'[,;\n&]'));
    bool hasKV = false;
    for (final p in parts) {
      final idx = p.indexOf(':');
      if (idx <= 0) continue;
      final rawKey = p.substring(0, idx).trim();
      final val = p.substring(idx + 1).trim();
      if (rawKey.isEmpty) continue;
      hasKV = true;
      final nk = _normKey(rawKey);
      // Only store known/meaningful keys; skip nulls
      if (val.toLowerCase() != 'null' && val.isNotEmpty) {
        map[nk] = val;
      }
    }

    // Positional fallback when no key:value pairs found
    if (!hasKV) {
      if (parts.length >= 3) {
        map['LCSCPart'] = parts[0].trim();
        map['MPNPart'] = parts[1].trim();
        map['Qty'] = parts[2].trim();
      } else {
        map['LCSCPart'] = clean;
      }
    }

    debugPrint('📦 Parsed scan: $map');
    return map;
  }

  Future<void> _handleScanResult(Map<String, String> data) async {
    final lcsc = (data['LCSCPart'] ?? '').trim();
    final mpn = (data['MPNPart'] ?? '').trim();
    final qty = int.tryParse(data['Qty'] ?? '0') ?? 0;
    final desc = (data['Description'] ?? data['Desc'] ?? '').trim();

    if (lcsc.isEmpty) {
      _showSnack('Invalid QR: LCSCPart missing', isError: true);
      return;
    }

    // 1. Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
      const PopScope(
        canPop: false,
        child: Center(
          child: Card(
            color: Color(0xFF161B22),
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Color(0xFF58A6FF)),
                  SizedBox(width: 16),
                  Text('Fetching LCSC details...',
                      style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    LcscProductInfo? info;
    try {
      info = await LcscService.fetch(lcsc);
    } catch (e) {
      debugPrint('LcscService.fetch error: $e');
    }

    // 2. Dismiss loading indicator
    if (mounted) {
      Navigator.of(context).pop();
    }

    final inv = context.read<InventoryProvider>();
    var existing = await inv.findByLCSC(lcsc);

    if (!mounted) return;

    if (existing == null) {
      await showDialog(
        context: context,
        builder: (_) =>
            _AddNewDialog(
              lcsc: lcsc,
              mpn: mpn,
              qty: qty,
              desc: (desc.isEmpty && info != null) ? info.description : desc,
              package: info?.package,
              referelLink: info?.url,
              currentPrice: info?.unitPrice,
              inStock: info?.inStock,
            ),
      );
    } else {
      // Sync mismatch if fetched details are different
      if (info != null) {
        print('🔍 LCSC Scan Sync checking for existing item ${existing
            .lcscPart}:');
        print('   • DB Price: "${existing.currentPrice}" vs LCSC Price: "${info
            .unitPrice}"');
        print(
            '   • DB Packaging: "${existing.package}" vs LCSC Packaging: "${info
                .package}"');
        print('   • DB Description: "${existing
            .description}" vs LCSC Description: "${info.description}"');
        print('   • DB InStock: ${existing.inStock} vs LCSC InStock: ${info
            .inStock}');
        print('   • DB Link: "${existing.referelLink}" vs LCSC Link: "${info
            .url}"');

        final dbPrice = existing.currentPrice.trim();
        final ftPrice = info.unitPrice.trim();
        final dbPkg = existing.package.trim();
        final ftPkg = info.package.trim();
        final dbDesc = existing.description.trim();
        final ftDesc = info.description.trim();
        final dbLink = existing.referelLink.trim();
        final ftLink = info.url.trim();
        final dbInStock = existing.inStock;
        final ftInStock = info.inStock;

        bool changed = false;
        String oldPrice = existing.oldPrice;
        String currentPrice = existing.currentPrice;
        String package = existing.package;
        String description = existing.description;
        String referelLink = existing.referelLink;
        int inStock = existing.inStock;

        if (ftPrice.isNotEmpty && ftPrice != dbPrice) {
          oldPrice = dbPrice;
          currentPrice = ftPrice;
          changed = true;
        }
        if (ftPkg.isNotEmpty && ftPkg != dbPkg) {
          package = ftPkg;
          changed = true;
        }
        if (ftDesc.isNotEmpty && ftDesc != dbDesc) {
          description = ftDesc;
          changed = true;
        }
        if (ftLink.isNotEmpty && ftLink != dbLink) {
          referelLink = ftLink;
          changed = true;
        }
        if (ftInStock != dbInStock) {
          inStock = ftInStock;
          changed = true;
        }

        if (changed) {
          final ok = await inv.editItem(
            id: existing.id!,
            mpn: existing.mpnPart,
            desc: description,
            type: existing.type,
            pkg: package,
            referelLink: referelLink,
            currentPrice: currentPrice,
            oldPrice: oldPrice,
            inStock: inStock,
          );
          if (ok) {
            existing = await inv.findByLCSC(lcsc) ?? existing;
            _showSnack('Synced existing item with latest LCSC details');
          }
        }
      }

      await showDialog(
        context: context,
        builder: (_) => _StockActionDialog(item: existing!, scannedQty: qty),
      );
    }
    inv.fetchAll();
  }

  // ─── Delete confirmation ──────────────────────────────────────────────────
  Future<void> _confirmDelete(InventryModel item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) =>
          AlertDialog(
            backgroundColor: const Color(0xFF161B22),
            title: const Text(
                'Delete Item', style: TextStyle(color: Colors.white)),
            content: Text('Delete "${item
                .lcscPart}"?\nThis will also delete all events for this item.',
                style: const TextStyle(color: Color(0xFF8B949E))),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false),
                  child: const Text(
                      'Cancel', style: TextStyle(color: Color(0xFF8B949E)))),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF85149)),
                child: const Text(
                    'Delete', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
    );
    if (ok == true && mounted) {
      await context.read<InventoryProvider>().deleteItem(item.id!);
      _showSnack('Deleted ${item.lcscPart}');
    }
  }

  // ─── Edit dialog ──────────────────────────────────────────────────────────
  Future<void> _editItem(InventryModel item) async {
    await showDialog(context: context, builder: (_) => _EditDialog(item: item));
  }

  Future<void> _exportCSV() async {
    final provider = context.read<InventoryProvider>();
    final items = provider.items;
    if (items.isEmpty) {
      _showSnack('No items to export', isError: true);
      return;
    }
    try {
      final String? path = await FilePicker.saveFile(
        dialogTitle: 'Export CSV',
        fileName: 'lcsc_parts_export.csv',
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      if (path == null) return;

      String finalPath = path;
      if (!finalPath.toLowerCase().endsWith('.csv')) {
        finalPath = '$finalPath.csv';
      }

      final rows = <List<dynamic>>[];
      rows.add([
        'LCSC',
        'MPN',
        'Description',
        'Current Quantity',
        'Used Quantity',
        'InStock',
        'Price'
      ]);
      for (final item in items) {
        rows.add([
          item.lcscPart,
          item.mpnPart,
          item.description,
          item.currentQty,
          item.usedQty,
          item.inStock,
          item.currentPrice,
        ]);
      }
      final csvString = const ListToCsvConverter().convert(rows);
      await File(finalPath).writeAsString(csvString);
      _showSnack('CSV exported successfully to $finalPath');
    } catch (e) {
      _showSnack('CSV Export failed: $e', isError: true);
    }
  }

  Future<void> _exportExcel() async {
    final provider = context.read<InventoryProvider>();
    final items = provider.items;
    if (items.isEmpty) {
      _showSnack('No items to export', isError: true);
      return;
    }
    try {
      final String? path = await FilePicker.saveFile(
        dialogTitle: 'Export Excel',
        fileName: 'lcsc_parts_export.xlsx',
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );
      if (path == null) return;

      String finalPath = path;
      if (!finalPath.toLowerCase().endsWith('.xlsx')) {
        finalPath = '$finalPath.xlsx';
      }

      final excel = ex.Excel.createExcel();
      final sheetName = excel.sheets.keys.first;
      final sheet = excel[sheetName]!;

      final headers = [
        'LCSC',
        'MPN',
        'Description',
        'Current Quantity',
        'Used Quantity',
        'InStock',
        'Price'
      ];
      sheet.appendRow(headers.map((h) => ex.TextCellValue(h)).toList());

      for (final item in items) {
        sheet.appendRow([
          ex.TextCellValue(item.lcscPart),
          ex.TextCellValue(item.mpnPart),
          ex.TextCellValue(item.description),
          ex.IntCellValue(item.currentQty),
          ex.IntCellValue(item.usedQty),
          ex.IntCellValue(item.inStock),
          ex.TextCellValue(item.currentPrice),
        ]);
      }

      final bytes = excel.encode();
      if (bytes != null) {
        await File(finalPath).writeAsBytes(bytes);
        _showSnack('Excel exported successfully to $finalPath');
      } else {
        _showSnack('Excel encoding failed', isError: true);
      }
    } catch (e) {
      _showSnack('Excel Export failed: $e', isError: true);
    }
  }

  Future<void> _exportPDF() async {
    final provider = context.read<InventoryProvider>();
    final items = provider.items;
    if (items.isEmpty) {
      _showSnack('No items to export', isError: true);
      return;
    }
    _exportToPDF(items);
  }

  String _sanitizePdfText(String val) {
    return val
        .replaceAll('Ω', 'Ohm')
        .replaceAll('μ', 'u')
        .replaceAll('µ', 'u')
        .replaceAll('±', '+/-')
        .replaceAll('°', 'deg')
        .replaceAll('²', '2')
        .replaceAll('³', '3');
  }

  // ─── Export to PDF ────────────────────────────────────────────────────────
  Future<void> _exportToPDF(List<InventryModel> items) async {
    try {
      final String? path = await FilePicker.saveFile(
        dialogTitle: 'Export PDF',
        fileName: 'lcsc_parts_export.pdf',
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (path == null) return;

      String finalPath = path;
      if (!finalPath.toLowerCase().endsWith('.pdf')) {
        finalPath = '$finalPath.pdf';
      }

      final pdfDoc = pw.Document();
      pdfDoc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(24),
          build: (context) => [
            pw.Header(
              level: 0,
              child: pw.Text('LCSC Inventory Report', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
            ),
            pw.SizedBox(height: 10),
            pw.TableHelper.fromTextArray(
              headers: ['LCSC', 'MPN', 'Description', 'Current Qty', 'Used Qty', 'InStock', 'Price'],
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
              cellStyle: const pw.TextStyle(fontSize: 8),
              data: items.map((item) => [
                _sanitizePdfText(item.lcscPart),
                _sanitizePdfText(item.mpnPart),
                _sanitizePdfText(item.description),
                _sanitizePdfText(item.currentQty.toString()),
                _sanitizePdfText(item.usedQty.toString()),
                _sanitizePdfText(item.inStock.toString()),
                _sanitizePdfText(item.currentPrice),
              ]).toList(),
            ),
          ],
        ),
      );

      final pdfBytes = await pdfDoc.save();
      await File(finalPath).writeAsBytes(pdfBytes);
      _showSnack('PDF exported successfully to $finalPath');
    } catch (e) {
      _showSnack('PDF Export failed: $e', isError: true);
    }
  }

    Widget _buildDashboardView() {
      return Consumer<InventoryProvider>(
        builder: (context, provider, _) {
          if (provider.loading) {
            return const Center(
                child: CircularProgressIndicator(color: Color(0xFF2EA44F)));
          }

          final items = provider.items;

          // Count overall statistics
          final totalUniqueParts = items.length;
          final totalPhysicalQty = items.fold<int>(
              0, (sum, item) => sum + item.currentQty);

          // Group by category type
          final Map<String, List<InventryModel>> grouped = {};
          for (final item in items) {
            final t = item.type
                .trim()
                .isNotEmpty ? item.type.trim() : 'Uncategorized';
            grouped.putIfAbsent(t, () => []).add(item);
          }

          return Scrollbar(
            controller: _dashboardScrollController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _dashboardScrollController,
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Dashboard Summary',
                    style: TextStyle(color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 22),
                  ),
                  const SizedBox(height: 20),

                  Row(
                    children: [
                      Expanded(
                        child: _dashboardStatCard(
                          title: 'Total Parts Types',
                          value: '$totalUniqueParts',
                          icon: Icons.category_outlined,
                          color: const Color(0xFF58A6FF),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _dashboardStatCard(
                          title: 'Total In-Stock Qty',
                          value: '$totalPhysicalQty pcs',
                          icon: Icons.inventory_2_outlined,
                          color: const Color(0xFF2EA44F),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),

                  const Text(
                    'Inventory By Category Type',
                    style: TextStyle(color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16),
                  ),
                  const SizedBox(height: 16),

                  if (grouped.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Text(
                            'No categories available yet.', style: TextStyle(
                            color: Color(0xFF8B949E))),
                      ),
                    )
                  else
                    LayoutBuilder(builder: (context, constraints) {
                      final width = constraints.maxWidth;
                      final crossAxisCount = width > 1100 ? 4 : width > 800
                          ? 3
                          : width > 500 ? 2 : 1;

                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: 1.4,
                        ),
                        itemCount: grouped.keys.length,
                        itemBuilder: (context, idx) {
                          final category = grouped.keys.elementAt(idx);
                          final categoryItems = grouped[category]!;
                          final catUniqueCount = categoryItems.length;
                          final catTotalQty = categoryItems.fold<int>(
                              0, (sum, i) => sum + i.currentQty);

                          return _categoryCard(
                              category, catUniqueCount, catTotalQty);
                        },
                      );
                    }),
                ],
              ),
            ),
          );
        },
      );
    }

    Widget _dashboardStatCard(
        {required String title, required String value, required IconData icon, required Color color}) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF30363D)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Color(0xFF8B949E),
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  Text(value, style: const TextStyle(color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    Widget _categoryCard(String title, int uniqueCount, int totalQty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF30363D)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                    Icons.folder_outlined, color: Color(0xFFBC8CFF), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text('$uniqueCount Unique Parts',
                style: const TextStyle(color: Color(0xFF8B949E), fontSize: 13)),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total Qty:',
                    style: TextStyle(color: Color(0xFF8B949E), fontSize: 12)),
                Text(
                  '$totalQty pcs',
                  style: const TextStyle(color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13),
                ),
              ],
            ),
          ],
        ),
      );
    }

    void _showSnack(String msg, {bool isError = false}) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: isError ? const Color(0xFFF85149) : const Color(
            0xFF2EA44F),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ));
    }

    Widget _buildPortStatus() {
      final settings = context.read<DbSettingsProvider>();
      final port = settings.barcodePort;
      if (port.isEmpty) {
        return const Text(
          'Scanner: Not Configured',
          style: TextStyle(color: Color(0xFF8B949E), fontSize: 11),
        );
      }
      final isConnected = _serialScanner.isRunning;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Scanner: ',
              style: TextStyle(color: Color(0xFF8B949E), fontSize: 11)),
          Text(
            port,
            style: TextStyle(
              color: isConnected ? const Color(0xFF2EA44F) : const Color(
                  0xFFF85149),
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            isConnected ? '(Connected)' : '(Offline/Error)',
            style: TextStyle(
              color: isConnected ? const Color(0xFF2EA44F) : const Color(
                  0xFFF85149),
              fontSize: 10,
            ),
          ),
        ],
      );
    }

    Widget _buildPartsSearchView() {
      return Column(
        children: [
          // Search & Scan Bar
          Container(
            padding: const EdgeInsets.all(16),
            color: const Color(0xFF161B22),
            child: Column(
              children: [
                // Search Input
                TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(color: Colors.white),
                  onChanged: (v) => setState(() => _query = v.toLowerCase()),
                  decoration: InputDecoration(
                    hintText: 'Search by LCSC / MPN / Description / Type / Package…',
                    hintStyle: const TextStyle(
                        color: Color(0xFF8B949E), fontSize: 13),
                    prefixIcon: const Icon(
                        Icons.search, color: Color(0xFF8B949E)),
                    filled: true,
                    fillColor: const Color(0xFF0D1117),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF30363D))),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF30363D))),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF2EA44F))),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
                const SizedBox(height: 12),
                // Scan Barcode & Manual Add row
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _scanInputCtrl,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 14),
                        onSubmitted: _handleManualScanOrType,
                        decoration: InputDecoration(
                          hintText: 'Scan Barcode/QR or Type LCSC Part & Enter',
                          hintStyle: const TextStyle(color: Color(0xFF8B949E),
                              fontSize: 13),
                          prefixIcon: const Icon(
                              Icons.keyboard_outlined, color: Color(0xFF8B949E),
                              size: 20),
                          filled: true,
                          fillColor: const Color(0xFF0D1117),
                          border: OutlineInputBorder(borderRadius: BorderRadius
                              .circular(8), borderSide: const BorderSide(
                              color: Color(0xFF30363D))),
                          enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                  color: Color(0xFF30363D))),
                          focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                  color: Color(0xFF2EA44F))),
                          contentPadding: const EdgeInsets.symmetric(
                              vertical: 10, horizontal: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: _openManualAdd,
                      style: TextButton.styleFrom(
                        backgroundColor: const Color(0xFF2EA44F),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add Manually', style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF30363D)),
          // Results Area
          Expanded(
            child: Consumer<InventoryProvider>(
              builder: (ctx, inv, _) {
                if (inv.loading) {
                  return const Center(child: CircularProgressIndicator(
                      color: Color(0xFF2EA44F)));
                }
                if (inv.error != null) {
                  return Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.error_outline, color: Color(0xFFF85149),
                          size: 48),
                      const SizedBox(height: 12),
                      Text(inv.error!, style: const TextStyle(color: Color(
                          0xFF8B949E))),
                      const SizedBox(height: 12),
                      ElevatedButton(onPressed: inv.fetchAll, child: const Text(
                          'Retry')),
                    ]),
                  );
                }

                final filtered = inv.items.where((i) =>
                i.lcscPart.toLowerCase().contains(_query) ||
                    i.mpnPart.toLowerCase().contains(_query) ||
                    i.description.toLowerCase().contains(_query) ||
                    i.type.toLowerCase().contains(_query) ||
                    i.package.toLowerCase().contains(_query)).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.inbox_outlined, color: Color(0xFF30363D),
                          size: 64),
                      const SizedBox(height: 12),
                      Text(_query.isEmpty
                          ? 'No inventory items yet.\nUse input above / scan QR.'
                          : 'No results for "$_query".',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFF8B949E),
                              fontSize: 15)),
                    ]),
                  );
                }

                return Scrollbar(
                  controller: _listScrollController,
                  thumbVisibility: true,
                  child: ListView.separated(
                    controller: _listScrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) =>
                        _InventoryCard(
                          item: filtered[i],
                          onEdit: () => _editItem(filtered[i]),
                          onDelete: () => _confirmDelete(filtered[i]),
                        ),
                  ),
                );
              },
            ),
          ),
        ],
      );
    }

    Widget _sidebarItem(int index, String label, IconData icon) {
      final isSelected = _currentTab == index;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: InkWell(
          onTap: () => setState(() => _currentTab = index),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF2EA44F).withValues(
                  alpha: 0.15) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: isSelected ? Border.all(
                  color: const Color(0xFF2EA44F).withValues(alpha: 0.3)) : null,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: isSelected ? const Color(0xFF2EA44F) : const Color(
                      0xFF8B949E),
                  size: 20,
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : const Color(0xFF8B949E),
                    fontWeight: isSelected ? FontWeight.bold : FontWeight
                        .normal,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget _buildTabContent() {
      switch (_currentTab) {
        case 0:
          return _buildDashboardView();
        case 1:
          return _buildPartsSearchView();
        case 2:
          return const HistoryScreen(isEmbedded: true);
        case 3:
          return const DbSettingsScreen(isEmbedded: true);
        default:
          return _buildDashboardView();
      }
    }

    @override
    Widget build(BuildContext context) {
      return Scaffold(
        backgroundColor: const Color(0xFF0D1117),
        appBar: AppBar(
          backgroundColor: const Color(0xFF161B22),
          elevation: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Inventry Management', style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18)),
              const SizedBox(height: 3),
              _buildPortStatus(),
            ],
          ),
          actions: [
            PopupMenuButton<String>(
              tooltip: 'Export Data',
              icon: const Icon(
                  Icons.file_download_outlined, color: Color(0xFF58A6FF)),
              iconSize: 25,
              onSelected: (val) {
                if (val == 'csv') _exportCSV();
                if (val == 'excel') _exportExcel();
                if (val == 'pdf') _exportPDF();
              },
              itemBuilder: (_) =>
              [
                PopupMenuItem(
                  value: 'csv',
                  child: Row(
                    children: const [
                      Icon(Icons.description, color: Color(0xFFE3B341),
                          size: 18),
                      SizedBox(width: 8),
                      Text('Export as CSV'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'excel',
                  child: Row(
                    children: const [
                      Icon(
                          Icons.table_view, color: Color(0xFF2EA44F), size: 18),
                      SizedBox(width: 8),
                      Text('Export as Excel'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'pdf',
                  child: Row(
                    children: const [
                      Icon(Icons.picture_as_pdf, color: Color(0xFFF85149),
                          size: 18),
                      SizedBox(width: 8),
                      Text('Export as PDF'),
                    ],
                  ),
                ),
              ],
            ),
            IconButton(
              tooltip: 'Refresh All DB Data',
              icon: const Icon(Icons.refresh, color: Color(0xFF8B949E)),
              iconSize: 25,
              onPressed: () {
                context.read<InventoryProvider>().fetchAll();
                context.read<InventoryProvider>().fetchEvents();
              },
            ),
            IconButton(
              tooltip: 'Scan QR Code Dialog',
              icon: const Icon(Icons.qr_code_scanner, color: Color(0xFF2EA44F)),
              iconSize: 25,
              onPressed: _openScanner,
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () {
                context.read<AuthProvider>().logout();
                Navigator.pushReplacement(context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()));
              },
              icon: const Icon(
                  Icons.logout, color: Color(0xFF8B949E), size: 19),
              label: const Text(
                  'Logout', style: TextStyle(color: Color(0xFF8B949E))),
            ),
          ],
        ),
        body: Row(
          children: [
            // Sidebar Left side
            Container(
              width: 230,
              height: double.infinity,
              decoration: const BoxDecoration(
                color: Color(0xFF161B22),
                border: Border(right: BorderSide(color: Color(0xFF30363D))),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  _sidebarItem(0, 'Dashboard', Icons.dashboard_outlined),
                  _sidebarItem(1, 'LCSC Parts', Icons.inventory_2_outlined),
                  _sidebarItem(2, 'History', Icons.history_outlined),
                  _sidebarItem(3, 'Settings', Icons.settings_outlined),
                  const Spacer(),
                  Consumer<AuthProvider>(
                    builder: (context, auth, _) {
                      final uname = auth.userName.isNotEmpty
                          ? auth.userName
                          : 'User';
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 20),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 15,
                              backgroundColor: const Color(0xFF58A6FF)
                                  .withValues(alpha: 0.15),
                              child: Text(
                                uname.substring(0, 1).toUpperCase(),
                                style: const TextStyle(color: Color(0xFF58A6FF),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(uname, style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold),
                                      overflow: TextOverflow.ellipsis),
                                  const Text('Operator', style: TextStyle(
                                      color: Color(0xFF8B949E), fontSize: 11)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            // Content Right side
            Expanded(
              child: _buildTabContent(),
            ),
          ],
        ),
        floatingActionButton: _currentTab == 1
            ? FloatingActionButton.extended(
          onPressed: _openScanner,
          backgroundColor: const Color(0xFF2EA44F),
          icon: const Icon(Icons.qr_code_scanner, color: Colors.white),
          label: const Text('Scan QR', style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.w600)),
        )
            : null,
      );
    }
  }

// ─── Inventory Card ───────────────────────────────────────────────────────────
  class _InventoryCard extends StatelessWidget {
  final InventryModel item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _InventoryCard({required this.item, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
  final stockColor = item.currentQty <= 0
  ? const Color(0xFFF85149)
      : item.currentQty < 5
  ? const Color(0xFFE3B341)
      : const Color(0xFF2EA44F);

  return Container(
  decoration: BoxDecoration(
  color: const Color(0xFF161B22),
  borderRadius: BorderRadius.circular(12),
  border: Border.all(color: const Color(0xFF30363D)),
  ),
  child: Padding(
  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
  child: Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  mainAxisSize: MainAxisSize.min,
  children: [
  // Row 1: Columns (Specs/Timestamps on left, Centered URL, Stock vertical stack on right)
  Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
  // Left Column: LCSC Part, Specs, Timestamps, Type chip
  Expanded(
  flex: 4,
  child: Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
  // Sub-Row: LCSC Part number and Description
  Row(
  children: [
  Text(
  item.lcscPart,
  style: const TextStyle(
  color: Colors.white,
  fontWeight: FontWeight.bold,
  fontSize: 16,
  ),
  ),
  const SizedBox(width: 12),
  Expanded(
  child: Text(
  item.description.isNotEmpty ? item.description : '(No Description)',
  style: const TextStyle(
  color: Color(0xFFC9D1D9),
  fontSize: 13,
  fontWeight: FontWeight.w500,
  ),
  maxLines: 1,
  overflow: TextOverflow.ellipsis,
  ),
  ),
  ],
  ),
  const SizedBox(height: 6),

  // Specs (MPN & Package)
  Row(
  children: [
  if (item.mpnPart.isNotEmpty) ...[
  const Icon(Icons.settings_suggest_outlined, size: 12, color: Color(0xFF58A6FF)),
  const SizedBox(width: 4),
  Flexible(
  child: Text(
  'MPN: ${item.mpnPart}',
  style: const TextStyle(color: Color(0xFF58A6FF), fontSize: 12, fontWeight: FontWeight.w600),
  overflow: TextOverflow.ellipsis,
  ),
  ),
  const SizedBox(width: 8),
  ],
  if (item.package.isNotEmpty) ...[
  const Icon(Icons.layers_outlined, size: 12, color: Color(0xFFBC8CFF)),
  const SizedBox(width: 4),
  Flexible(
  child: Text(
  'Pkg: ${item.package}',
  style: const TextStyle(color: Color(0xFFBC8CFF), fontSize: 12, fontWeight: FontWeight.w600),
  overflow: TextOverflow.ellipsis,
  ),
  ),
  ],
  ],
  ),
  const SizedBox(height: 6),

  // Timestamps (Created & Updated - font size 13!)
  Row(
  children: [
  const Icon(Icons.add_circle_outline, size: 12, color: Color(0xFF8B949E)),
  const SizedBox(width: 4),
  Text(
  'Cr: ${_formatDateTime(item.createdDate)}',
  style: const TextStyle(color: Color(0xFF8B949E), fontSize: 13),
  ),
  const SizedBox(width: 8),
  const Icon(Icons.history_toggle_off, size: 12, color: Color(0xFF8B949E)),
  const SizedBox(width: 4),
  Text(
  'Up: ${_formatDateTime(item.lastUpdated)}',
  style: const TextStyle(color: Color(0xFF8B949E), fontSize: 13),
  ),
  ],
  ),
  const SizedBox(height: 6),

  // Type chip
  if (item.type.isNotEmpty)
  _chip('Type: ${item.type}', const Color(0xFFBC8CFF)),
  ],
  ),
  ),
  const SizedBox(width: 12),

  // Center Column: Centered URL link
  Expanded(
  flex: 3,
  child: Center(
  child: item.referelLink.isNotEmpty
  ? InkWell(
  onTap: () async {
  final url = item.referelLink.trim();
  if (url.isNotEmpty) {
  try {
  final uri = Uri.parse(url);
  await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
  }
  },
  child: Padding(
  padding: const EdgeInsets.symmetric(vertical: 4),
  child: Text(
  item.referelLink,
  style: const TextStyle(
  color: Color(0xFF58A6FF),
  fontSize: 14,
  fontWeight: FontWeight.w600,
  decoration: TextDecoration.underline,
  ),
  maxLines: 2,
  textAlign: TextAlign.center,
  overflow: TextOverflow.ellipsis,
  ),
  ),
  )
      : const SizedBox.shrink(),
  ),
  ),
  const SizedBox(width: 12),

  // Right Column: Stock text + vertical parameters (left aligned!)
  Expanded(
  flex: 3,
  child: Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
  // Current Stock with Border!
  Container(
  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
  decoration: BoxDecoration(
  borderRadius: BorderRadius.circular(6),
  border: Border.all(color: stockColor, width: 1.5),
  ),
  child: Text(
  'Current Stock: ${item.currentQty}',
  style: TextStyle(color: stockColor, fontWeight: FontWeight.bold, fontSize: 13),
  ),
  ),
  const SizedBox(height: 6),
  Text(
  'Used: ${item.usedQty}',
  style: const TextStyle(color: Color(0xFFF85149), fontSize: 12, fontWeight: FontWeight.bold),
  ),
  const SizedBox(height: 4),
  Text(
  'In-Stock: ${item.inStock}',
  style: const TextStyle(color: Color(0xFFF0883E), fontSize: 12, fontWeight: FontWeight.bold),
  ),
  const SizedBox(height: 4),
  Text(
  'Price: ${item.currentPrice.isNotEmpty ? item.currentPrice : '-'}',
  style: const TextStyle(color: Color(0xFF2EA44F), fontSize: 12, fontWeight: FontWeight.bold),
  ),
  ],
  ),
  ),
  ],
  ),

  // Row 2: Action Buttons (divider-less bottom corner to save height!)
  Row(
  mainAxisAlignment: MainAxisAlignment.end,
  children: [
  IconButton(
  icon: const Icon(Icons.edit_outlined, size: 18),
  color: const Color(0xFF58A6FF),
  tooltip: 'Edit',
  constraints: const BoxConstraints(),
  padding: const EdgeInsets.all(4),
  onPressed: onEdit,
  ),
  IconButton(
  icon: const Icon(Icons.delete_outline, size: 18),
  color: const Color(0xFFF85149),
  tooltip: 'Delete',
  constraints: const BoxConstraints(),
  padding: const EdgeInsets.all(4),
  onPressed: onDelete,
  ),
  ],
  ),
  ],
  ),
  ),
  );
  }

  Widget _chip(String text, Color color) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
  decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
  child: Text(text, style: TextStyle(color: color, fontSize: 13)),
  );

  String _formatDateTime(DateTime? dt) {
  if (dt == null) return '-';
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${dt.year}-${pad(dt.month)}-${pad(dt.day)} ${pad(dt.hour)}:${pad(dt.minute)}:${pad(dt.second)}';
  }
  }


// ─── QR Scanner Dialog ────────────────────────────────────────────────────────
  class _QrScanDialog extends StatefulWidget {
  const _QrScanDialog();
  @override
  State<_QrScanDialog> createState() => _QrScanDialogState();
  }

  class _QrScanDialogState extends State<_QrScanDialog> {
  bool _scanned = false;

  void _handle(BarcodeCapture capture) {
  if (_scanned) return;
  final raw = capture.barcodes.firstOrNull?.rawValue;
  if (raw == null) return;
  _scanned = true;
  final map = _parseQr(raw);
  Navigator.pop(context, map);
  }

  // Parse formats: key:value pairs separated by \n or ;
  // e.g.  LCSCPart:C10;MPNPart:GRM188R71C104KA01;Qty:100
  Map<String, String> _parseQr(String raw) {
  final map = <String, String>{};
  final parts = raw.split(RegExp(r'[;\n&]'));
  for (final p in parts) {
  final idx = p.indexOf(':');
  if (idx < 0) continue;
  final key = p.substring(0, idx).trim();
  final val = p.substring(idx + 1).trim();
  map[key] = val;
  }
  // Fallback: if LCSCPart missing but we have 3 bare values
  if (!map.containsKey('LCSCPart') && parts.length >= 3) {
  map['LCSCPart'] = parts[0].trim();
  map['MPNPart'] = parts[1].trim();
  map['Qty'] = parts[2].trim();
  }
  return map;
  }

  @override
  Widget build(BuildContext context) {
  return Dialog(
  backgroundColor: const Color(0xFF161B22),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  child: SizedBox(
  width: 380, height: 460,
  child: Column(children: [
  Padding(
  padding: const EdgeInsets.all(16),
  child: Row(children: [
  const Icon(Icons.qr_code_scanner, color: Color(0xFF2EA44F)),
  const SizedBox(width: 10),
  const Text('Scan QR Code', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
  const Spacer(),
  IconButton(icon: const Icon(Icons.close, color: Color(0xFF8B949E)), onPressed: () => Navigator.pop(context)),
  ]),
  ),
  Expanded(
  child: ClipRRect(
  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
  child: MobileScanner(onDetect: _handle),
  ),
  ),
  Padding(
  padding: const EdgeInsets.all(12),
  child: Text('Point camera at the QR code', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13)),
  ),
  ]),
  ),
  );
  }
  }

  class _WindowsScanDialog extends StatefulWidget {
  const _WindowsScanDialog();
  @override
  State<_WindowsScanDialog> createState() => _WindowsScanDialogState();
  }

  class _WindowsScanDialogState extends State<_WindowsScanDialog> {
  final _inputCtrl = TextEditingController();
  final _focusNode = FocusNode();
  final _qtyCtrl = TextEditingController(text: '1');
  bool _loading = false;
  InventryModel? _existing;
  bool _checked = false;
  String? _err;
  String _rawScan = '';
  Map<String, String> _parsedMap = {};

  @override
  void initState() {
  super.initState();
  WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
  _inputCtrl.dispose();
  _focusNode.dispose();
  _qtyCtrl.dispose();
  super.dispose();
  }

  // Called on Enter / scanner trigger
  Future<void> _lookup() async {
  final raw = _inputCtrl.text.trim();
  if (raw.isEmpty) return;

  debugPrint('🔍 WindowsScanDialog received: "$raw"');

  final parsed = _InventoryScreenState._parseInputText(raw);

  // Pre-fill qty from scanned data
  if (parsed.containsKey('Qty')) {
  final qtyFromScan = int.tryParse(parsed['Qty']!);
  if (qtyFromScan != null && qtyFromScan > 0) {
  _qtyCtrl.text = qtyFromScan.toString();
  }
  }

  final lcsc = parsed['LCSCPart'] ?? raw.trim();
  debugPrint('🔍 Parsed map: $parsed');
  debugPrint('🔍 Extracted LCSCPart: "$lcsc"');

  setState(() {
  _loading = true;
  _err = null;
  _checked = false;
  _existing = null;
  _rawScan = raw;
  _parsedMap = parsed;
  });

  final inv = context.read<InventoryProvider>();
  final found = await inv.findByLCSC(lcsc);

  debugPrint('🔍 DB lookup: ${found == null ? "NOT FOUND" : "FOUND → ${found.lcscPart}"}');

  setState(() {
  _loading = false;
  _checked = true;
  _existing = found;
  });
  }

  // Add stock to existing item
  Future<void> _doAdd() async {
  final qty = int.tryParse(_qtyCtrl.text) ?? 0;
  if (qty <= 0) { setState(() => _err = 'Qty must be > 0'); return; }
  if (_existing == null) return;
  setState(() => _loading = true);
  final auth = context.read<AuthProvider>();
  await context.read<InventoryProvider>().addQty(item: _existing!, qty: qty, userId: auth.userId);
  if (mounted) Navigator.pop(context);
  }

  // Use/minus stock from existing item
  Future<void> _doUse() async {
  final qty = int.tryParse(_qtyCtrl.text) ?? 0;
  if (qty <= 0) { setState(() => _err = 'Qty must be > 0'); return; }
  if (qty > _existing!.currentQty) { setState(() => _err = 'Only ${_existing!.currentQty} in stock'); return; }
  setState(() => _loading = true);
  final auth = context.read<AuthProvider>();
  await context.read<InventoryProvider>().minusQty(item: _existing!, qty: qty, userId: auth.userId);
  if (mounted) Navigator.pop(context);
  }

  // Human-readable label for display in Scan Details card
  static String _fieldLabel(String key) {
  switch (key) {
  case 'LCSCPart': return 'LCSC Part:';
  case 'MPNPart': return 'MPN Part:';
  case 'Qty': return 'Quantity:';
  case 'Description': return 'Description:';
  default: return '$key:';
  }
  }

  // Pop plain text so _openScanner can create an _AddNewDialog
  void _doAddNew() {
  Navigator.pop(context, _inputCtrl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
  return _BaseDialog(
  title: 'Barcode Scanner',
  icon: Icons.qr_code_scanner,
  iconColor: const Color(0xFF2EA44F),
  children: [
  const Text(
  'Scan barcode or type part number then press Enter / Check:',
  style: TextStyle(color: Color(0xFF8B949E), fontSize: 13),
  ),
  const SizedBox(height: 14),

  // ── Input row ────────────────────────────────────────────────────────
  Row(children: [
  Expanded(
  child: TextField(
  controller: _inputCtrl,
  focusNode: _focusNode,
  style: const TextStyle(color: Colors.white, fontSize: 14),
  onSubmitted: (_) => _lookup(),
  decoration: InputDecoration(
  hintText: 'Waiting for scan…',
  hintStyle: const TextStyle(color: Color(0xFF8B949E)),
  prefixIcon: const Icon(Icons.keyboard_outlined, color: Color(0xFF8B949E)),
  filled: true,
  fillColor: const Color(0xFF0D1117),
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF30363D))),
  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF30363D))),
  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF2EA44F))),
  contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
  ),
  ),
  ),
  const SizedBox(width: 8),
  ElevatedButton(
  onPressed: _loading ? null : _lookup,
  style: ElevatedButton.styleFrom(
  backgroundColor: const Color(0xFF2EA44F),
  foregroundColor: Colors.white,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
  ),
  child: _loading
  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
      : const Icon(Icons.search, size: 20),
  ),
  ]),

  // ── Scan Details card (raw + parsed) ─────────────────────────────────
  if (_rawScan.isNotEmpty) ...[
  const SizedBox(height: 14),
  Container(
  width: double.infinity,
  padding: const EdgeInsets.all(12),
  decoration: BoxDecoration(
  color: const Color(0xFF0D1117),
  borderRadius: BorderRadius.circular(8),
  border: Border.all(color: const Color(0xFF30363D)),
  ),
  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
  Row(children: const [
  Icon(Icons.receipt_long, color: Color(0xFF58A6FF), size: 15),
  SizedBox(width: 6),
  Text('Scan Details', style: TextStyle(color: Color(0xFF58A6FF), fontWeight: FontWeight.bold, fontSize: 13)),
  ]),
  const SizedBox(height: 8),
  // Raw string
  Text('Raw: $_rawScan', style: const TextStyle(color: Color(0xFF8B949E), fontSize: 11, fontFamily: 'monospace')),
  if (_parsedMap.isNotEmpty) ...[
  const Divider(color: Color(0xFF30363D), height: 12),
  // Each mapped field
  for (final entry in _parsedMap.entries)
  Padding(
  padding: const EdgeInsets.only(bottom: 3),
  child: Row(children: [
  SizedBox(
  width: 100,
  child: Text(_fieldLabel(entry.key),
  style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12)),
  ),
  Expanded(child: Text(entry.value,
  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500))),
  ]),
  ),
  ],
  ]),
  ),
  ],

  // ── Results area ─────────────────────────────────────────────────────
  if (_checked) ...[
  const SizedBox(height: 16),
  if (_existing != null) ...[
  // Found — show item info + qty field
  Container(
  padding: const EdgeInsets.all(12),
  decoration: BoxDecoration(
  color: const Color(0xFF0D1117),
  borderRadius: BorderRadius.circular(8),
  border: Border.all(color: const Color(0xFF2EA44F).withValues(alpha: 0.5)),
  ),
  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
  Row(children: [
  const Icon(Icons.check_circle, color: Color(0xFF2EA44F), size: 16),
  const SizedBox(width: 6),
  Text('Found: ${_existing!.lcscPart}', style: const TextStyle(color: Color(0xFF2EA44F), fontWeight: FontWeight.bold)),
  ]),
  const SizedBox(height: 4),
  if (_existing!.mpnPart.isNotEmpty)
  Text('MPN: ${_existing!.mpnPart}', style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12)),
  if (_existing!.type.isNotEmpty)
  Text('Type: ${_existing!.type}', style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12)),
  if (_existing!.package.isNotEmpty)
  Text('Package: ${_existing!.package}', style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12)),
  Text('In stock: ${_existing!.currentQty} pcs', style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12)),
  ]),
  ),
  const SizedBox(height: 12),
  _tf(_qtyCtrl, 'Quantity', isNumber: true),
  if (_err != null) ...[
  const SizedBox(height: 6),
  Text(_err!, style: const TextStyle(color: Color(0xFFF85149), fontSize: 12)),
  ],
  const SizedBox(height: 14),
  if (_loading)
  const Center(child: CircularProgressIndicator(color: Color(0xFF2EA44F)))
  else
  Row(children: [
  Expanded(child: TextButton(
  onPressed: () => Navigator.pop(context),
  child: const Text('Cancel', style: TextStyle(color: Color(0xFF8B949E))),
  )),
  const SizedBox(width: 8),
  Expanded(child: OutlinedButton.icon(
  onPressed: _doUse,
  icon: const Icon(Icons.remove_circle_outline, color: Color(0xFFF85149), size: 16),
  label: const Text('Use (−)', style: TextStyle(color: Color(0xFFF85149))),
  style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFFF85149)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
  )),
  const SizedBox(width: 8),
  Expanded(child: ElevatedButton.icon(
  onPressed: _doAdd,
  icon: const Icon(Icons.add_circle_outline, color: Colors.white, size: 16),
  label: const Text('Add (+)', style: TextStyle(color: Colors.white)),
  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2EA44F), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
  )),
  ]),
  ] else ...[
  // Not found — prompt to add
  Container(
  padding: const EdgeInsets.all(12),
  decoration: BoxDecoration(
  color: const Color(0xFF0D1117),
  borderRadius: BorderRadius.circular(8),
  border: Border.all(color: const Color(0xFFF85149).withValues(alpha: 0.4)),
  ),
  child: Row(children: [
  const Icon(Icons.info_outline, color: Color(0xFF58A6FF), size: 16),
  const SizedBox(width: 8),
  const Expanded(child: Text('Part not found. Would you like to add it as new?',
  style: TextStyle(color: Color(0xFF8B949E), fontSize: 13))),
  ]),
  ),
  const SizedBox(height: 14),
  Row(children: [
  Expanded(child: TextButton(
  onPressed: () => Navigator.pop(context),
  child: const Text('Cancel', style: TextStyle(color: Color(0xFF8B949E))),
  )),
  const SizedBox(width: 12),
  Expanded(child: ElevatedButton.icon(
  onPressed: _doAddNew,
  icon: const Icon(Icons.add, color: Colors.white, size: 16),
  label: const Text('Add New', style: TextStyle(color: Colors.white)),
  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2EA44F), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
  )),
  ]),
  ],
  ] else ...[
  // Not yet looked up — just show Cancel
  const SizedBox(height: 16),
  Align(
  alignment: Alignment.centerRight,
  child: TextButton(
  onPressed: () => Navigator.pop(context),
  child: const Text('Cancel', style: TextStyle(color: Color(0xFF8B949E))),
  ),
  ),
  ],
  ],
  );
  }
  }
// ─── Add New Part Dialog ──────────────────────────────────────────────────────
  class _AddNewDialog extends StatefulWidget {
  final String lcsc, mpn, desc;
  final int qty;
  final String? package;
  final String? referelLink;
  final String? currentPrice;
  final String? oldPrice;
  final int? inStock;
  const _AddNewDialog({
  required this.lcsc,
  required this.mpn,
  required this.qty,
  this.desc = '',
  this.package,
  this.referelLink,
  this.currentPrice,
  this.oldPrice,
  this.inStock,
  });
  @override
  State<_AddNewDialog> createState() => _AddNewDialogState();
  }

  const _kComponentTypes = [
  'Capacitor', 'Resistor', 'Inductor', 'Ferrite Bead', 'Fuse',
  'IC', 'OpAmp', 'Microcontroller', 'Transistor', 'MOSFET',
  'Diode', 'TVS/ESD', 'LED', 'Connector', 'Crystal/Oscillator',
  'Relay', 'Sensor', 'Module', 'Others',
  ];

  class _AddNewDialogState extends State<_AddNewDialog> {
  late final TextEditingController _lcscCtrl;
  late final TextEditingController _mpnCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _pkgCtrl;
  late final TextEditingController _qtyCtrl;
  final TextEditingController _typeCtrl = TextEditingController();
  final TextEditingController _referelLinkCtrl = TextEditingController();
  final TextEditingController _currentPriceCtrl = TextEditingController();
  final TextEditingController _oldPriceCtrl = TextEditingController();
  final TextEditingController _inStockCtrl = TextEditingController();
  final FocusNode _typeFocusNode = FocusNode();
  bool _loading = false;
  bool _lcscFetching = false;
  String _fetchStatus = '';
  String? _err;

  @override
  void initState() {
  super.initState();
  _lcscCtrl = TextEditingController(text: widget.lcsc);
  _mpnCtrl = TextEditingController(text: widget.mpn);
  _descCtrl = TextEditingController(text: widget.desc);
  _pkgCtrl = TextEditingController(text: widget.package ?? '');
  _qtyCtrl = TextEditingController(text: widget.qty.toString());
  _referelLinkCtrl.text = widget.referelLink ?? '';
  _currentPriceCtrl.text = widget.currentPrice ?? '';
  _oldPriceCtrl.text = widget.oldPrice ?? '';
  _inStockCtrl.text = widget.inStock != null ? widget.inStock.toString() : '';

  // Auto-fetch from LCSC if part number is known from scan but we didn't receive pre-fetched data
  if (widget.lcsc.isNotEmpty && widget.package == null && widget.currentPrice == null) {
  WidgetsBinding.instance.addPostFrameCallback((_) => _fetchFromLcsc());
  } else if (widget.package != null || widget.currentPrice != null) {
  _fetchStatus = '✓ LCSC data auto-filled';
  }
  }

  @override
  void dispose() {
  _lcscCtrl.dispose();
  _mpnCtrl.dispose();
  _descCtrl.dispose();
  _pkgCtrl.dispose();
  _typeCtrl.dispose();
  _referelLinkCtrl.dispose();
  _currentPriceCtrl.dispose();
  _oldPriceCtrl.dispose();
  _inStockCtrl.dispose();
  _typeFocusNode.dispose();
  _qtyCtrl.dispose();
  super.dispose();
  }

  Future<void> _fetchFromLcsc([String? overridePart]) async {
  final part = (overridePart ?? _lcscCtrl.text).trim();
  if (part.isEmpty) return;
  if (!mounted) return;
  setState(() { _lcscFetching = true; _fetchStatus = ''; });
  final info = await LcscService.fetch(part);
  if (!mounted) return;
  setState(() {
  _lcscFetching = false;
  if (info == null) {
  _fetchStatus = '⚠ Could not fetch LCSC data (check internet)';
  } else {
  _fetchStatus = '✓ LCSC data auto-filled';
  // Always fill link
  _referelLinkCtrl.text = info.url;
  // Fill only if field is empty (don't overwrite user edits)
  if (_pkgCtrl.text.isEmpty) _pkgCtrl.text = info.package;
  if (_descCtrl.text.isEmpty) _descCtrl.text = info.description;
  if (_inStockCtrl.text.isEmpty || _inStockCtrl.text == '0') {
  _inStockCtrl.text = info.inStock.toString();
  }
  // Price: if Current is set, move to Old, set new
  final fetchedPrice = info.unitPrice;
  if (fetchedPrice.isNotEmpty) {
  final existing = _currentPriceCtrl.text.trim();
  if (existing.isNotEmpty && existing != fetchedPrice) {
  _oldPriceCtrl.text = existing;
  }
  _currentPriceCtrl.text = fetchedPrice;
  }
  }
  });
  }

  Future<void> _save() async {
  final lcsc = _lcscCtrl.text.trim();
  if (lcsc.isEmpty) {
  setState(() => _err = 'LCSC Part is required');
  return;
  }
  final mpn = _mpnCtrl.text.trim();
  if (mpn.isEmpty) {
  setState(() => _err = 'MPN Part is required');
  return;
  }
  final type = _typeCtrl.text.trim();
  if (type.isEmpty) {
  setState(() => _err = 'Category Type is required');
  return;
  }
  final qty = int.tryParse(_qtyCtrl.text) ?? 0;
  setState(() {
  _loading = true;
  _err = null;
  });

  final invPro = context.read<InventoryProvider>();

  if (widget.lcsc.isEmpty) {
  final existing = await invPro.findByLCSC(lcsc);
  if (existing != null) {
  setState(() {
  _loading = false;
  _err = 'LCSC Part "$lcsc" already exists.';
  });
  return;
  }
  }

  final auth = context.read<AuthProvider>();
  final ok = await invPro.addNew(
  lcsc: lcsc, mpn: _mpnCtrl.text, desc: _descCtrl.text,
  type: _typeCtrl.text.trim(),
  pkg: _pkgCtrl.text.trim(),
  qty: qty, userId: auth.userId,
  referelLink: _referelLinkCtrl.text.trim(),
  currentPrice: _currentPriceCtrl.text.trim(),
  oldPrice: _oldPriceCtrl.text.trim(),
  inStock: int.tryParse(_inStockCtrl.text.trim()) ?? 0,
  );
  if (mounted) Navigator.pop(context);
  if (!ok && mounted) {
  ScaffoldMessenger.of(context).showSnackBar(
  const SnackBar(content: Text('Failed to add item'), backgroundColor: Color(0xFFF85149)));
  }
  }

  @override
  Widget build(BuildContext context) {
  final isLcscEditable = widget.lcsc.isEmpty;
  return _BaseDialog(
  title: 'Add New Part',
  icon: Icons.add_circle_outline,
  iconColor: const Color(0xFF2EA44F),
  children: [
  if (isLcscEditable) ...[
  _tf(_lcscCtrl, 'LCSC Part'),
  const SizedBox(height: 6),
  Align(
  alignment: Alignment.centerRight,
  child: TextButton.icon(
  onPressed: _lcscFetching ? null : () => _fetchFromLcsc(),
  icon: _lcscFetching
  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF58A6FF)))
      : const Icon(Icons.cloud_download_outlined, size: 16, color: Color(0xFF58A6FF)),
  label: Text(_lcscFetching ? 'Fetching…' : 'Fetch from LCSC',
  style: const TextStyle(color: Color(0xFF58A6FF), fontSize: 12)),
  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
  ),
  ),
  ] else ...[
  Row(children: [
  Expanded(child: _infoRow('LCSC Part', widget.lcsc)),
  if (_lcscFetching)
  const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF58A6FF)))
  else
  IconButton(
  tooltip: 'Reload from LCSC',
  icon: const Icon(Icons.cloud_download_outlined, size: 18, color: Color(0xFF58A6FF)),
  onPressed: _fetchFromLcsc,
  padding: EdgeInsets.zero,
  constraints: const BoxConstraints(),
  ),
  ]),
  ],
  const SizedBox(height: 12),
  _tf(_mpnCtrl, 'MPN Part'),
  const SizedBox(height: 12),
  _descriptionTf(_descCtrl),
  const SizedBox(height: 12),
  // Type autocomplete (select from list OR free-type)
  _typeAutoComplete(_typeCtrl, _typeFocusNode),
  const SizedBox(height: 12),
  _tf(_pkgCtrl, 'Package (e.g. 0402, SOT-23, SOIC-8)'),
  const SizedBox(height: 12),
  _tf(_referelLinkCtrl, 'Referel Link (e.g. LCSC / Datasheet URL)'),
  const SizedBox(height: 12),
  Row(children: [
  Expanded(child: _tf(_currentPriceCtrl, 'Current Price')),
  const SizedBox(width: 10),
  Expanded(child: _tf(_oldPriceCtrl, 'Old Price')),
  ]),
  const SizedBox(height: 12),
  _tf(_inStockCtrl, 'In-Stock (initial qty on hand)', isNumber: true),
  const SizedBox(height: 12),
  _tf(_qtyCtrl, 'Quantity', isNumber: true),
  // ── LCSC fetch status banner ─────────────────────────────────────────
  if (_fetchStatus.isNotEmpty) ...[
  const SizedBox(height: 8),
  Container(
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
  decoration: BoxDecoration(
  color: _fetchStatus.startsWith('✓')
  ? const Color(0xFF2EA44F).withValues(alpha: 0.12)
      : const Color(0xFFE3B341).withValues(alpha: 0.12),
  borderRadius: BorderRadius.circular(8),
  border: Border.all(
  color: _fetchStatus.startsWith('✓')
  ? const Color(0xFF2EA44F).withValues(alpha: 0.4)
      : const Color(0xFFE3B341).withValues(alpha: 0.4),
  ),
  ),
  child: Row(children: [
  Icon(
  _fetchStatus.startsWith('✓') ? Icons.check_circle_outline : Icons.warning_amber_outlined,
  size: 14,
  color: _fetchStatus.startsWith('✓') ? const Color(0xFF2EA44F) : const Color(0xFFE3B341),
  ),
  const SizedBox(width: 6),
  Expanded(
  child: Text(_fetchStatus,
  style: TextStyle(
  color: _fetchStatus.startsWith('✓') ? const Color(0xFF2EA44F) : const Color(0xFFE3B341),
  fontSize: 12,
  )),
  ),
  ]),
  ),
  ],
  if (_err != null) ...[
  const SizedBox(height: 10),
  Text(_err!, style: const TextStyle(color: Color(0xFFF85149), fontSize: 13)),
  ],
  const SizedBox(height: 20),
  Row(children: [
  Expanded(child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Color(0xFF8B949E))))),
  const SizedBox(width: 12),
  Expanded(child: ElevatedButton(
  onPressed: _loading ? null : _save,
  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2EA44F), foregroundColor: Colors.white,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
  child: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
      : const Text('Add'),
  )),
  ]),
  ],
  );
  }
  }

// ─── Stock Action Dialog (Add + or Minus -) ────────────────────────────────────
  class _StockActionDialog extends StatefulWidget {
  final InventryModel item;
  final int scannedQty;
  const _StockActionDialog({required this.item, required this.scannedQty});
  @override
  State<_StockActionDialog> createState() => _StockActionDialogState();
  }

  class _StockActionDialogState extends State<_StockActionDialog> {
  late final TextEditingController _qtyCtrl;
  bool _loading = false;
  String? _err;

  @override
  void initState() {
  super.initState();
  _qtyCtrl = TextEditingController(text: widget.scannedQty.toString());
  }

  Future<void> _doAdd() async {
  final qty = int.tryParse(_qtyCtrl.text) ?? 0;
  if (qty <= 0) { setState(() => _err = 'Quantity must be > 0'); return; }
  setState(() { _loading = true; _err = null; });
  final auth = context.read<AuthProvider>();
  await context.read<InventoryProvider>().addQty(item: widget.item, qty: qty, userId: auth.userId);
  if (mounted) Navigator.pop(context);
  }

  Future<void> _doMinus() async {
  final qty = int.tryParse(_qtyCtrl.text) ?? 0;
  if (qty <= 0) { setState(() => _err = 'Quantity must be > 0'); return; }
  if (qty > widget.item.currentQty) { setState(() => _err = 'Only ${widget.item.currentQty} in stock'); return; }
  setState(() { _loading = true; _err = null; });
  final auth = context.read<AuthProvider>();
  await context.read<InventoryProvider>().minusQty(item: widget.item, qty: qty, userId: auth.userId);
  if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
  return _BaseDialog(
  title: 'Update Stock',
  icon: Icons.inventory_2_outlined,
  iconColor: const Color(0xFF58A6FF),
  children: [
  _infoRow('LCSC Part', widget.item.lcscPart),
  _infoRow('MPN Part', widget.item.mpnPart),
  if (widget.item.type.isNotEmpty)
  _infoRow('Type', widget.item.type),
  if (widget.item.package.isNotEmpty)
  _infoRow('Package', widget.item.package),
  _infoRow('Current Stock', '${widget.item.currentQty} pcs'),
  const SizedBox(height: 14),
  _tf(_qtyCtrl, 'Quantity', isNumber: true),
  if (_err != null) ...[
  const SizedBox(height: 8),
  Text(_err!, style: const TextStyle(color: Color(0xFFF85149), fontSize: 13)),
  ],
  const SizedBox(height: 20),
  if (_loading)
  const Center(child: CircularProgressIndicator(color: Color(0xFF2EA44F)))
  else
  Row(children: [
  Expanded(child: OutlinedButton.icon(
  onPressed: _doMinus,
  icon: const Icon(Icons.remove_circle_outline, color: Color(0xFFF85149)),
  label: const Text('Use (−)', style: TextStyle(color: Color(0xFFF85149))),
  style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFFF85149)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
  )),
  const SizedBox(width: 12),
  Expanded(child: ElevatedButton.icon(
  onPressed: _doAdd,
  icon: const Icon(Icons.add_circle_outline, color: Colors.white),
  label: const Text('Add (+)', style: TextStyle(color: Colors.white)),
  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2EA44F), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
  )),
  ]),
  const SizedBox(height: 8),
  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Color(0xFF8B949E)))),
  ],
  );
  }
  }
// ─── Edit Dialog ──────────────────────────────────────────────────────────────
  class _EditDialog extends StatefulWidget {
  final InventryModel item;
  const _EditDialog({required this.item});
  @override
  State<_EditDialog> createState() => _EditDialogState();
  }

  class _EditDialogState extends State<_EditDialog> {
  late final TextEditingController _mpnCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _pkgCtrl;
  late final TextEditingController _typeCtrl;
  late final TextEditingController _referelLinkCtrl;
  late final TextEditingController _currentPriceCtrl;
  late final TextEditingController _oldPriceCtrl;
  late final TextEditingController _inStockCtrl;
  final FocusNode _typeFocusNode = FocusNode();
  bool _loading = false;

  @override
  void initState() {
  super.initState();
  _mpnCtrl = TextEditingController(text: widget.item.mpnPart);
  _descCtrl = TextEditingController(text: widget.item.description);
  _pkgCtrl = TextEditingController(text: widget.item.package);
  _typeCtrl = TextEditingController(text: widget.item.type);
  _referelLinkCtrl = TextEditingController(text: widget.item.referelLink);
  _currentPriceCtrl = TextEditingController(text: widget.item.currentPrice);
  _oldPriceCtrl = TextEditingController(text: widget.item.oldPrice);
  _inStockCtrl = TextEditingController(text: widget.item.inStock.toString());
  }

  @override
  void dispose() {
  _mpnCtrl.dispose();
  _descCtrl.dispose();
  _pkgCtrl.dispose();
  _typeCtrl.dispose();
  _referelLinkCtrl.dispose();
  _currentPriceCtrl.dispose();
  _oldPriceCtrl.dispose();
  _inStockCtrl.dispose();
  _typeFocusNode.dispose();
  super.dispose();
  }

  Future<void> _save() async {
  final provider = context.read<InventoryProvider>();
  final ok = await showDialog<bool>(
  context: context,
  builder: (_) => AlertDialog(
  backgroundColor: const Color(0xFF161B22),
  title: const Text('Confirm Edit', style: TextStyle(color: Colors.white)),
  content: const Text('Save changes to this inventory item?',
  style: TextStyle(color: Color(0xFF8B949E))),
  actions: [
  TextButton(
  onPressed: () => Navigator.pop(context, false),
  child: const Text('Cancel', style: TextStyle(color: Color(0xFF8B949E))),
  ),
  ElevatedButton(
  onPressed: () => Navigator.pop(context, true),
  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2EA44F)),
  child: const Text('Save', style: TextStyle(color: Colors.white)),
  ),
  ],
  ),
  );
  if (ok != true) return;

  setState(() => _loading = true);
  await provider.editItem(
  id: widget.item.id!, mpn: _mpnCtrl.text, desc: _descCtrl.text,
  type: _typeCtrl.text.trim(),
  pkg: _pkgCtrl.text.trim(),
  referelLink: _referelLinkCtrl.text.trim(),
  currentPrice: _currentPriceCtrl.text.trim(),
  oldPrice: _oldPriceCtrl.text.trim(),
  inStock: int.tryParse(_inStockCtrl.text.trim()) ?? 0,
  );
  if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
  return _BaseDialog(
  title: 'Edit Part',
  icon: Icons.edit_outlined,
  iconColor: const Color(0xFF58A6FF),
  children: [
  _infoRow('LCSC Part', widget.item.lcscPart),
  const SizedBox(height: 12),
  _tf(_mpnCtrl, 'MPN Part'),
  const SizedBox(height: 12),
  _descriptionTf(_descCtrl),
  const SizedBox(height: 12),
  // Type autocomplete (select from list OR free-type)
  _typeAutoComplete(_typeCtrl, _typeFocusNode),
  const SizedBox(height: 12),
  _tf(_pkgCtrl, 'Package (e.g. 0402, SOT-23, SOIC-8)'),
  const SizedBox(height: 12),
  _tf(_referelLinkCtrl, 'Referel Link (e.g. LCSC / Datasheet URL)'),
  const SizedBox(height: 12),
  Row(children: [
  Expanded(child: _tf(_currentPriceCtrl, 'Current Price')),
  const SizedBox(width: 10),
  Expanded(child: _tf(_oldPriceCtrl, 'Old Price')),
  ]),
  const SizedBox(height: 20),
  Row(children: [
  Expanded(child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Color(0xFF8B949E))))),
  const SizedBox(width: 12),
  Expanded(child: ElevatedButton(
  onPressed: _loading ? null : _save,
  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF58A6FF), foregroundColor: Colors.white,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
  child: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
      : const Text('Save'),
  )),
  ]),
  ],
  );
  }
  }

// ─── Shared helpers ───────────────────────────────────────────────────────────
  class _BaseDialog extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final List<Widget> children;
  const _BaseDialog({required this.title, required this.icon, required this.iconColor, required this.children});

  @override
  Widget build(BuildContext context) {
  return Dialog(
  backgroundColor: const Color(0xFF161B22),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  child: Container(
  width: 400,
  constraints: const BoxConstraints(maxHeight: 780),
  padding: const EdgeInsets.all(24),
  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
  Row(children: [
  Icon(icon, color: iconColor, size: 22),
  const SizedBox(width: 10),
  Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
  ]),
  const SizedBox(height: 20),
  const Divider(color: Color(0xFF30363D), height: 1),
  const SizedBox(height: 16),
  Flexible(
  child: SingleChildScrollView(
  child: Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  mainAxisSize: MainAxisSize.min,
  children: children,
  ),
  ),
  ),
  ]),
  ),
  );
  }
  }

  Widget _infoRow(String label, String value) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 4),
  child: Row(children: [
  SizedBox(width: 110, child: Text('$label:', style: const TextStyle(color: Color(0xFF8B949E), fontSize: 13))),
  Expanded(child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500))),
  ]),
  );

  Widget _tf(TextEditingController ctrl, String label, {bool isNumber = false}) => TextField(
  controller: ctrl,
  keyboardType: isNumber ? TextInputType.number : TextInputType.text,
  style: const TextStyle(color: Colors.white, fontSize: 14),
  decoration: InputDecoration(
  labelText: label,
  labelStyle: const TextStyle(color: Color(0xFF8B949E), fontSize: 13),
  filled: true, fillColor: const Color(0xFF0D1117),
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF30363D))),
  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF30363D))),
  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF2EA44F))),
  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  ),
  );

  /// Taller Description field — 3 visible lines
  Widget _descriptionTf(TextEditingController ctrl) => TextField(
  controller: ctrl,
  maxLines: 3,
  minLines: 3,
  style: const TextStyle(color: Colors.white, fontSize: 14),
  decoration: const InputDecoration(
  labelText: 'Description',
  labelStyle: TextStyle(color: Color(0xFF8B949E), fontSize: 13),
  alignLabelWithHint: true,
  filled: true,
  fillColor: Color(0xFF0D1117),
  border: OutlineInputBorder(
  borderRadius: BorderRadius.all(Radius.circular(8)),
  borderSide: BorderSide(color: Color(0xFF30363D))),
  enabledBorder: OutlineInputBorder(
  borderRadius: BorderRadius.all(Radius.circular(8)),
  borderSide: BorderSide(color: Color(0xFF30363D))),
  focusedBorder: OutlineInputBorder(
  borderRadius: BorderRadius.all(Radius.circular(8)),
  borderSide: BorderSide(color: Color(0xFF2EA44F))),
  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  ),
  );

  /// Type autocomplete — select from list OR free-type
  Widget _typeAutoComplete(TextEditingController ctrl, FocusNode focusNode) {
  return RawAutocomplete<String>(
  textEditingController: ctrl,
  focusNode: focusNode,
  optionsBuilder: (TextEditingValue tv) {
  if (tv.text.isEmpty) return _kComponentTypes;
  return _kComponentTypes.where(
  (t) => t.toLowerCase().contains(tv.text.toLowerCase()));
  },
  fieldViewBuilder: (ctx, controller, focusNode, onFieldSubmitted) =>
  TextField(
  controller: controller,
  focusNode: focusNode,
  style: const TextStyle(color: Colors.white, fontSize: 14),
  decoration: const InputDecoration(
  labelText: 'Type (select or type)',
  labelStyle: TextStyle(color: Color(0xFF8B949E), fontSize: 13),
  filled: true,
  fillColor: Color(0xFF0D1117),
  border: OutlineInputBorder(
  borderRadius: BorderRadius.all(Radius.circular(8)),
  borderSide: BorderSide(color: Color(0xFF30363D))),
  enabledBorder: OutlineInputBorder(
  borderRadius: BorderRadius.all(Radius.circular(8)),
  borderSide: BorderSide(color: Color(0xFF30363D))),
  focusedBorder: OutlineInputBorder(
  borderRadius: BorderRadius.all(Radius.circular(8)),
  borderSide: BorderSide(color: Color(0xFFBC8CFF))),
  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  ),
  ),
  optionsViewBuilder: (ctx, onSelected, options) => Align(
  alignment: Alignment.topLeft,
  child: Material(
  color: const Color(0xFF161B22),
  elevation: 4,
  borderRadius: BorderRadius.circular(8),
  child: ConstrainedBox(
  constraints: const BoxConstraints(maxHeight: 230, maxWidth: 352),
  child: ListView.builder(
  padding: EdgeInsets.zero,
  shrinkWrap: true,
  itemCount: options.length,
  itemBuilder: (_, i) {
  final opt = options.elementAt(i);
  return InkWell(
  onTap: () => onSelected(opt),
  child: Padding(
  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
  child: Text(opt,
  style: const TextStyle(color: Colors.white, fontSize: 14)),
  ),
  );
  },
  ),
  ),
  ),
  ),
  onSelected: (val) => ctrl.text = val,
  );
  }

