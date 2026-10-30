class EventModel {
  final int id;
  final int stockId;
  final String action;
  final int qty;
  final DateTime dateTime;
  final int userId;

  // Joined fields for easy display
  final String lcscPart;
  final String mpnPart;
  final String package;
  final String userName;

  EventModel({
    required this.id,
    required this.stockId,
    required this.action,
    required this.qty,
    required this.dateTime,
    required this.userId,
    required this.lcscPart,
    required this.mpnPart,
    required this.package,
    required this.userName,
  });

  factory EventModel.fromMap(Map<String, dynamic> map) {
    return EventModel(
      id: map['ID'] != null ? int.tryParse(map['ID'].toString()) ?? 0 : 0,
      stockId: map['StockID'] != null ? int.tryParse(map['StockID'].toString()) ?? 0 : 0,
      action: map['Action']?.toString() ?? '',
      qty: map['QTY'] != null ? int.tryParse(map['QTY'].toString()) ?? 0 : 0,
      dateTime: map['DateTime'] != null
          ? DateTime.tryParse(map['DateTime'].toString()) ?? DateTime.now()
          : DateTime.now(),
      userId: map['UserID'] != null ? int.tryParse(map['UserID'].toString()) ?? 0 : 0,
      lcscPart: map['LCSCPart']?.toString() ?? '',
      mpnPart: map['MPNPart']?.toString() ?? '',
      package: map['Package']?.toString() ?? '',
      userName: map['UserName']?.toString() ?? '',
    );
  }
}

