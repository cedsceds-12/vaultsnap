package com.vaultsnap.app.autofill.save

/**
 * Cleartext save-request payload extracted from a [android.service.autofill.SaveRequest].
 *
 * Lifetime: created when the framework asks "save this login?", encrypted
 * (Android Keystore AES-GCM) before being written to SharedPreferences,
 * decrypted later when the Dart side consumes the queue. Never written to
 * disk in cleartext.
 */
internal data class SavePayload(
    val username: String?,
    val password: String,
    val callerPackage: String?,
    val webHost: String?,
    val createdAtMs: Long,
)
