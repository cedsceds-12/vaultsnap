package com.vaultsnap.app.autofill.engine

import android.util.Log
import com.vaultsnap.app.AesGcmVmk
import com.vaultsnap.app.autofill.parser.ParsedPage
import org.json.JSONObject
import java.nio.charset.StandardCharsets

/**
 * Orchestrates the engine list: load candidates once, filter by the union of
 * applicable engines, decrypt the survivors, and return [MatchedEntry] for
 * each.
 *
 * Decryption failures are logged at INFO and the row is silently skipped —
 * a corrupted blob shouldn't prevent the rest of the response from rendering.
 */
internal object AutofillDispatcher {

    private const val TAG = "VaultSnapAutofill"

    private val engines: List<AutofillEngine> = listOf(NativeAppEngine, WebDomainEngine)

    /**
     * Skip-on-no-applicable behaviour: if no engine applies to the parsed
     * page, return an empty list (the service will fall through to the
     * unlock-only response or `onSuccess(null)`).
     *
     * PR-2 will introduce a low-confidence browser fallback engine when the
     * caller is a browser but no `webDomain` is reported.
     */
    fun match(parsed: ParsedPage, vmk: ByteArray, dbPath: String): List<MatchedEntry> {
        val applicable = engines.filter { it.applies(parsed) }
        if (applicable.isEmpty()) {
            Log.i(TAG, "no_engine_applies pkgs=${parsed.packages} hosts=${parsed.webHosts}")
            return emptyList()
        }

        val candidates = try {
            EntryRepository.loadAllLogins(dbPath)
        } catch (e: Exception) {
            Log.w(TAG, "entry_load_failed ${e.message}")
            return emptyList()
        }

        val out = ArrayList<MatchedEntry>()
        for (candidate in candidates) {
            val matched = applicable.any { it.matches(parsed, candidate) }
            if (!matched) continue
            decrypt(candidate, vmk)?.let { out.add(it) }
        }
        return out
    }

    private fun decrypt(candidate: EntryCandidate, vmk: ByteArray): MatchedEntry? {
        return try {
            AesGcmVmk.decryptAndUse(
                vmk,
                candidate.nonce,
                candidate.encryptedBlob,
                candidate.mac,
            ) { clear ->
                val json = JSONObject(String(clear, StandardCharsets.UTF_8))
                val password = json.optString("password", "")
                val username = candidate.username?.takeIf { it.isNotBlank() }
                    ?: json.optString("username").takeIf { it.isNotBlank() }
                MatchedEntry(
                    label = candidate.name,
                    username = username,
                    password = password,
                )
            }
        } catch (e: Exception) {
            Log.i(TAG, "decrypt_skip name=${candidate.name} reason=${e.message}")
            null
        }
    }
}
