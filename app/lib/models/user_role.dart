enum UserRole { consumer, manufacturer, distributor, pharmacy, admin }

extension UserRoleDetails on UserRole {
  String get title {
    switch (this) {
      case UserRole.consumer:
        return 'Consumer';
      case UserRole.manufacturer:
        return 'Manufacturer';
      case UserRole.distributor:
        return 'Distributor';
      case UserRole.pharmacy:
        return 'Pharmacy';
      case UserRole.admin:
        return 'Administrator';
    }
  }

  String get description {
    switch (this) {
      case UserRole.consumer:
        return 'Scan a medicine and check its authenticity.';
      case UserRole.manufacturer:
        return 'Manage medicine registration and batches.';
      case UserRole.distributor:
        return 'View medicine movement through the supply chain.';
      case UserRole.pharmacy:
        return 'Review medicines and their verification details.';
      case UserRole.admin:
        return 'Manage organization approvals and authorized platform operations.';
    }
  }

  bool get isSupplyChainOrganization =>
      this == UserRole.manufacturer ||
      this == UserRole.distributor ||
      this == UserRole.pharmacy;

  bool get isPlatformAdmin => this == UserRole.admin;
}
