package com.vaultsnap.app.autofill.parser

import android.view.autofill.AutofillId

internal enum class FieldKind {
    USERNAME,
    EMAIL,
    PASSWORD_CURRENT,
    PASSWORD_NEW,
    PASSWORD_UNKNOWN,
}

internal enum class Confidence { HIGH, MEDIUM, LOW }

internal data class ClassifiedField(
    val id: AutofillId,
    val kind: FieldKind,
    val confidence: Confidence,
)

/**
 * Result of walking an [android.app.assist.AssistStructure] (or the union of all
 * [android.service.autofill.FillContext]s in a request). Holds the classified
 * fields, the caller package(s), and any web hosts surfaced by the WebView's
 * `webDomain` attribute.
 */
internal data class ParsedPage(
    val fields: List<ClassifiedField>,
    val packages: Set<String>,
    val webHosts: Set<String>,
) {
    val hasAuthFields: Boolean
        get() = fields.any { it.kind in AUTH_KINDS }

    val firstUsernameField: AutofillId?
        get() = fields.firstOrNull { it.kind == FieldKind.USERNAME || it.kind == FieldKind.EMAIL }?.id

    val firstPasswordField: AutofillId?
        get() = fields.firstOrNull { it.kind in PASSWORD_KINDS }?.id

    /**
     * True if any password field is explicitly marked as `new-password` (sign-up
     * or change-password page). Existing-credential autofill should be skipped
     * for these; they are candidates for save flow + password generator instead.
     */
    val isNewPasswordPage: Boolean
        get() = fields.any { it.kind == FieldKind.PASSWORD_NEW }

    companion object {
        private val AUTH_KINDS = setOf(
            FieldKind.USERNAME,
            FieldKind.EMAIL,
            FieldKind.PASSWORD_CURRENT,
            FieldKind.PASSWORD_NEW,
            FieldKind.PASSWORD_UNKNOWN,
        )
        private val PASSWORD_KINDS = setOf(
            FieldKind.PASSWORD_CURRENT,
            FieldKind.PASSWORD_NEW,
            FieldKind.PASSWORD_UNKNOWN,
        )
    }
}
