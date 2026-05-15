package com.vaultsnap.app

import java.util.concurrent.atomic.AtomicReference

/**
 * In-process VMK + DB path for [VaultSnapAutofillService]. Cleared on lock
 * (bytes are zeroed before drop).
 */
object AutofillSessionHolder {
    private val vmkRef = AtomicReference<ByteArray?>(null)
    @Volatile
    var vaultDbPath: String? = null
        private set

    fun setSession(vmk: ByteArray, dbPath: String) {
        clear()
        vmkRef.set(vmk)
        vaultDbPath = dbPath
    }

    fun vmk(): ByteArray? = vmkRef.get()

    fun clear() {
        val v = vmkRef.getAndSet(null)
        v?.fill(0)
        vaultDbPath = null
    }
}
