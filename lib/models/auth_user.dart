import 'role.dart';

class AuthUser {
  const AuthUser({
    required this.id,
    required this.username,
    required this.name,
    required this.role,
    this.phoneNumber,
  });

  final String id;
  final String username;
  final String name;
  final AppRole role;
  final String? phoneNumber;

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      role: AppRole.fromString(json['role']?.toString()),
      phoneNumber: json['phone_number']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'name': name,
        'role': role.name,
        if (phoneNumber != null) 'phone_number': phoneNumber,
      };

  AuthUser copyWith({
    String? name,
    String? phoneNumber,
  }) {
    return AuthUser(
      id: id,
      username: username,
      name: name ?? this.name,
      role: role,
      phoneNumber: phoneNumber ?? this.phoneNumber,
    );
  }
}
