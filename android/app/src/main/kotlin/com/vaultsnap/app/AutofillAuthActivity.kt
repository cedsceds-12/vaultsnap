package com.vaultsnap.app

import android.app.Activity
import android.app.assist.AssistStructure
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.Parcelable
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.autofill.AutofillManager
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import androidx.annotation.RequiresApi
import androidx.core.content.ContextCompat
import com.vaultsnap.app.autofill.engine.AutofillDispatcher
import com.vaultsnap.app.autofill.parser.ParsedPage
import com.vaultsnap.app.autofill.parser.ViewNodeWalker
import com.vaultsnap.app.autofill.presentation.DatasetBuilder
import java.util.concurrent.atomic.AtomicReference

/**
 * Authentication step for autofill: returns a real [FillResponse] via
 * [AutofillManager.EXTRA_AUTHENTICATION_RESULT] after the vault session exists.
 *
 * Listens for [AutofillSessionNotifier] (broadcast fires right after the Dart
 * unlock pushes the wrapped VMK over MethodChannel) and uses a slow handler
 * poll as a backup. The receiver stays registered until [onDestroy] so the
 * broadcast is still delivered while [MainActivity] is on top.
 *
 * State machine — K-7 fix: replaces the previous `@Volatile completed`
 * flag with an AtomicReference so concurrent broadcast / poll callers
 * cannot race past the same completion path twice.
 */
@RequiresApi(Build.VERSION_CODES.O)
class AutofillAuthActivity : Activity() {

    private enum class AuthState { PENDING, COMPLETED }

    private val handler = Handler(Looper.getMainLooper())
    private var startedAtMs: Long = 0L
    private var parsed: ParsedPage? = null
    private var messageView: TextView? = null

    private val state = AtomicReference(AuthState.PENDING)
    private val isCompleted: Boolean get() = state.get() == AuthState.COMPLETED

    private var pollRunnable: Runnable? = null

    private val sessionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != AutofillSessionNotifier.ACTION_SESSION_READY) return
            Log.i(TAG, "auth_broadcast_received")
            runOnUiThread { tryComplete("broadcast") }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        startedAtMs = System.currentTimeMillis()
        Log.i(TAG, "auth_activity_start")

        val (root, msg) = buildContentView()
        messageView = msg
        setContentView(root)

        val filter = IntentFilter(AutofillSessionNotifier.ACTION_SESSION_READY)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.registerReceiver(
                this,
                sessionReceiver,
                filter,
                ContextCompat.RECEIVER_NOT_EXPORTED,
            )
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(sessionReceiver, filter)
        }

        val structure = intent.getParcelableExtra<AssistStructure>(
            AutofillManager.EXTRA_ASSIST_STRUCTURE,
        )
        if (structure == null) {
            finishCanceled("no_assist_structure")
            return
        }

        val p = ViewNodeWalker.parse(listOf(structure))
        Log.i(
            TAG,
            "auth_parsed pkgs=${p.packages} hosts=${p.webHosts} " +
                "fields=${p.fields.size} hasAuth=${p.hasAuthFields}",
        )
        if (!p.hasAuthFields) {
            finishCanceled("no_field_refs")
            return
        }
        parsed = p

        // Session may already exist (race with very fast unlock).
        tryComplete("initial")

        schedulePoll()

        // Bring VaultSnap forward so the user can unlock; no extra button needed.
        handler.post {
            if (!isCompleted) {
                Log.i(TAG, "auth_open_vault")
                openVaultSnapToUnlock()
            }
        }
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        try {
            unregisterReceiver(sessionReceiver)
        } catch (_: Exception) {
        }
        super.onDestroy()
    }

    private fun schedulePoll() {
        pollRunnable?.let { handler.removeCallbacks(it) }
        pollRunnable = Runnable {
            if (isCompleted) return@Runnable
            tryComplete("poll")
            if (!isCompleted &&
                System.currentTimeMillis() - startedAtMs <= AUTH_TIMEOUT_MS
            ) {
                schedulePoll()
            } else if (!isCompleted) {
                finishCanceled("timeout")
            }
        }
        handler.postDelayed(pollRunnable!!, POLL_MS)
    }

    private fun tryComplete(reason: String) {
        if (isCompleted) return
        val p = parsed ?: return

        val vmk = AutofillSessionHolder.vmk()
        val dbPath = AutofillSessionHolder.vaultDbPath
        if (vmk == null || vmk.size != 32 || dbPath.isNullOrBlank()) {
            messageView?.text = "Unlock VaultSnap on the next screen, then wait…"
            return
        }

        val matches = AutofillDispatcher.match(p, vmk, dbPath)
        if (matches.isEmpty()) {
            Log.i(
                TAG,
                "session_ready reason=$reason but no matching entries; " +
                    "pkgs=${p.packages} hosts=${p.webHosts}",
            )
            finishCanceled("no_matches")
            return
        }

        // UX: when exactly one entry matches, return a Dataset directly so
        // Android applies it without showing the suggestion picker — the
        // user lands back in the calling app with the fields already filled.
        // For 2+ matches we return a FillResponse so the user can pick.
        val authResult: Parcelable? = if (matches.size == 1) {
            DatasetBuilder.buildSingleDataset(this, p, matches[0])
        } else {
            DatasetBuilder.buildResponse(this, p, matches)
        }
        if (authResult == null) {
            finishCanceled("no_dataset")
            return
        }
        Log.i(
            TAG,
            "auth_ok reason=$reason matches=${matches.size} type=${authResult::class.simpleName}",
        )
        finishOk(authResult)
    }

    private fun finishOk(result: Parcelable) {
        if (!state.compareAndSet(AuthState.PENDING, AuthState.COMPLETED)) return
        handler.removeCallbacksAndMessages(null)
        val reply = Intent()
        reply.putExtras(Bundle())
        reply.putExtra(AutofillManager.EXTRA_AUTHENTICATION_RESULT, result)
        setResult(Activity.RESULT_OK, reply)
        finish()
    }

    private fun finishCanceled(reason: String) {
        if (!state.compareAndSet(AuthState.PENDING, AuthState.COMPLETED)) return
        handler.removeCallbacksAndMessages(null)
        Log.i(TAG, "auth_cancel reason=$reason")
        val reply = Intent()
        reply.putExtras(Bundle())
        setResult(Activity.RESULT_CANCELED, reply)
        finish()
    }

    private fun openVaultSnapToUnlock() {
        startActivity(
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
                putExtra(EXTRA_AUTOFILL_AUTH, true)
            },
        )
    }

    private fun buildContentView(): Pair<View, TextView> {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
            setPadding(48, 48, 48, 48)
        }
        val bar = ProgressBar(this)
        val text = TextView(this).apply {
            text = "Opening VaultSnap…"
            textSize = 16f
            gravity = Gravity.CENTER
            setPadding(0, 24, 0, 0)
        }
        root.addView(bar)
        root.addView(text)
        return Pair(root, text)
    }

    companion object {
        const val EXTRA_AUTOFILL_AUTH = "vaultsnap.autofill.AUTH"
        private const val TAG = "VaultSnapAutofill"
        private const val POLL_MS = 400L
        // K-8: 30s gives users enough time to enter a master password / use
        // biometrics without making the auth Activity feel "stuck" if they
        // change their mind. Old value of 120s was painfully long.
        private const val AUTH_TIMEOUT_MS = 30_000L
    }
}
