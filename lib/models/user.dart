class User {
  final String name;
  final String avatar;
  final String phone;
  final String uid;
  final String school;
  final String platform;

  User({
    required this.name,
    required this.avatar,
    required this.phone,
    required this.uid,
    required this.school,
    this.platform = 'chaoxing'
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
        name: json['name'] ?? '未知用户',
        avatar: json['avatar'] ?? '',
        phone: json['phone'] ?? '未知手机号',
        uid: json['uid'] ?? '0',
        school: json['school'] ?? '未知学校',
        platform: json['platform'] ?? 'chaoxing'
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'avatar': avatar,
      'phone': phone,
      'uid': uid,
      'school': school,
      'platform': platform
    };
  }

  bool get isChaoxing => platform == 'chaoxing';
  bool get isRainClassroom => platform == 'rainClassroom';
}