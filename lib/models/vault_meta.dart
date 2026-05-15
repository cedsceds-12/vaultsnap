import 'dart:convert';
import 'dart:typed_data';

/// Argon2id key-derivation parameters.
///
/// These are stored alongside the vault so future versions can adjust the
/// memory/iteration cost without breaking existing vaults — verification
/// always uses the params recorded at setup time.
class KdfParams {
  static const String argon2id = 'argon2id';

  final String name;
  final int memKiB;
  final int iterations;
  final int parallelism;

  const KdfParams({
    required this.name,
    required this.memKiB,
    required this.iterations,
    required this.parallelism,
  });

  /// Default params: 64 MiB memory, 3 iterations, single-threaded.
  /// Yields ~500-1500ms derivations on real Android hardware — slow
  /// enough to neuter brute-force, fast enough to feel responsive.
  static const KdfParams defaults = KdfParams(
    name: argon2id,
    memKiB: 65536,
    iterations: 3,
    parallelism: 1,
  );

  Map<String, dynamic> toJson() => {
        'name': name,
        'memKiB': memKiB,
        'iterations': iterations,
        'parallelism': parallelism,
      };

  factory KdfParams.fromJson(Map<String, dynamic> json) => KdfParams(
        name: json['name'] as String,
        memKiB: json['memKiB'] as int,
        iterations: json['iterations'] as int,
        parallelism: json['parallelism'] as int,
      );
}

/// AES-GCM ciphertext + nonce + auth tag.
///
/// Used to "wrap" the Vault Master Key (VMK) under one or more derived
/// keys (master-password key, recovery-answer key, biometric-keystore
/// key). Each unlock path produces its own [WrappedSecret].
class WrappedSecret {
  final Uint8List nonce;
  final Uint8List ciphertext;
  final Uint8List mac;

  const WrappedSecret({
    required this.nonce,
    required this.ciphertext,
    required this.mac,
  });

  Map<String, dynamic> toJson() => {
        'nonce': base64Encode(nonce),
        'ciphertext': base64Encode(ciphertext),
        'mac': base64Encode(mac),
      };

  factory WrappedSecret.fromJson(Map<String, dynamic> json) => WrappedSecret(
        nonce: base64Decode(json['nonce'] as String),
        ciphertext: base64Decode(json['ciphertext'] as String),
        mac: base64Decode(json['mac'] as String),
      );

  /// Redacted toString — never dumps ciphertext / nonce / mac bytes.
  /// A WrappedSecret object accidentally logged or included in an
  /// exception trace would otherwise leak the ciphertext envelope,
  /// which doesn't break the encryption but does signal vault internals.
  @override
  String toString() => 'WrappedSecret(<redacted>)';
}

/// Recovery question metadata. The answer itself is never stored —
/// only its salt + the recovery-wrapped VMK.
class RecoveryMeta {
  final String question;
  final Uint8List salt;
  final int normalizationVersion;

  const RecoveryMeta({
    required this.question,
    required this.salt,
    this.normalizationVersion = 1,
  });

  Map<String, dynamic> toJson() => {
        'question': question,
        'salt': base64Encode(salt),
        'normalizationVersion': normalizationVersion,
      };

  factory RecoveryMeta.fromJson(Map<String, dynamic> json) => RecoveryMeta(
        question: json['question'] as String,
        salt: base64Decode(json['salt'] as String),
        normalizationVersion: json['normalizationVersion'] as int? ?? 1,
      );

  /// Redacted toString — keeps the public question text (already on disk
  /// in cleartext, shown on the unlock screen) but never dumps the salt.
  @override
  String toString() => 'RecoveryMeta(question: $question, '
      'normalizationVersion: $normalizationVersion)';
}

/// Top-level on-disk vault descriptor. Contains everything needed to
/// authenticate the user and recover the Vault Master Key — but never
/// the master password, the recovery answer, or the VMK itself in the
/// clear.
class VaultMeta {
  static const int currentVersion = 1;

  final int version;
  final KdfParams kdf;
  final Uint8List passwordSalt;
  final WrappedSecret wrappedVmkPassword;
  final WrappedSecret wrappedVmkRecovery;
  final WrappedSecret? wrappedVmkBiometric;
  final RecoveryMeta recovery;
  final DateTime createdAt;
  final DateTime? lastUnlockAt;

  const VaultMeta({
    required this.version,
    required this.kdf,
    required this.passwordSalt,
    required this.wrappedVmkPassword,
    required this.wrappedVmkRecovery,
    required this.wrappedVmkBiometric,
    required this.recovery,
    required this.createdAt,
    required this.lastUnlockAt,
  });

  bool get hasBiometric => wrappedVmkBiometric != null;

  VaultMeta copyWith({
    WrappedSecret? wrappedVmkPassword,
    WrappedSecret? wrappedVmkRecovery,
    WrappedSecret? wrappedVmkBiometric,
    bool clearBiometric = false,
    RecoveryMeta? recovery,
    DateTime? lastUnlockAt,
  }) {
    return VaultMeta(
      version: version,
      kdf: kdf,
      passwordSalt: passwordSalt,
      wrappedVmkPassword: wrappedVmkPassword ?? this.wrappedVmkPassword,
      wrappedVmkRecovery: wrappedVmkRecovery ?? this.wrappedVmkRecovery,
      wrappedVmkBiometric: clearBiometric
          ? null
          : (wrappedVmkBiometric ?? this.wrappedVmkBiometric),
      recovery: recovery ?? this.recovery,
      createdAt: createdAt,
      lastUnlockAt: lastUnlockAt ?? this.lastUnlockAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'kdf': kdf.toJson(),
        'passwordSalt': base64Encode(passwordSalt),
        'wrappedVmkPassword': wrappedVmkPassword.toJson(),
        'wrappedVmkRecovery': wrappedVmkRecovery.toJson(),
        'wrappedVmkBiometric': wrappedVmkBiometric?.toJson(),
        'recovery': recovery.toJson(),
        'createdAt': createdAt.toUtc().toIso8601String(),
        'lastUnlockAt': lastUnlockAt?.toUtc().toIso8601String(),
      };

  factory VaultMeta.fromJson(Map<String, dynamic> json) => VaultMeta(
        version: json['version'] as int,
        kdf: KdfParams.fromJson(json['kdf'] as Map<String, dynamic>),
        passwordSalt: base64Decode(json['passwordSalt'] as String),
        wrappedVmkPassword: WrappedSecret.fromJson(
            json['wrappedVmkPassword'] as Map<String, dynamic>),
        wrappedVmkRecovery: WrappedSecret.fromJson(
            json['wrappedVmkRecovery'] as Map<String, dynamic>),
        wrappedVmkBiometric: json['wrappedVmkBiometric'] == null
            ? null
            : WrappedSecret.fromJson(
                json['wrappedVmkBiometric'] as Map<String, dynamic>),
        recovery:
            RecoveryMeta.fromJson(json['recovery'] as Map<String, dynamic>),
        createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
        lastUnlockAt: json['lastUnlockAt'] == null
            ? null
            : DateTime.parse(json['lastUnlockAt'] as String).toUtc(),
      );

  /// Redacted toString — VaultMeta itself isn't a key, but contains
  /// every wrap and salt. Default Dart toString would dump the entire
  /// object graph (including base64-encoded ciphertext) into any log
  /// or exception trace that prints it.
  @override
  String toString() => 'VaultMeta(version: $version, '
      'kdf: ${kdf.name}, hasBiometric: $hasBiometric, '
      'createdAt: $createdAt)';
}
