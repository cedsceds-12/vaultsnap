package com.vaultsnap.app.autofill.engine

import com.vaultsnap.app.autofill.parser.ParsedPage

/**
 * One row from the on-device login table — cleartext metadata for the matcher
 * + encrypted payload for later decrypt-on-match.
 *
 * PR-3 will replace [androidPackages] with an HMAC-indexed shadow table; until
 * then the existing cleartext JSON column is loaded as-is.
 */
internal data class EntryCandidate(
    val name: String,
    val username: String?,
    val url: String?,
    val androidPackages: List<String>,
    val encryptedBlob: ByteArray,
    val nonce: ByteArray,
    val mac: ByteArray,
) {
    override fun equals(other: Any?): Boolean = this === other
    override fun hashCode(): Int = System.identityHashCode(this)
}

/**
 * The result of decrypting a candidate that survived engine filtering. This
 * is the only type that carries plaintext password material; instances must
 * not be logged or persisted, and references should be dropped as soon as
 * the [android.service.autofill.FillResponse] has been built.
 */
internal data class MatchedEntry(
    val label: String,
    val username: String?,
    val password: String?,
)

/**
 * Strategy interface for "does this row match this fill request?" — one
 * implementation per matching context (native package, web domain, …).
 *
 * Engines are pure predicates: they don't touch the DB, the VMK, or
 * Android system services. The dispatcher loads candidates once and
 * intersects them with the union of applicable engines' predicates.
 */
internal interface AutofillEngine {
    /** True if this engine can produce matches for the given page. */
    fun applies(parsed: ParsedPage): Boolean

    /** True if [candidate] should be offered as a fill suggestion for [parsed]. */
    fun matches(parsed: ParsedPage, candidate: EntryCandidate): Boolean
}
