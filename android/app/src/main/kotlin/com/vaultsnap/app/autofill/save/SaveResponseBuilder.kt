package com.vaultsnap.app.autofill.save

import android.os.Build
import android.service.autofill.SaveInfo
import android.view.autofill.AutofillId
import androidx.annotation.RequiresApi
import com.vaultsnap.app.autofill.parser.ParsedPage

/**
 * Builds the [SaveInfo] attached to a [android.service.autofill.FillResponse].
 * Without this the framework will never call `onSaveRequest`.
 */
internal object SaveResponseBuilder {

    @RequiresApi(Build.VERSION_CODES.O)
    fun build(parsed: ParsedPage): SaveInfo? {
        val ids = mutableListOf<AutofillId>()
        parsed.firstUsernameField?.let { ids.add(it) }
        parsed.firstPasswordField?.let { ids.add(it) }
        if (ids.isEmpty()) return null

        val type = when {
            parsed.firstUsernameField != null && parsed.firstPasswordField != null ->
                SaveInfo.SAVE_DATA_TYPE_USERNAME or SaveInfo.SAVE_DATA_TYPE_PASSWORD
            parsed.firstPasswordField != null -> SaveInfo.SAVE_DATA_TYPE_PASSWORD
            else -> SaveInfo.SAVE_DATA_TYPE_USERNAME
        }

        val builder = SaveInfo.Builder(type, ids.toTypedArray())
        // SPA / multi-step signups: don't call onSaveRequest until every
        // referenced view is invisible, which is the common Bitwarden /
        // 1Password setting.
        builder.setFlags(SaveInfo.FLAG_SAVE_ON_ALL_VIEWS_INVISIBLE)
        return builder.build()
    }
}
