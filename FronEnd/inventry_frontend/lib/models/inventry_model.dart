class InventryModel {
  final int? id;
  final String lcscPart;
  final String mpnPart;
  final String description;
  final String type;
  final String package;
  final int currentQty;
  final int usedQty;
  final int inStock;
  final String referelLink;
  final String currentPrice;
  final String oldPrice;
  final DateTime? createdDate;
  final DateTime? lastUpdated;

  InventryModel({
    this.id,
    required this.lcscPart,
    required this.mpnPart,
    required this.description,
    required this.type,
    required this.package,
    required this.currentQty,
    required this.usedQty,
    this.inStock = 0,
    this.referelLink = '',
    this.currentPrice = '',
    this.oldPrice = '',
    this.createdDate,
    this.lastUpdated,
  });

  factory InventryModel.fromMap(Map<String, dynamic> map) {
    return InventryModel(
      id: map['ID'] != null ? int.tryParse(map['ID'].toString()) : null,
      lcscPart: map['LCSCPart']?.toString() ?? '',
      mpnPart: map['MPNPart']?.toString() ?? '',
      description: map['Description']?.toString() ?? '',
      type: map['Type']?.toString() ?? '',
      package: map['Package']?.toString() ?? '',
      currentQty: int.tryParse(map['CurrentQTY']?.toString() ?? '0') ?? 0,
      usedQty: int.tryParse(map['UsedQTY']?.toString() ?? '0') ?? 0,
      inStock: int.tryParse(map['InStock']?.toString() ?? '0') ?? 0,
      referelLink: map['ReferelLink']?.toString() ?? '',
      currentPrice: map['CurrentPrice']?.toString() ?? '',
      oldPrice: map['OldPrice']?.toString() ?? '',
      createdDate: map['CreatedDate'] != null
          ? DateTime.tryParse(map['CreatedDate'].toString())
          : null,
      lastUpdated: map['LastUpdatedDateTime'] != null
          ? DateTime.tryParse(map['LastUpdatedDateTime'].toString())
          : null,
    );
  }
}
