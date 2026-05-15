package com.vaultsnap.app

import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * AES-256-GCM decrypt compatible with Dart `cryptography` `AesGcm.with256bits()`.
 *
 * Two API styles:
 *   * [decrypt] returns the plaintext directly. Callers MUST zero the
 *     returned ByteArray themselves once consumed.
 *   * [decryptAndUse] runs [block] on the plaintext inside a try/finally
 *     that zeros the buffer. Prefer this in new code so transient
 *     plaintexts don't linger on the heap.
 */
object AesGcmVmk {
    private const val TAG_BITS = 128

    /**
     * @param vmk 32-byte vault master key
     * @param nonce 12-byte nonce (Dart default for AesGcm.with256bits)
     * @param ciphertext ciphertext only (no tag)
     * @param mac 16-byte authentication tag
     */
    @JvmStatic
    fun decrypt(
        vmk: ByteArray,
        nonce: ByteArray,
        ciphertext: ByteArray,
        mac: ByteArray,
    ): ByteArray {
        require(vmk.size == 32) { "VMK must be 32 bytes" }
        require(nonce.size == 12) { "Nonce must be 12 bytes for VaultSnap" }
        val combined = ciphertext + mac
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        val spec = GCMParameterSpec(TAG_BITS, nonce)
        val keySpec = SecretKeySpec(vmk, "AES")
        cipher.init(Cipher.DECRYPT_MODE, keySpec, spec)
        return cipher.doFinal(combined)
    }

    /**
     * Decrypt + run [block] + zero the plaintext. Use this for transient
     * decryptions (e.g. autofill match) where the plaintext should not
     * outlive the call.
     */
    inline fun <T> decryptAndUse(
        vmk: ByteArray,
        nonce: ByteArray,
        ciphertext: ByteArray,
        mac: ByteArray,
        block: (ByteArray) -> T,
    ): T {
        val clear = decrypt(vmk, nonce, ciphertext, mac)
        try {
            return block(clear)
        } finally {
            clear.fill(0)
        }
    }
}
