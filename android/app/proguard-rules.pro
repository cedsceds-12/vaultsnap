# VaultSnap — release-build R8 / ProGuard rules.
#
# Strategy: stay conservative. Pure-Dart deps (cryptography, pointycastle,
# encrypt) compile to AOT and are not visible to R8. Flutter plugins
# (sqflite, flutter_secure_storage, local_auth, path_provider, file_picker)
# ship their own consumer-rules.pro inside their AARs and AGP merges those
# automatically. The only things we have to keep ourselves are our own
# Kotlin classes that Android instantiates by name.

# --- Manifest-referenced entry points -------------------------------------
# AGP auto-keeps these via the manifest, but explicit is safer and survives
# package renames / future refactors.
-keep class com.vaultsnap.app.MainActivity { *; }
-keep class com.vaultsnap.app.VaultSnapAutofillService { *; }
-keep class com.vaultsnap.app.AutofillAuthActivity { *; }

# --- Autofill internals ---------------------------------------------------
# Called from VaultSnapAutofillService; some classes override framework
# methods (onSaveRequest, onFillRequest) whose signatures must survive
# obfuscation so the JVM dispatcher resolves them correctly.
-keep class com.vaultsnap.app.autofill.** { *; }

# --- Logging strip --------------------------------------------------------
# Remove verbose / debug / info Log.* calls in release. ERROR and WARN
# survive (and project rules forbid logging sensitive material at any
# level — see CLAUDE.md). This both shrinks the APK and removes any
# accidental verbose-only diagnostic noise from a shipped build.
-assumenosideeffects class android.util.Log {
    public static *** v(...);
    public static *** d(...);
    public static *** i(...);
}

# --- @Keep contract -------------------------------------------------------
# No current usages, but matches AndroidX practice and costs nothing.
# Lets future code opt out of obfuscation via @Keep without touching this
# file.
-keep @androidx.annotation.Keep class * { *; }
-keepclassmembers class * { @androidx.annotation.Keep *; }
