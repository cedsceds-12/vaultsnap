/// Thrown when entry CRUD needs the VMK but the vault is locked.
class VaultLockedError implements Exception {
  const VaultLockedError();

  @override
  String toString() => 'Vault is locked';
}
