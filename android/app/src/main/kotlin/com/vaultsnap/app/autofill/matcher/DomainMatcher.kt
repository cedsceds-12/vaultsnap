package com.vaultsnap.app.autofill.matcher

import android.net.Uri

/**
 * Host normalization + PSL-aware subdomain matching with tolerant port handling.
 *
 * Mirror of `lib/services/autofill_matching.dart` — keep the two
 * implementations behaviorally identical. Tests on the Dart side cover the
 * matching matrix; this Kotlin side carries the same logic for the runtime
 * autofill service.
 */
internal object DomainMatcher {

    private data class Authority(val host: String, val port: Int?)

    fun normalizeHost(input: String): String {
        var s = input.trim().lowercase()
        if (s.startsWith("www.")) s = s.substring(4)
        return s
    }

    fun hostFromEntryUrl(entryUrl: String?): String? {
        if (entryUrl.isNullOrBlank()) return null
        return parseAuthority(entryUrl)?.host
    }

    /**
     * Tolerant port comparison: when either side omits the port, treat as
     * match-any. Matches the Dart side's `_portsMatch` helper.
     */
    private fun portsMatch(a: Int?, b: Int?): Boolean {
        if (a == null || b == null) return true
        return a == b
    }

    private fun parseAuthority(input: String): Authority? {
        val trimmed = input.trim()
        if (trimmed.isEmpty()) return null
        val uri = Uri.parse(trimmed)
        if (uri.scheme == "http" || uri.scheme == "https") {
            val host = uri.host
            if (!host.isNullOrEmpty()) {
                return Authority(
                    host = normalizeHost(host),
                    port = if (uri.port != -1) uri.port else null,
                )
            }
        }
        if (!trimmed.contains('/') && !trimmed.contains(' ')) {
            val fake = Uri.parse("https://$trimmed")
            val host = fake.host
            if (!host.isNullOrEmpty()) {
                return Authority(
                    host = normalizeHost(host),
                    port = if (fake.port != -1) fake.port else null,
                )
            }
        }
        return null
    }

    /**
     * @return true when [fillHost] (host from `webDomain` or address bar)
     *   matches [entryUrl] (the URL stored on the saved entry). Uses
     *   PSL-aware eTLD+1 so `login.example.co.uk` matches an entry stored
     *   under `example.co.uk`.
     */
    fun fillHostMatchesEntryUrl(fillHost: String?, entryUrl: String?): Boolean {
        if (fillHost.isNullOrBlank()) return false
        val fillAuth = parseAuthority(fillHost) ?: return false
        val entryAuth = entryUrl?.let { parseAuthority(it) } ?: return false
        if (!portsMatch(fillAuth.port, entryAuth.port)) return false

        // Both sides must share a registrable domain (eTLD+1), then the fill
        // host must be the same as or a subdomain of the entry's host — never
        // the other way around. Mirrors the Dart implementation.
        val fillRegistrable = PublicSuffixList.etldPlus1(fillAuth.host)
        val entryRegistrable = PublicSuffixList.etldPlus1(entryAuth.host)
        if (fillRegistrable != entryRegistrable) return false
        return PublicSuffixList.isSameOrSubdomain(fillAuth.host, entryAuth.host)
    }
}
