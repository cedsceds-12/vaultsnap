package com.vaultsnap.app.autofill.engine

import com.vaultsnap.app.autofill.matcher.DomainMatcher
import com.vaultsnap.app.autofill.parser.ParsedPage

/**
 * Matches a saved login against a web domain reported by a browser or
 * WebView (`ViewNode.webDomain`). A row matches when at least one of the
 * fill hosts equals or is a subdomain of the entry's URL host.
 *
 * NOTE: PR-2 will replace the naive `endsWith` check with PSL-aware eTLD+1
 * matching and add a fallback path for browsers that don't report a
 * `webDomain` (K-11). Until then, the original Phase-7 behavior is preserved.
 */
internal object WebDomainEngine : AutofillEngine {

    override fun applies(parsed: ParsedPage): Boolean = parsed.webHosts.isNotEmpty()

    override fun matches(parsed: ParsedPage, candidate: EntryCandidate): Boolean {
        val url = candidate.url ?: return false
        for (host in parsed.webHosts) {
            if (DomainMatcher.fillHostMatchesEntryUrl(host, url)) return true
        }
        return false
    }
}
