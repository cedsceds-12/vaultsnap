package com.vaultsnap.app.autofill.matcher

import org.json.JSONArray

/**
 * Caller-package matching helpers + the curated browser package list.
 *
 * NOTE: HMAC-indexed package storage (vs. cleartext JSON column) is deferred
 * to PR-3. PR-1 keeps the existing JSON-array-or-CSV cleartext format.
 */
internal object PackageMatcher {

    fun parseAndroidPackagesColumn(raw: String?): List<String> {
        if (raw.isNullOrBlank()) return emptyList()
        val t = raw.trim()
        if (t.startsWith("[")) {
            try {
                val arr = JSONArray(t)
                val out = LinkedHashSet<String>()
                for (i in 0 until arr.length()) {
                    val s = arr.optString(i).trim()
                    if (s.isNotEmpty()) out.add(s)
                }
                return out.toList()
            } catch (_: Exception) {
                // Fall through to CSV.
            }
        }
        return t.split(',')
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .distinct()
    }

    /**
     * Known browsers — when the caller package matches one of these, prefer
     * web-domain signals from `AssistStructure.ViewNode.webDomain` and skip
     * the native package-equality check.
     */
    val browserPackages: Set<String> = setOf(
        "com.android.chrome",
        "com.chrome.beta",
        "com.chrome.dev",
        "org.chromium.chrome",
        "com.brave.browser",
        "org.mozilla.firefox",
        "org.mozilla.firefox_beta",
        "org.mozilla.fennec_fdroid",
        "com.microsoft.emmx",
        "com.opera.browser",
        "com.opera.mini.native",
        "com.sec.android.app.sbrowser",
        "com.android.browser",
        "com.duckduckgo.mobile.android",
        "com.vivaldi.browser",
        "com.ecosia.android",
    )

    fun isBrowser(packageName: String): Boolean = packageName in browserPackages
}
