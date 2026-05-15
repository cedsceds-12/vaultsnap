package com.vaultsnap.app.autofill.save

import android.content.Context
import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Stores pending save-requests so the Dart side can prompt the user after the
 * next unlock. The on-disk form is AES-GCM-256 ciphertext under a per-app
 * symmetric key in the Android Keystore — VaultSnap's product invariant
 * forbids cleartext credentials on disk.
 *
 * The Dart side consumes the queue via [com.vaultsnap.app.MainActivity]'s
 * `autofillConsumePendingSaves` MethodChannel route.
 */
internal object DeferredSaveQueue {
    private const val TAG = "VaultSnapAutofill"
    private const val PREFS = "vaultsnap_save_queue"
    private const val KEY_PAYLOADS = "payloads"
    private const val KEYSTORE_ALIAS = "vaultsnap_save_queue_aes"
    private const val GCM_TAG_BITS = 128
    private const val MAX_QUEUE_SIZE = 50

    fun enqueue(context: Context, payload: SavePayload) {
        try {
            val key = ensureKey()
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, key)
            val iv = cipher.iv
            val plaintext = payload.toJson().toString().toByteArray(Charsets.UTF_8)
            val ciphertext = cipher.doFinal(plaintext)

            val record = JSONObject().apply {
                put("iv", Base64.encodeToString(iv, Base64.NO_WRAP))
                put("ct", Base64.encodeToString(ciphertext, Base64.NO_WRAP))
            }

            val prefs = prefs(context)
            val list = currentList(prefs)
            list.put(record)
            // Cap queue size so it can't grow unbounded.
            while (list.length() > MAX_QUEUE_SIZE) list.remove(0)
            prefs.edit().putString(KEY_PAYLOADS, list.toString()).apply()
            Log.i(TAG, "save_enqueued pkg=${payload.callerPackage} host=${payload.webHost}")
        } catch (e: Exception) {
            Log.w(TAG, "save_enqueue_failed ${e.message}")
        }
    }

    fun consumeAll(context: Context): List<SavePayload> {
        return try {
            val prefs = prefs(context)
            val raw = prefs.getString(KEY_PAYLOADS, null) ?: return emptyList()
            val list = JSONArray(raw)
            val out = ArrayList<SavePayload>()
            val key = ensureKey()
            for (i in 0 until list.length()) {
                val rec = list.optJSONObject(i) ?: continue
                val ivStr = rec.optString("iv")
                val ctStr = rec.optString("ct")
                if (ivStr.isEmpty() || ctStr.isEmpty()) continue
                try {
                    val iv = Base64.decode(ivStr, Base64.NO_WRAP)
                    val ct = Base64.decode(ctStr, Base64.NO_WRAP)
                    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                    cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(GCM_TAG_BITS, iv))
                    val plain = cipher.doFinal(ct)
                    val payload = savePayloadFromJson(JSONObject(String(plain, Charsets.UTF_8)))
                    if (payload != null) out.add(payload)
                } catch (_: Exception) {
                    // Skip corrupted record; continue with the rest.
                }
            }
            prefs.edit().remove(KEY_PAYLOADS).apply()
            out
        } catch (e: Exception) {
            Log.w(TAG, "save_consume_failed ${e.message}")
            emptyList()
        }
    }

    fun pendingCount(context: Context): Int {
        val prefs = prefs(context)
        val raw = prefs.getString(KEY_PAYLOADS, null) ?: return 0
        return try { JSONArray(raw).length() } catch (_: Exception) { 0 }
    }

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun currentList(prefs: SharedPreferences): JSONArray {
        val raw = prefs.getString(KEY_PAYLOADS, null) ?: return JSONArray()
        return try { JSONArray(raw) } catch (_: Exception) { JSONArray() }
    }

    private fun ensureKey(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing = ks.getKey(KEYSTORE_ALIAS, null) as? SecretKey
        if (existing != null) return existing
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        val spec = KeyGenParameterSpec.Builder(
            KEYSTORE_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .build()
        gen.init(spec)
        return gen.generateKey()
    }

    private fun SavePayload.toJson(): JSONObject = JSONObject().apply {
        put("username", username ?: "")
        put("password", password)
        put("callerPackage", callerPackage ?: "")
        put("webHost", webHost ?: "")
        put("createdAtMs", createdAtMs)
    }

    private fun savePayloadFromJson(json: JSONObject): SavePayload? {
        val password = json.optString("password")
        if (password.isEmpty()) return null
        return SavePayload(
            username = json.optString("username").takeIf { it.isNotEmpty() },
            password = password,
            callerPackage = json.optString("callerPackage").takeIf { it.isNotEmpty() },
            webHost = json.optString("webHost").takeIf { it.isNotEmpty() },
            createdAtMs = json.optLong("createdAtMs", System.currentTimeMillis()),
        )
    }
}
