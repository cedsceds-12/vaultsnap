package com.vaultsnap.app.autofill.parser

import android.app.assist.AssistStructure
import android.view.View
import android.view.autofill.AutofillId
import com.vaultsnap.app.autofill.matcher.DomainMatcher

/**
 * Walks every [AssistStructure] in a [android.service.autofill.FillRequest]
 * (K-12: walk all FillContexts, not just the latest) and produces a
 * unified [ParsedPage]. K-13: nodes marked
 * [View.IMPORTANT_FOR_AUTOFILL_NO] / `_NO_EXCLUDE_DESCENDANTS` and
 * non-focusable nodes are skipped to avoid honeypots / decoys.
 */
internal object ViewNodeWalker {

    fun parse(structures: List<AssistStructure>): ParsedPage {
        val fields = ArrayList<ClassifiedField>()
        val packages = LinkedHashSet<String>()
        val webHosts = LinkedHashSet<String>()

        for (structure in structures) {
            // Authoritative caller package — present even when view resource
            // IDs belong to a library package rather than the host app.
            structure.activityComponent?.packageName
                ?.takeIf { it.isNotBlank() }
                ?.let { packages.add(it) }

            val n = structure.windowNodeCount
            for (i in 0 until n) {
                val root = structure.getWindowNodeAt(i).rootViewNode ?: continue
                walk(root, fields, packages, webHosts)
            }
        }

        return ParsedPage(
            fields = dedupeByAutofillId(fields),
            packages = packages,
            webHosts = webHosts,
        )
    }

    private fun walk(
        node: AssistStructure.ViewNode,
        fields: MutableList<ClassifiedField>,
        packages: MutableSet<String>,
        webHosts: MutableSet<String>,
    ) {
        node.idPackage?.takeIf { it.isNotBlank() }?.let { packages.add(it) }
        node.webDomain?.takeIf { it.isNotBlank() }?.let {
            webHosts.add(DomainMatcher.normalizeHost(it))
        }

        val importance = node.importantForAutofill
        val excludeDescendants = importance == View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS
        val excludeSelf = excludeDescendants || importance == View.IMPORTANT_FOR_AUTOFILL_NO

        if (!excludeSelf && node.isFocusable) {
            FieldClassifier.classify(node)?.let { fields.add(it) }
        }

        if (excludeDescendants) return

        val cc = node.childCount
        for (i in 0 until cc) {
            walk(node.getChildAt(i), fields, packages, webHosts)
        }
    }

    private fun dedupeByAutofillId(fields: List<ClassifiedField>): List<ClassifiedField> {
        val seen = HashSet<AutofillId>()
        val out = ArrayList<ClassifiedField>()
        for (f in fields) {
            if (seen.add(f.id)) out.add(f)
        }
        return out
    }
}
