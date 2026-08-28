// lib/models/app_user.dart

enum UserRole { guest, member, staff, partner, admin }

extension UserRoleExtension on UserRole {
  String get label {
    switch (this) {
      case UserRole.guest:
        return '비회원';
      case UserRole.member:
        return '일반 회원';
      case UserRole.staff:
        return '관리자(직원)';
      case UserRole.partner:
        return '협력/파트너사';
      case UserRole.admin:
        return '관리자(총괄)';
    }
  }

  bool get isLoggedIn => this != UserRole.guest;
  bool get canSeeAllShipments =>
      this == UserRole.staff || this == UserRole.partner || this == UserRole.admin;
  bool get canAccessAdmin => this == UserRole.admin;
  bool get canManageCargo =>
      this == UserRole.staff || this == UserRole.partner || this == UserRole.admin;
  bool get canEditSchedules => this == UserRole.staff || this == UserRole.admin;
  bool get canEditNotices => this == UserRole.staff || this == UserRole.admin;
  bool get canEditCargoAnytime =>
      this == UserRole.partner || this == UserRole.admin;
  bool get canApproveChanges => this == UserRole.admin;
  bool get canRequestOwnCargoCorrection => this == UserRole.member;
  bool get cargoEditRequiresApproval => this == UserRole.staff;
}

class AppUser {
  final String id, email, name, phone, countryCode, address, company;
  final String? avatarUrl;
  final UserRole role;

  String get displayName => name;
  String get companyName => company;
  String get roleLabel => role.label;

  const AppUser({
    this.id = '',
    this.email = '',
    String? name,
    String? displayName,
    this.phone = '',
    this.countryCode = '+82',
    this.address = '',
    String? company,
    String? companyName,
    this.avatarUrl,
    this.role = UserRole.guest,
  })  : name = name ?? displayName ?? '',
        company = company ?? companyName ?? '';

  factory AppUser.fromMap(Map<String, dynamic> map) {
    final roleValue = map['role']?.toString() ?? 'member';
    final parsedRole = UserRole.values.firstWhere(
      (item) => item.name == roleValue,
      orElse: () => UserRole.member,
    );
    return AppUser(
      id: (map['id'] ?? map['user_id'] ?? '').toString(),
      email: (map['email'] ?? '').toString(),
      name: (map['name'] ?? map['full_name'] ?? '').toString(),
      phone: (map['phone'] ?? '').toString(),
      countryCode: (map['country_code'] ?? '+82').toString(),
      address: (map['address'] ?? '').toString(),
      company: (map['company'] ?? '').toString(),
      avatarUrl: map['avatar_url']?.toString(),
      role: parsedRole,
    );
  }

  AppUser copyWith({
    String? id,
    String? email,
    String? name,
    String? phone,
    String? countryCode,
    String? address,
    String? company,
    String? avatarUrl,
    UserRole? role,
  }) =>
      AppUser(
        id: id ?? this.id,
        email: email ?? this.email,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        countryCode: countryCode ?? this.countryCode,
        address: address ?? this.address,
        company: company ?? this.company,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        role: role ?? this.role,
      );

  Map<String, dynamic> toProfileMap() => {
        'id': id,
        'email': email,
        'name': name,
        'phone': phone,
        'country_code': countryCode,
        'address': address,
        'company': company,
        'role': role.name,
      };
}

class AccountProvisionRequest {
  const AccountProvisionRequest({
    required this.name,
    required this.email,
    required this.role,
    this.company = '',
    this.phone = '',
  });

  final String name, email, company, phone;
  final UserRole role;

  Map<String, dynamic> toMap() => {
        'name': name,
        'email': email,
        'role': role.name,
        'company': company,
        'phone': phone,
        'status': 'pending',
      };
}

class AuthException implements Exception {
  const AuthException(this.message);
  final String message;

  @override
  String toString() => message;
}

class AuthResult {
  const AuthResult({
    required this.user,
    required this.emailConfirmationRequired,
  });
  final AppUser user;
  final bool emailConfirmationRequired;
}

class MockAccountInfo {
  const MockAccountInfo({
    required this.label,
    required this.email,
    required this.password,
    required this.role,
  });

  final String label, email, password;
  final UserRole role;
}
