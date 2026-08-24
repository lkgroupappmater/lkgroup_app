// lib/models/app_user.dart

enum UserRole { guest, member, staff, partner, admin }

extension UserRoleExtension on UserRole {
  String get label {
    switch (this) {
      case UserRole.guest:
        return 'Guest';
      case UserRole.member:
        return 'Member';
      case UserRole.staff:
        return 'Staff';
      case UserRole.partner:
        return 'Partner';
      case UserRole.admin:
        return 'Admin';
    }
  }

  bool get isLoggedIn {
    switch (this) {
      case UserRole.guest:
        return false;
      case UserRole.member:
      case UserRole.staff:
      case UserRole.partner:
      case UserRole.admin:
        return true;
    }
  }

  bool get canSeeAllShipments {
    switch (this) {
      case UserRole.staff:
      case UserRole.admin:
        return true;
      case UserRole.guest:
      case UserRole.member:
      case UserRole.partner:
        return false;
    }
  }

  bool get canAccessAdmin {
    switch (this) {
      case UserRole.admin:
        return true;
      case UserRole.guest:
      case UserRole.member:
      case UserRole.staff:
      case UserRole.partner:
        return false;
    }
  }
}

class AppUser {
  final String id;
  final String email;
  final String name;
  final String phone;
  final String company;
  final String? avatarUrl;
  final UserRole role;

  /// Aliases kept for call-site compatibility.
  String get displayName => name;
  String get companyName => company;
  String get roleLabel => role.label;

  const AppUser({
    this.id = '',
    this.email = '',
    String? name,
    String? displayName,
    this.phone = '',
    String? company,
    String? companyName,
    this.avatarUrl,
    this.role = UserRole.guest,
  })  : name = name ?? displayName ?? '',
        company = company ?? companyName ?? '';

  AppUser copyWith({
    String? id,
    String? email,
    String? name,
    String? phone,
    String? company,
    String? avatarUrl,
    UserRole? role,
  }) {
    return AppUser(
      id: id ?? this.id,
      email: email ?? this.email,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      company: company ?? this.company,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      role: role ?? this.role,
    );
  }

  @override
  String toString() =>
      'AppUser(id: $id, email: $email, name: $name, role: $role)';
}
