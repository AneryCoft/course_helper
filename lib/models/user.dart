class User {
  final String name;
  final String avatar;
  final String phone;
  final String uid;

  User({
    required this.name,
    required this.avatar,
    required this.phone,
    required this.uid,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
        name: json['name'] ?? '未知用户',
        avatar: json['avatar'] ?? '',
        phone: json['phone'] ?? '未知手机号',
        uid: json['uid'] ?? ''
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'avatar': avatar,
      'phone': phone,
      'uid': uid
    };
  }

  @override
  String toString() {
    return 'User{name: $name, uid: $uid}';
  }
}