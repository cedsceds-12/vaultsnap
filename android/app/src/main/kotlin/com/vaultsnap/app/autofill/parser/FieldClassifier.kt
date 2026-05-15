package com.vaultsnap.app.autofill.parser

import android.app.assist.AssistStructure
import android.text.InputType
import android.view.View
import java.util.Locale

/**
 * Layered field classifier — same priority order Bitwarden / 1Password use:
 *
 *   1. `autofillHints`        (HIGH confidence, framework-blessed)
 *   2. HTML `autocomplete`/`type` (HIGH for explicit attributes; MEDIUM for name/id regex)
 *   3. `inputType` flags      (MEDIUM)
 *   4. `hint` / `contentDescription` / resource id regex   (LOW — accessibility fallback)
 *
 * Any single layer is sufficient to classify a field. Higher-confidence layers
 * stop further evaluation. K-3 (IME options) is intentionally not used as a
 * primary classifier — it's an ambiguous signal on its own.
 */
internal object FieldClassifier {

    fun classify(node: AssistStructure.ViewNode): ClassifiedField? {
        val aid = node.autofillId ?: return null

        classifyByAutofillHints(node)?.let {
            return ClassifiedField(aid, it, Confidence.HIGH)
        }
        classifyByHtmlInfo(node)?.let { (kind, conf) ->
            return ClassifiedField(aid, kind, conf)
        }
        classifyByInputType(node.inputType)?.let {
            return ClassifiedField(aid, it, Confidence.MEDIUM)
        }
        classifyByAccessibility(node)?.let {
            return ClassifiedField(aid, it, Confidence.LOW)
        }
        return null
    }

    private fun classifyByAutofillHints(node: AssistStructure.ViewNode): FieldKind? {
        val hints = node.autofillHints ?: return null
        for (h in hints) {
            when (h) {
                View.AUTOFILL_HINT_PASSWORD -> return FieldKind.PASSWORD_UNKNOWN
                View.AUTOFILL_HINT_USERNAME -> return FieldKind.USERNAME
                View.AUTOFILL_HINT_EMAIL_ADDRESS -> return FieldKind.EMAIL
            }
        }
        return null
    }

    /** Returns kind + confidence (HIGH for explicit autocomplete; MEDIUM for name/id/placeholder regex). */
    private fun classifyByHtmlInfo(node: AssistStructure.ViewNode): Pair<FieldKind, Confidence>? {
        val hi = node.htmlInfo ?: return null
        val attrs = hi.attributes ?: return null
        var typeAttr: String? = null
        var autocomplete: String? = null
        var nameHint: String? = null
        var placeholderHint: String? = null
        for (i in 0 until attrs.size) {
            val p = attrs[i]
            val k = p.first.lowercase(Locale.US)
            val v = p.second.lowercase(Locale.US)
            when (k) {
                "type" -> typeAttr = v
                "autocomplete" -> autocomplete = v
                "name", "id" -> if (nameHint == null) nameHint = v
                "placeholder", "aria-label" -> if (placeholderHint == null) placeholderHint = v
            }
        }

        // K-5: distinguish current-password vs new-password.
        when (autocomplete) {
            "current-password" -> return FieldKind.PASSWORD_CURRENT to Confidence.HIGH
            "new-password" -> return FieldKind.PASSWORD_NEW to Confidence.HIGH
            "username" -> return FieldKind.USERNAME to Confidence.HIGH
            "email" -> return FieldKind.EMAIL to Confidence.HIGH
            "nickname" -> return FieldKind.USERNAME to Confidence.HIGH
        }
        if (typeAttr == "password") return FieldKind.PASSWORD_UNKNOWN to Confidence.HIGH
        if (typeAttr == "email") return FieldKind.EMAIL to Confidence.HIGH

        // Name/id/placeholder regex — medium confidence.
        val combined = listOfNotNull(nameHint, placeholderHint).joinToString(" ")
        if (combined.isNotEmpty()) {
            if (PASSWORD_REGEX.containsMatchIn(combined)) return FieldKind.PASSWORD_UNKNOWN to Confidence.MEDIUM
            if (EMAIL_REGEX.containsMatchIn(combined)) return FieldKind.EMAIL to Confidence.MEDIUM
            if (USERNAME_REGEX.containsMatchIn(combined)) return FieldKind.USERNAME to Confidence.MEDIUM
        }
        return null
    }

    private fun classifyByInputType(inputType: Int): FieldKind? {
        val variation = inputType and InputType.TYPE_MASK_VARIATION
        val cls = inputType and InputType.TYPE_MASK_CLASS

        if (variation == InputType.TYPE_TEXT_VARIATION_PASSWORD ||
            variation == InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD ||
            variation == InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD
        ) {
            return FieldKind.PASSWORD_UNKNOWN
        }
        if (cls == InputType.TYPE_CLASS_NUMBER &&
            variation == InputType.TYPE_NUMBER_VARIATION_PASSWORD
        ) {
            return FieldKind.PASSWORD_UNKNOWN
        }
        if (variation == InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS ||
            variation == InputType.TYPE_TEXT_VARIATION_WEB_EMAIL_ADDRESS
        ) {
            return FieldKind.EMAIL
        }
        return null
    }

    /** K-4: contentDescription / hint / resource id as the lowest-confidence fallback. */
    private fun classifyByAccessibility(node: AssistStructure.ViewNode): FieldKind? {
        val signals = listOfNotNull(
            node.hint?.toString()?.lowercase(Locale.US),
            node.contentDescription?.toString()?.lowercase(Locale.US),
            node.idEntry?.lowercase(Locale.US),
        ).joinToString(" ")
        if (signals.isEmpty()) return null

        if (PASSWORD_REGEX.containsMatchIn(signals)) return FieldKind.PASSWORD_UNKNOWN
        if (EMAIL_REGEX.containsMatchIn(signals)) return FieldKind.EMAIL
        if (USERNAME_REGEX.containsMatchIn(signals)) return FieldKind.USERNAME
        return null
    }

    private val PASSWORD_REGEX = Regex(
        """\b(password|passwd|pwd|secret|passcode)\b""",
        RegexOption.IGNORE_CASE,
    )
    private val EMAIL_REGEX = Regex(
        """\b(email|e-mail|mail)\b""",
        RegexOption.IGNORE_CASE,
    )
    private val USERNAME_REGEX = Regex(
        """\b(user|username|login|account|acct|nickname|userid|user-id|user_id)\b""",
        RegexOption.IGNORE_CASE,
    )
}
