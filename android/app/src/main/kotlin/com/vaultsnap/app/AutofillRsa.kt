package com.vaultsnap.app

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.spec.MGF1ParameterSpec
import javax.crypto.Cipher
import javax.crypto.spec.OAEPParameterSpec
import javax.crypto.spec.PSource

internal object AutofillRsa {
    // RSA-OAEP with SHA-256 OAEP digest + SHA-1 MGF1.
    // Android Keystore (keystore2 / API 31+) only authorizes SHA-1 for MGF1
    // by default; setMgf1Digests was only added in API 34. RFC 8017 explicitly
    // permits a different MGF1 hash from the OAEP hash, so SHA-256 + SHA-1
    // MGF1 is a valid, secure combination that works on every supported API.
    //
    // v1 alias used SHA-256 MGF1 → INCOMPATIBLE_MGF_DIGEST on keystore2.
    // v2 alias attempted setMgf1Digests → silently ineffective on most APIs.
    // v3 keys match the OAEP_PARAMS below; abandon both legacy aliases.
    private const val LEGACY_ALIAS_V1 = "vaultsnap_autofill_rsa"
    private const val LEGACY_ALIAS_V2 = "vaultsnap_autofill_rsa_v2"
    private const val ALIAS = "vaultsnap_autofill_rsa_v3"
    private val OAEP_PARAMS = OAEPParameterSpec(
        "SHA-256",
        "MGF1",
        MGF1ParameterSpec.SHA1,
        PSource.PSpecified.DEFAULT,
    )

    fun ensureKey(androidKeystore: KeyStore = loadKeystore()) {
        // Clean up incompatible legacy keys.
        for (legacy in arrayOf(LEGACY_ALIAS_V1, LEGACY_ALIAS_V2)) {
            if (androidKeystore.containsAlias(legacy)) {
                try {
                    androidKeystore.deleteEntry(legacy)
                } catch (_: Exception) {
                    // Best-effort; harmless if it remains.
                }
            }
        }
        if (androidKeystore.containsAlias(ALIAS)) return
        val kpg = KeyPairGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_RSA,
            "AndroidKeyStore",
        )
        val spec = KeyGenParameterSpec.Builder(
            ALIAS,
            KeyProperties.PURPOSE_DECRYPT,
        )
            .setDigests(KeyProperties.DIGEST_SHA256)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_RSA_OAEP)
            .setKeySize(2048)
            .build()
        kpg.initialize(spec)
        kpg.generateKeyPair()
    }

    fun publicKeyPem(androidKeystore: KeyStore = loadKeystore()): String {
        ensureKey(androidKeystore)
        val cert = androidKeystore.getCertificate(ALIAS)
        val encoded = cert.publicKey.encoded
        val b64 = Base64.encodeToString(encoded, Base64.NO_WRAP)
        val lines = b64.chunked(64).joinToString("\n")
        return "-----BEGIN PUBLIC KEY-----\n$lines\n-----END PUBLIC KEY-----"
    }

    fun decryptVmk(wrapped: ByteArray, androidKeystore: KeyStore = loadKeystore()): ByteArray {
        val privateKey = androidKeystore.getKey(ALIAS, null)
            ?: throw IllegalStateException("Missing autofill RSA key")
        val cipher = Cipher.getInstance("RSA/ECB/OAEPWithSHA-256AndMGF1Padding")
        cipher.init(Cipher.DECRYPT_MODE, privateKey, OAEP_PARAMS)
        return cipher.doFinal(wrapped)
    }

    private fun loadKeystore(): KeyStore =
        KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
}
