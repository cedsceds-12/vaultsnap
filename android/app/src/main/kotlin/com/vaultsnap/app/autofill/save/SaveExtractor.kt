package com.vaultsnap.app.autofill.save

import android.app.assist.AssistStructure
import com.vaultsnap.app.autofill.parser.ParsedPage
import com.vaultsnap.app.autofill.parser.ViewNodeWalker

/**
 * Walks the SaveRequest structures and pulls out the values the user just
 * typed into the username + password fields.
 */
internal object SaveExtractor {

    fun extract(structures: List<AssistStructure>): SavePayload? {
        if (structures.isEmpty()) return null
        val parsed = ViewNodeWalker.parse(structures)
        val passwordId = parsed.firstPasswordField ?: return null

        val (password, username) = readValues(structures, parsed)
        if (password.isNullOrEmpty()) return null

        return SavePayload(
            username = username?.takeIf { it.isNotBlank() },
            password = password,
            callerPackage = parsed.packages.firstOrNull(),
            webHost = parsed.webHosts.firstOrNull(),
            createdAtMs = System.currentTimeMillis(),
        )
    }

    /**
     * Iterates the structure to grab the textValue/text for the
     * username / password autofill ids. Returns (password, username).
     */
    private fun readValues(
        structures: List<AssistStructure>,
        parsed: ParsedPage,
    ): Pair<String?, String?> {
        val passwordId = parsed.firstPasswordField
        val usernameId = parsed.firstUsernameField
        var password: String? = null
        var username: String? = null

        for (structure in structures) {
            for (i in 0 until structure.windowNodeCount) {
                val root = structure.getWindowNodeAt(i).rootViewNode ?: continue
                walk(root) { node ->
                    val aid = node.autofillId ?: return@walk
                    val value = node.autofillValue
                    val text = if (value != null && value.isText) {
                        value.textValue?.toString()
                    } else {
                        node.text?.toString()
                    }
                    if (text.isNullOrEmpty()) return@walk
                    if (aid == passwordId && password == null) password = text
                    if (aid == usernameId && username == null) username = text
                }
            }
        }
        return password to username
    }

    private fun walk(
        node: AssistStructure.ViewNode,
        visit: (AssistStructure.ViewNode) -> Unit,
    ) {
        visit(node)
        val cc = node.childCount
        for (i in 0 until cc) {
            walk(node.getChildAt(i), visit)
        }
    }
}
