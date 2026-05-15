package com.vaultsnap.app

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PersistableBundle
import android.provider.OpenableColumns
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import com.vaultsnap.app.autofill.save.DeferredSaveQueue
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterFragmentActivity() {
    private val channel = "com.vaultsnap.app/window"
    private val autofillChannelName = "com.vaultsnap.app/autofill"
    private val prefsName = "vaultsnap_preferences"
    private val themeModeKey = "themeMode"

    private var pendingExportResult: MethodChannel.Result? = null
    private var pendingExportBytes: ByteArray? = null
    private var pendingImportResult: MethodChannel.Result? = null

    // Set when AutofillAuthActivity brings us forward to unlock. After a
    // successful autofillStartSession we minimize VaultSnap so the user
    // returns to the calling app with credentials already filled.
    private var autofillAuthRequested = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        autofillAuthRequested =
            intent?.getBooleanExtra(AutofillAuthActivity.EXTRA_AUTOFILL_AUTH, false) == true
        applyWindowBackground(readThemeMode())
    }

    override fun onResume() {
        super.onResume()
        requestHighestRefreshRate()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.getBooleanExtra(AutofillAuthActivity.EXTRA_AUTOFILL_AUTH, false)) {
            autofillAuthRequested = true
        }
    }

    /**
     * Asks the OS for the highest refresh rate the current display
     * supports (90Hz / 120Hz / 144Hz on capable devices). Flutter's
     * engine already calls `Surface.setFrameRate()` since 3.13, but
     * some manufacturers (notably Samsung One UI and OnePlus Oxygen
     * OS) require the explicit `Window.preferredDisplayModeId` hint
     * to honour high refresh rates outside their internal "game
     * mode" allowlist. Belt and suspenders.
     *
     * Filters supported display modes by the *current* resolution so
     * we don't accidentally request a 1080p120 mode on a 1440p
     * display and trigger a resolution downgrade. If no higher mode
     * exists than what the OS already chose, this is a no-op.
     *
     * Available since API 23 (Android 6). Required on API 30+ for
     * apps that need to opt out of the 60Hz default.
     */
    private fun requestHighestRefreshRate() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        try {
            @Suppress("DEPRECATION")
            val display = windowManager.defaultDisplay
            val current = display.mode
            val best = display.supportedModes
                .filter {
                    it.physicalWidth == current.physicalWidth &&
                        it.physicalHeight == current.physicalHeight
                }
                .maxByOrNull { it.refreshRate } ?: return
            if (best.modeId == current.modeId) return
            val params = window.attributes
            params.preferredDisplayModeId = best.modeId
            window.attributes = params
        } catch (_: Exception) {
            // Some display configurations throw on supportedModes.
            // Falling back to whatever Flutter requests is fine.
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, autofillChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "autofillGetPublicKeyPem" -> {
                        try {
                            val pem = AutofillRsa.publicKeyPem()
                            result.success(pem)
                        } catch (e: Exception) {
                            result.error("AUTOFILL_KEY", e.message, null)
                        }
                    }
                    "autofillStartSession" -> {
                        val wrapped = call.argument<ByteArray>("wrappedVmk")
                        val dbPath = call.argument<String>("vaultDbPath")
                        if (wrapped == null || dbPath.isNullOrBlank()) {
                            result.error("INVALID_ARG", "Missing wrappedVmk or vaultDbPath", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val vmk = AutofillRsa.decryptVmk(wrapped)
                            if (vmk.size != 32) {
                                android.util.Log.w(
                                    "VaultSnapAutofill",
                                    "session_start_bad_len len=${vmk.size}",
                                )
                                result.error("VMK_LEN", "Unexpected VMK length", null)
                                return@setMethodCallHandler
                            }
                            AutofillSessionHolder.setSession(vmk, dbPath)
                            AutofillSessionNotifier.notify(this@MainActivity)
                            // Snapshot + clear the autofill-auth flag so a stray
                            // re-entry of this handler doesn't double-minimize.
                            val willMinimize = autofillAuthRequested
                            autofillAuthRequested = false
                            android.util.Log.i(
                                "VaultSnapAutofill",
                                "session_started minimize=$willMinimize",
                            )
                            // Tell Dart whether we'll minimize so it can suppress
                            // the next auto-lock-on-background event.
                            result.success(willMinimize)
                            if (willMinimize) {
                                moveTaskToBack(true)
                            }
                        } catch (e: Exception) {
                            android.util.Log.e(
                                "VaultSnapAutofill",
                                "session_start_failed ${e.message}",
                                e,
                            )
                            result.error("AUTOFILL_SESSION", e.message, null)
                        }
                    }
                    "autofillClearSession" -> {
                        AutofillSessionHolder.clear()
                        result.success(null)
                    }
                    "queryLaunchableApps" -> {
                        // Heavy: enumerates all launcher activities and rasterizes icons.
                        // Run off the main thread so the Flutter bottom sheet opens immediately.
                        Thread {
                            try {
                                val pm = packageManager
                                val launcher = Intent(Intent.ACTION_MAIN).apply {
                                    addCategory(Intent.CATEGORY_LAUNCHER)
                                }
                                @Suppress("DEPRECATION")
                                val resolves = pm.queryIntentActivities(launcher, 0)
                                val density = resources.displayMetrics.density
                                val iconSize =
                                    (40f * density).toInt().coerceIn(24, 72)
                                val out = ArrayList<Map<String, Any>>()
                                for (ri in resolves) {
                                    val pkg = ri.activityInfo.packageName
                                    val label = ri.loadLabel(pm).toString()
                                    val row = mutableMapOf<String, Any>(
                                        "packageName" to pkg,
                                        "label" to label,
                                    )
                                    try {
                                        val png = drawableToPngBytes(
                                            ri.loadIcon(pm),
                                            iconSize,
                                        )
                                        if (png.isNotEmpty()) {
                                            row["iconPng"] = png
                                        }
                                    } catch (_: Exception) {
                                    }
                                    out.add(row)
                                }
                                out.sortBy {
                                    (it["label"] as String).lowercase()
                                }
                                runOnUiThread {
                                    try {
                                        result.success(out)
                                    } catch (_: Exception) {
                                    }
                                }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.error("APPS", e.message, null)
                                }
                            }
                        }.start()
                    }
                    "autofillPendingSaveCount" -> {
                        try {
                            result.success(DeferredSaveQueue.pendingCount(this@MainActivity))
                        } catch (e: Exception) {
                            result.error("SAVE_QUEUE", e.message, null)
                        }
                    }
                    "autofillConsumePendingSaves" -> {
                        try {
                            val payloads = DeferredSaveQueue.consumeAll(this@MainActivity)
                            val out = payloads.map { p ->
                                mapOf(
                                    "username" to (p.username ?: ""),
                                    "password" to p.password,
                                    "callerPackage" to (p.callerPackage ?: ""),
                                    "webHost" to (p.webHost ?: ""),
                                    "createdAtMs" to p.createdAtMs,
                                )
                            }
                            result.success(out)
                        } catch (e: Exception) {
                            result.error("SAVE_QUEUE", e.message, null)
                        }
                    }
                    "openAndroidAutofillSettings" -> {
                        try {
                            val i = Intent(Settings.ACTION_REQUEST_SET_AUTOFILL_SERVICE).apply {
                                data = Uri.parse("package:$packageName")
                            }
                            startActivity(i)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("SETTINGS", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setSecure" -> {
                        val secure = call.argument<Boolean>("secure") ?: false
                        if (secure) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(null)
                    }
                    "copyToClipboardSensitive" -> {
                        // Copies [text] to the system clipboard with the
                        // EXTRA_IS_SENSITIVE flag set on the
                        // ClipDescription. On Android 13+ (API 33) the
                        // system clipboard preview chip will mask the
                        // content as "••••••" so it doesn't appear in
                        // notification toast / quick-paste UI; apps that
                        // explicitly read the clipboard still receive the
                        // real plaintext. On older APIs the extra is
                        // harmlessly ignored.
                        //
                        // This is the same flag Google Authenticator and
                        // 1Password use for copied codes / passwords.
                        val text = call.argument<String>("text") ?: ""
                        val cm = getSystemService(Context.CLIPBOARD_SERVICE)
                            as ClipboardManager
                        val clip = ClipData.newPlainText("VaultSnap", text)
                        // The EXTRA_IS_SENSITIVE constant is API-33+ but
                        // its underlying string key is read from the
                        // bundle on older OSes harmlessly. Using the
                        // string literal keeps us minSdk-compatible
                        // without a Build.VERSION guard.
                        val extras = PersistableBundle()
                        extras.putBoolean(
                            "android.content.extra.IS_SENSITIVE",
                            true,
                        )
                        clip.description.extras = extras
                        cm.setPrimaryClip(clip)
                        result.success(null)
                    }
                    "setThemeMode" -> {
                        val mode = call.argument<String>("mode") ?: "system"
                        getSharedPreferences(prefsName, MODE_PRIVATE)
                            .edit()
                            .putString(themeModeKey, mode)
                            .apply()
                        applyWindowBackground(mode)
                        result.success(null)
                    }
                    "saveBytesToUri" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        val suggestedName =
                            call.argument<String>("name") ?: "vaultsnap_backup.vsb"
                        val mime =
                            call.argument<String>("mime") ?: "application/octet-stream"
                        if (bytes == null) {
                            result.error("INVALID_ARG", "Missing bytes", null)
                            return@setMethodCallHandler
                        }
                        pendingExportResult = result
                        pendingExportBytes = bytes
                        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = mime
                            putExtra(Intent.EXTRA_TITLE, suggestedName)
                        }
                        @Suppress("DEPRECATION")
                        startActivityForResult(intent, REQUEST_EXPORT)
                    }
                    "pickBytesFromUri" -> {
                        val mime = call.argument<String>("mime") ?: "*/*"
                        pendingImportResult = result
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = mime
                        }
                        @Suppress("DEPRECATION")
                        startActivityForResult(intent, REQUEST_IMPORT)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            REQUEST_EXPORT -> handleExportResult(resultCode, data?.data)
            REQUEST_IMPORT -> handleImportResult(resultCode, data?.data)
        }
    }

    private fun handleExportResult(resultCode: Int, uri: Uri?) {
        val pending = pendingExportResult
        val bytes = pendingExportBytes
        pendingExportResult = null
        pendingExportBytes = null
        if (pending == null) return
        if (resultCode != RESULT_OK || uri == null || bytes == null) {
            pending.success(null)
            return
        }
        try {
            contentResolver.openOutputStream(uri).use { stream ->
                if (stream == null) {
                    pending.error("WRITE_FAILED", "Could not open output stream", null)
                    return
                }
                stream.write(bytes)
                stream.flush()
            }
            pending.success(displayName(uri) ?: uri.toString())
        } catch (e: Exception) {
            pending.error("WRITE_FAILED", e.message, null)
        }
    }

    private fun handleImportResult(resultCode: Int, uri: Uri?) {
        val pending = pendingImportResult
        pendingImportResult = null
        if (pending == null) return
        if (resultCode != RESULT_OK || uri == null) {
            pending.success(null)
            return
        }
        try {
            val bytes = contentResolver.openInputStream(uri).use { it?.readBytes() }
            if (bytes == null) {
                pending.success(null)
                return
            }
            pending.success(
                mapOf(
                    "bytes" to bytes,
                    "name" to (displayName(uri) ?: ""),
                ),
            )
        } catch (e: Exception) {
            pending.error("READ_FAILED", e.message, null)
        }
    }

    private fun displayName(uri: Uri): String? {
        return try {
            contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun applyWindowBackground(mode: String) {
        val color = when (resolvedThemeMode(mode)) {
            "light" -> Color.rgb(246, 248, 251)
            else -> Color.rgb(11, 18, 32)
        }
        window.setBackgroundDrawable(ColorDrawable(color))
    }

    private fun readThemeMode(): String {
        return getSharedPreferences(prefsName, MODE_PRIVATE)
            .getString(themeModeKey, "system") ?: "system"
    }

    private fun drawableToPngBytes(drawable: Drawable, sizePx: Int): ByteArray {
        val bmp = Bitmap.createBitmap(
            sizePx,
            sizePx,
            Bitmap.Config.ARGB_8888,
        )
        val canvas = Canvas(bmp)
        drawable.setBounds(0, 0, sizePx, sizePx)
        drawable.draw(canvas)
        val stream = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.PNG, 100, stream)
        return stream.toByteArray()
    }

    private fun resolvedThemeMode(mode: String): String {
        if (mode == "light" || mode == "dark") return mode
        val nightMode = resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
        return if (nightMode == Configuration.UI_MODE_NIGHT_YES) "dark" else "light"
    }

    companion object {
        private const val REQUEST_EXPORT = 4201
        private const val REQUEST_IMPORT = 4202
    }
}
