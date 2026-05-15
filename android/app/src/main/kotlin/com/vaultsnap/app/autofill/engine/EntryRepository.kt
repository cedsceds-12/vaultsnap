package com.vaultsnap.app.autofill.engine

import android.database.sqlite.SQLiteDatabase
import com.vaultsnap.app.autofill.matcher.PackageMatcher

/**
 * Reads candidate login rows from the on-device SQLite vault. Returns
 * cleartext-metadata-only rows; decryption of the payload is the dispatcher's
 * job (it requires VMK).
 *
 * PR-3 will fold HMAC-indexed package matching into this query.
 */
internal object EntryRepository {

    fun loadAllLogins(dbPath: String): List<EntryCandidate> {
        val db = SQLiteDatabase.openDatabase(dbPath, null, SQLiteDatabase.OPEN_READONLY)
        return db.use { conn ->
            val out = ArrayList<EntryCandidate>()
            conn.rawQuery(
                """
                SELECT name, username, url, android_packages, encrypted_blob, nonce, mac
                FROM entries
                WHERE category = 'login'
                ORDER BY updated_at DESC
                """.trimIndent(),
                null,
            ).use { cursor ->
                val ixName = cursor.getColumnIndexOrThrow("name")
                val ixUser = cursor.getColumnIndexOrThrow("username")
                val ixUrl = cursor.getColumnIndexOrThrow("url")
                val ixPkg = cursor.getColumnIndexOrThrow("android_packages")
                val ixBlob = cursor.getColumnIndexOrThrow("encrypted_blob")
                val ixNonce = cursor.getColumnIndexOrThrow("nonce")
                val ixMac = cursor.getColumnIndexOrThrow("mac")
                while (cursor.moveToNext()) {
                    val blob = cursor.getBlob(ixBlob)
                    val nonce = cursor.getBlob(ixNonce)
                    val mac = cursor.getBlob(ixMac)
                    if (blob == null || nonce == null || mac == null) continue
                    out.add(
                        EntryCandidate(
                            name = cursor.getString(ixName) ?: "(Unnamed)",
                            username = cursor.getString(ixUser),
                            url = cursor.getString(ixUrl),
                            androidPackages = PackageMatcher
                                .parseAndroidPackagesColumn(cursor.getString(ixPkg)),
                            encryptedBlob = blob,
                            nonce = nonce,
                            mac = mac,
                        ),
                    )
                }
            }
            out
        }
    }
}
