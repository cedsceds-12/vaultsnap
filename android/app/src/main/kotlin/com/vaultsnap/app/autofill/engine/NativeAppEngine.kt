package com.vaultsnap.app.autofill.engine

import com.vaultsnap.app.autofill.matcher.PackageMatcher
import com.vaultsnap.app.autofill.parser.ParsedPage

/**
 * Matches a saved login against a native Android app caller (anything that
 * isn't a known browser package). A row matches when at least one of the
 * caller packages equals one of the entry's linked package names.
 */
internal object NativeAppEngine : AutofillEngine {

    override fun applies(parsed: ParsedPage): Boolean =
        parsed.packages.any { !PackageMatcher.isBrowser(it) }

    override fun matches(parsed: ParsedPage, candidate: EntryCandidate): Boolean {
        if (candidate.androidPackages.isEmpty()) return false
        for (callerPkg in parsed.packages) {
            if (PackageMatcher.isBrowser(callerPkg)) continue
            for (entryPkg in candidate.androidPackages) {
                if (callerPkg == entryPkg) return true
            }
        }
        return false
    }
}
