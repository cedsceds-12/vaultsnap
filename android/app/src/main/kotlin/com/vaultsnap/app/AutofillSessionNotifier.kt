package com.vaultsnap.app

import android.content.Context
import android.content.Intent

/**
 * Fires when [AutofillSessionHolder] has been populated after unlock so
 * [AutofillAuthActivity] can return [AutofillManager.EXTRA_AUTHENTICATION_RESULT]
 * without relying only on polling.
 */
internal object AutofillSessionNotifier {
    const val ACTION_SESSION_READY =
        "com.vaultsnap.app.internal.AUTOFILL_SESSION_READY"

    fun notify(context: Context) {
        val i = Intent(ACTION_SESSION_READY).setPackage(context.packageName)
        context.sendBroadcast(i)
    }
}
