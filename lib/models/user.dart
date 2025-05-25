class AppUser {
  final String id;
  final String email;
  final String displayName;

  AppUser({
    required this.id,
    required this.email,
    required this.displayName,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'email': email,
      'displayName': displayName,
    };
  }

  factory AppUser.fromMap(Map<String, dynamic> map) {
    return AppUser(
      id: map['id'] as String,
      email: map['email'] as String,
      displayName: map['displayName'] as String,
    );
  }
}