package com.vaultsnap.app.autofill.presentation

import android.content.Context
import android.service.autofill.Dataset
import android.service.autofill.FillResponse
import android.view.autofill.AutofillValue
import android.widget.RemoteViews
import com.vaultsnap.app.R
import com.vaultsnap.app.autofill.engine.MatchedEntry
import com.vaultsnap.app.autofill.parser.ParsedPage
import com.vaultsnap.app.autofill.save.SaveResponseBuilder

/**
 * Builds the [FillResponse] users see (RemoteViews popup datasets).
 *
 * Dataset polish — inline suggestions, custom icons, configurable max — is in
 * PR-4. PR-1 just wires the new dispatcher output into the existing popup
 * layout.
 */
internal object DatasetBuilder {

    private const val MAX_DATASETS = 8

    fun buildResponse(
        context: Context,
        parsed: ParsedPage,
        matches: List<MatchedEntry>,
    ): FillResponse? {
        if (matches.isEmpty()) return null
        val response = FillResponse.Builder()
        var added = 0
        for (m in matches) {
            if (added >= MAX_DATASETS) break
            val ds = buildDataset(context, parsed, m) ?: continue
            response.addDataset(ds)
            added++
        }
        if (added == 0) return null
        // Branded header so the drop-down reads as "VaultSnap suggestions"
        // — matches the visual pattern every major password manager uses
        // (1Password, Bitwarden, Apple Passwords) and reassures users they
        // are interacting with VaultSnap rather than a system fallback.
        response.setHeader(buildHeader(context, added))
        // Attach SaveInfo so the framework will call onSaveRequest if the user
        // edits / submits new credentials. Skipped silently if no fields exist.
        SaveResponseBuilder.build(parsed)?.let { response.setSaveInfo(it) }
        return response.build()
    }

    /// Builds a single auto-fill Dataset for the given match. Used by
    /// [AutofillAuthActivity] when exactly one entry matches — returning a
    /// Dataset (rather than a FillResponse) tells Android to apply it
    /// directly without showing the suggestion picker.
    fun buildSingleDataset(
        context: Context,
        parsed: ParsedPage,
        match: MatchedEntry,
    ): Dataset? = buildDataset(context, parsed, match)

    private fun buildHeader(context: Context, count: Int): RemoteViews {
        val view = RemoteViews(context.packageName, R.layout.autofill_header)
        val label = if (count == 1) "1 match" else "$count matches"
        view.setTextViewText(R.id.autofill_header_count, label)
        return view
    }

    private fun buildDataset(
        context: Context,
        parsed: ParsedPage,
        match: MatchedEntry,
    ): Dataset? {
        val userId = parsed.firstUsernameField
        val passId = parsed.firstPasswordField
        if (userId == null && passId == null) return null

        val presentation = RemoteViews(context.packageName, R.layout.autofill_dataset)
        val label = match.label.ifBlank { "(Unnamed)" }
        presentation.setTextViewText(R.id.autofill_label, label)

        // Subtitle = username preview. Falls back to a localized "No
        // username" placeholder so the row keeps its two-line height
        // and the picker layout stays consistent.
        val subtitle = match.username?.takeIf { it.isNotBlank() }
            ?: context.getString(R.string.autofill_no_username)
        presentation.setTextViewText(R.id.autofill_subtitle, subtitle)

        val builder = Dataset.Builder(presentation)
        userId?.let {
            builder.setValue(it, AutofillValue.forText(match.username ?: ""))
        }
        passId?.let {
            builder.setValue(it, AutofillValue.forText(match.password ?: ""))
        }
        return builder.build()
    }
}
