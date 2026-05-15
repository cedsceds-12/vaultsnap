package com.vaultsnap.app

import android.os.Build
import android.os.CancellationSignal
import android.service.autofill.AutofillService
import android.service.autofill.FillCallback
import android.service.autofill.FillRequest
import android.service.autofill.SaveCallback
import android.service.autofill.SaveRequest
import android.util.Log
import androidx.annotation.RequiresApi
import com.vaultsnap.app.autofill.engine.AutofillDispatcher
import com.vaultsnap.app.autofill.parser.ViewNodeWalker
import com.vaultsnap.app.autofill.presentation.AuthIntentBuilder
import com.vaultsnap.app.autofill.presentation.DatasetBuilder
import com.vaultsnap.app.autofill.save.DeferredSaveQueue
import com.vaultsnap.app.autofill.save.SaveExtractor

/**
 * Slim entry point for the Android Autofill framework.
 *
 *   FillRequest
 *     → ViewNodeWalker.parse  (parser/)
 *     → AutofillDispatcher.match  (engine/)
 *     → DatasetBuilder.buildResponse  (presentation/)
 *
 * The service is intentionally thin — almost all logic lives in
 * `com.vaultsnap.app.autofill.*`. PR-5 will replace the no-op
 * [onSaveRequest] with a real save flow + deferred-save queue.
 */
@RequiresApi(Build.VERSION_CODES.O)
class VaultSnapAutofillService : AutofillService() {

    override fun onFillRequest(
        request: FillRequest,
        cancellationSignal: CancellationSignal,
        callback: FillCallback,
    ) {
        try {
            // K-12: walk every FillContext, not just the latest. Multi-page
            // logins (e.g. Google "username then password") need the union.
            val structures = request.fillContexts.mapNotNull { it.structure }
            Log.i(TAG, "fill_request structures=${structures.size}")
            if (structures.isEmpty()) {
                callback.onSuccess(null)
                return
            }
            val parsed = ViewNodeWalker.parse(structures)
            Log.i(
                TAG,
                "fill_parsed pkgs=${parsed.packages} hosts=${parsed.webHosts} " +
                    "fields=${parsed.fields.size} hasAuth=${parsed.hasAuthFields}",
            )
            if (!parsed.hasAuthFields) {
                // PR-7 (K-18) will replace this with an unlock-only fallback
                // so users always get an "Unlock VaultSnap" affordance.
                callback.onSuccess(null)
                return
            }

            val vmk = AutofillSessionHolder.vmk()
            val dbPath = AutofillSessionHolder.vaultDbPath
            if (vmk == null || vmk.size != 32 || dbPath.isNullOrBlank()) {
                Log.i(TAG, "fill_locked → returning unlock affordance")
                callback.onSuccess(AuthIntentBuilder.buildUnlockResponse(this, parsed))
                return
            }

            val matches = AutofillDispatcher.match(parsed, vmk, dbPath)
            Log.i(TAG, "fill_unlocked matches=${matches.size}")
            callback.onSuccess(DatasetBuilder.buildResponse(this, parsed, matches))
        } catch (e: Exception) {
            Log.e(TAG, "onFillRequest", e)
            callback.onFailure(e.message)
        }
    }

    override fun onSaveRequest(request: SaveRequest, callback: SaveCallback) {
        try {
            val structures = request.fillContexts.mapNotNull { it.structure }
            val payload = SaveExtractor.extract(structures)
            if (payload != null) {
                DeferredSaveQueue.enqueue(this, payload)
            } else {
                Log.i(TAG, "save_skip reason=no_password_extracted")
            }
            callback.onSuccess()
        } catch (e: Exception) {
            Log.e(TAG, "onSaveRequest", e)
            callback.onFailure(e.message)
        }
    }

    companion object {
        private const val TAG = "VaultSnapAutofill"
    }
}
