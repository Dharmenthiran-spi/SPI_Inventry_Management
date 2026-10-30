import 'dart:convert';
import 'package:http/http.dart' as http;

class LcscProductInfo {
  final String package;
  final String description;
  final int inStock;
  final String unitPrice;
  final String url;

  const LcscProductInfo({
    required this.package,
    required this.description,
    required this.inStock,
    required this.unitPrice,
    required this.url,
  });
}

class LcscService {
  /// Fetches product details for [lcscPart] (e.g. "C4747971") from LCSC.
  /// Returns null if the part is not found or fetch fails.
  static Future<LcscProductInfo?> fetch(String lcscPart) async {
    final part = lcscPart.trim().toUpperCase();
    if (part.isEmpty) return null;

    final url = 'https://www.lcsc.com/product-detail/$part.html';
    try {
      final resp = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
              'AppleWebKit/537.36 (KHTML, like Gecko) '
              'Chrome/124.0 Safari/537.36',
          'Accept-Language': 'en-US,en;q=0.9',
        },
      ).timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) return null;
      return _parse(resp.body, url);
    } catch (_) {
      return null;
    }
  }

  static LcscProductInfo? _parse(String html, String url) {
    // 1. Try embedded JSON (__NEXT_DATA__ or window.__INITIAL_STATE__)
    final nextData = _extractNextData(html);
    if (nextData != null) {
      final info = _parseNextData(nextData, url);
      if (info != null) return info;
    }

    // 2. Fallback: plain text scraping
    return _parseViaTextSearch(html, url);
  }

  // ---------------------------------------------------------------------------
  // Next.js embedded JSON
  // ---------------------------------------------------------------------------
  static Map<String, dynamic>? _extractNextData(String html) {
    final tag = '__NEXT_DATA__';
    final start = html.indexOf(tag);
    if (start < 0) return null;
    // find opening { after the script tag close >
    final braceStart = html.indexOf('{', start + tag.length);
    if (braceStart < 0) return null;
    // Find matching closing } by counting braces
    int depth = 0;
    int end = -1;
    for (int i = braceStart; i < html.length; i++) {
      if (html[i] == '{') { depth++; }
      else if (html[i] == '}') {
        depth--;
        if (depth == 0) { end = i; break; }
      }
    }
    if (end < 0) return null;
    try {
      return jsonDecode(html.substring(braceStart, end + 1)) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static LcscProductInfo? _parseNextData(Map<String, dynamic> data, String url) {
    try {
      final props = data['props'];
      if (props == null) return null;
      final pageProps = props['pageProps'];
      if (pageProps == null) return null;

      final product = pageProps['webData']
          ?? pageProps['product']
          ?? pageProps['productInfo']
          ?? pageProps['detail']
          ?? (pageProps['data'] is Map ? pageProps['data']['product'] : null);

      if (product == null) {
        print('🔍 LCSC [NextDataParser]: Could not find a product map/webData in pageProps.');
        return null;
      }

      print('🔍 LCSC [NextDataParser] SUCCESS: Found product data.');
      print('   • Product properties available: ${product.keys.toList()}');
      print('   • Raw Packaging: ${product['packaging']} / encapStandard: ${product['encapStandard']}');
      print('   • Raw Package: ${product['package']}');
      print('   • Raw Attributes (Desc): ${product['attributes']} / productKeyAttributes: ${product['productKeyAttributes']}');
      print('   • Raw Stock Count: ${product['stockCount']} / Stock: ${product['stock']} / stockNumber: ${product['stockNumber']}');
      print('   • Raw Prices: ${product['productPriceList'] ?? product['productPrices'] ?? product['prices']}');

      final String pkg  = _str(product['encapStandard'])
                        ?? _str(product['packaging'])
                        ?? _str(product['package'])
                        ?? '';
      final String desc = _str(product['productKeyAttributes'])
                        ?? _str(product['attributes'])
                        ?? _str(product['description'])
                        ?? _str(product['productIntroEn'])
                        ?? _str(product['productIntro'])
                        ?? '';
      final int stock   = _int(product['stockNumber'])
                        ?? _int(product['totalStock'])
                        ?? _int(product['availStock'])
                        ?? _int(product['stockCount'])
                        ?? _int(product['hkStockNumber'])
                        ?? _int(product['szStockNumber'])
                        ?? _int(product['wmStockNumber'])
                        ?? _int(product['stockQuantity'])
                        ?? _int(product['stock'])
                        ?? _int(product['inventory'])
                        ?? (product['stockInfo'] is Map ? (_int(product['stockInfo']['stockNumber']) ?? _int(product['stockInfo']['totalStock'])) : null)
                        ?? 0;
      final String price = _extractPrice(product);

      print('🔍 LCSC [NextDataParser] Mapped Values:');
      print('   • pkg: "$pkg"');
      print('   • desc: "$desc"');
      print('   • stock: $stock');
      print('   • price: "$price"');

      return LcscProductInfo(
        package: pkg,
        description: desc,
        inStock: stock,
        unitPrice: price,
        url: url,
      );
    } catch (e) {
      print('🔍 LCSC [NextDataParser] ERROR: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Plain-text fallback
  // ---------------------------------------------------------------------------
  static LcscProductInfo? _parseViaTextSearch(String html, String url) {
    String pkg   = '';
    String desc  = '';
    int  stock   = 0;
    String price = '';

    // In-Stock: robust case-insensitive regex for various stock labels
    final stockRe = RegExp(
      r'(?:In-Stock|In Stock|Stock Count|Stock Qty|Stock Quantity|Available Stock|Availability)[\s:]*([0-9][0-9,]*)',
      caseSensitive: false,
    );
    final sm = stockRe.firstMatch(html);
    if (sm != null) {
      stock = int.tryParse(sm.group(1)!.replaceAll(',', '')) ?? 0;
    }

    // Packaging
    final pkgRe = RegExp(
      r'(?:Packaging|Package)[\s>:]*([A-Za-z0-9][A-Za-z0-9 ,.\-/]{1,60})',
      caseSensitive: false,
    );
    final pm = pkgRe.firstMatch(html);
    if (pm != null) {
      pkg = pm.group(1)!.trim();
    }

    // Key Attributes / Description
    final attrRe = RegExp(
      r'(?:Key Attributes|Description)[\s>:]*([A-Z0-9][^\n<"]{3,120})',
      caseSensitive: false,
    );
    final am = attrRe.firstMatch(html);
    if (am != null) {
      desc = am.group(1)!.trim();
    }

    // Unit Price — look for dollar amounts
    final priceRe = RegExp(r'\$\s*([0-9]+\.[0-9]+)');
    final prm = priceRe.firstMatch(html);
    if (prm != null) price = '\$${prm.group(1)!}';

    print('🔍 LCSC [TextSearchParser] Parsed Values:');
    print('   • pkg: "$pkg"');
    print('   • desc: "$desc"');
    print('   • stock: $stock');
    print('   • price: "$price"');

    if (pkg.isEmpty && desc.isEmpty && stock == 0 && price.isEmpty) {
      print('🔍 LCSC [TextSearchParser] FAILED: All parsed values are empty.');
      return null;
    }

    return LcscProductInfo(
      package: pkg,
      description: desc,
      inStock: stock,
      unitPrice: price,
      url: url,
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------
  static String? _str(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  static int? _int(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse(v.toString().replaceAll(',', ''));
  }

  static String _extractPrice(Map<String, dynamic> product) {
    final prices = product['productPriceList'] ?? product['productPrices'] ?? product['prices'] ?? product['priceList'];
    if (prices is List && prices.isNotEmpty) {
      try {
        final sorted = List<Map>.from(prices)
          ..sort((a, b) =>
              (_int(a['ladder'] ?? a['startQty'] ?? a['minQty'] ?? a['qty']) ?? 999999)
                  .compareTo(_int(b['ladder'] ?? b['startQty'] ?? b['minQty'] ?? b['qty']) ?? 999999));
        final first = sorted.first;
        final up = first['discountPrice'] ?? first['price'] ?? first['productPrice'] ?? first['usdPrice'] ?? first['unitPrice'] ?? first['currencyPrice'];
        if (up != null) return '\$${_formatPrice(up)}';
      } catch (_) {}
    }
    final simple = product['price'] ?? product['unitPrice'] ?? product['usdPrice'];
    if (simple != null) return '\$${_formatPrice(simple)}';
    return '';
  }

  static String _formatPrice(dynamic v) {
    if (v is double) return v.toStringAsFixed(4);
    if (v is int)    return v.toStringAsFixed(2);
    final d = double.tryParse(v.toString());
    return d != null ? d.toStringAsFixed(4) : v.toString();
  }
}
