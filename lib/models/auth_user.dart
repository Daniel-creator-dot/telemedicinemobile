import 'role.dart';

class AuthUser {
  const AuthUser({
    required this.id,
    required this.username,
    required this.name,
    required this.role,
    this.phoneNumber,
    this.email,
    this.patientCode,
    this.patientId,
  });

  final String id;
  final String username;
  final String name;
  final AppRole role;
  final String? phoneNumber;
  final String? email;
  final String? patientCode;
  final int? patientId;

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      role: AppRole.fromString(json['role']?.toString()),
      phoneNumber: json['phone_number']?.toString(),
      email: json['email']?.toString(),
      patientCode: json['patient_code']?.toString(),
      patientId: json['patient_id'] is int
          ? json['patient_id'] as int
          : int.tryParse(json['patient_id']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'name': name,
        'role': role.name,
        if (phoneNumber != null) 'phone_number': phoneNumber,
        if (email != null) 'email': email,
        if (patientCode != null) 'patient_code': patientCode,
        if (patientId != null) 'patient_id': patientId,
      };

  AuthUser copyWith({
    String? name,
    String? phoneNumber,
    String? email,
    String? patientCode,
    int? patientId,
  }) {
    return AuthUser(
      id: id,
      username: username,
      name: name ?? this.name,
      role: role,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      email: email ?? this.email,
      patientCode: patientCode ?? this.patientCode,
      patientId: patientId ?? this.patientId,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AuthUser && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
