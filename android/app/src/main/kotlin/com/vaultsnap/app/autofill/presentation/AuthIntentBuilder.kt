package com.vaultsnap.app.autofill.presentation

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.service.autofill.Dataset
import android.service.autofill.FillResponse
import android.view.autofill.AutofillValue
import android.widget.RemoteViews
import com.vaultsnap.app.AutofillAuthActivity
import com.vaultsnap.app.R
import com.vaultsnap.app.autofill.parser.ParsedPage
import com.vaultsnap.app.autofill.save.SaveResponseBuilder

/**
 * Builds the "Unlock VaultSnap" [FillResponse] used when a fill request
 * arrives but the vault session is absent. The dataset carries empty values
 * for the detected username/password fields and an [PendingIntent] that
 * launches [AutofillAuthActivity]; once the vault unlocks, the auth activity
 * returns a real response via `EXTRA_AUTHENTICATION_RESULT`.
 *
 * K-18: this is invoked even when no auth fields were detected, so the user
 * always gets an unlock affordance — the empty fields are a no-op fill but
 * the auth activity can still re-evaluate after the user unlocks.
 */
internal object AuthIntentBuilder {

    private const val REQ_UNLOCK = 4401

    fun buildUnlockResponse(context: Context, parsed: ParsedPage): FillResponse {
        // Branded unlock prompt — title + dim subtitle + "UNLOCK" CTA — so
        // the row reads as a real call-to-action instead of just a single
        // label. Matches the polished `autofill_dataset.xml` layout users
        // see for matched entries after unlock.
        val presentation = RemoteViews(context.packageName, R.layout.autofill_unlock)

        val unlockIntent = Intent(context, AutofillAuthActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingFlags = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0)
        val pi = PendingIntent.getActivity(context, REQ_UNLOCK, unlockIntent, pendingFlags)

        val builder = Dataset.Builder(presentation)
        // API 34+ requires a value for any field referenced by the dataset; the
        // auth activity replaces these with the real values after unlock.
        parsed.firstUsernameField?.let { builder.setValue(it, AutofillValue.forText("")) }
        parsed.firstPasswordField?.let { builder.setValue(it, AutofillValue.forText("")) }
        builder.setAuthentication(pi.intentSender)

        // Brand header on the unlock state too — keeps the drop-down
        // visually consistent whether the vault is locked or unlocked.
        val header = RemoteViews(context.packageName, R.layout.autofill_header)
        header.setTextViewText(R.id.autofill_header_count, "Locked")

        val response = FillResponse.Builder()
            .addDataset(builder.build())
            .setHeader(header)
        SaveResponseBuilder.build(parsed)?.let { response.setSaveInfo(it) }
        return response.build()
    }
}
