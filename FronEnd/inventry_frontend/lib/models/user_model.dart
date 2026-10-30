class UserModel {
  final int? id;
  final String name;
  final String userName;
  final String passWord;

  UserModel({this.id, required this.name, required this.userName, required this.passWord});

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['ID'] != null ? int.tryParse(map['ID'].toString()) : null,
      name: map['Name']?.toString() ?? '',
      userName: map['UserName']?.toString() ?? '',
      passWord: map['PassWord']?.toString() ?? '',
    );
  }
}
