#!/usr/bin/env bash
# verify_release_manifest.sh
#
# Asserts the merged release-build AndroidManifest.xml contains exactly one
# <uses-permission> entry — `android.permission.USE_BIOMETRIC` — and nothing
# else (no INTERNET, no ACCESS_NETWORK_STATE, no surprises).
#
# Run from `vault_snap/`:
#   ./scripts/verify_release_manifest.sh
#
# Exits 0 on success, non-zero with a loud error if anything unexpected is
# present. Intended to run before every release; CI can wire this in too.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

echo "[verify] Building release APK to produce merged manifest..."
flutter build apk --release

# AGP writes the merged manifest under one of these paths depending on
# version. Probed in priority order; first match wins.
CANDIDATES=(
  "build/app/intermediates/merged_manifests/release/processReleaseManifest/AndroidManifest.xml"
  "build/app/intermediates/merged_manifests/release/AndroidManifest.xml"
  "build/app/intermediates/merged_manifest/release/AndroidManifest.xml"
  "build/app/intermediates/merged_manifest/release/processReleaseMainManifest/AndroidManifest.xml"
  "build/app/intermediates/packaged_manifests/release/processReleaseManifestForPackage/AndroidManifest.xml"
)

MANIFEST=""
for c in "${CANDIDATES[@]}"; do
  if [ -f "$c" ]; then
    MANIFEST="$c"
    break
  fi
done

if [ -z "$MANIFEST" ]; then
  echo "[verify] FAIL — could not find merged release manifest. Tried:" >&2
  for c in "${CANDIDATES[@]}"; do echo "  $c" >&2; done
  exit 2
fi

echo "[verify] Inspecting $MANIFEST"

# Extract every uses-permission entry.
PERMISSIONS=$(grep -oE '<uses-permission[^>]+android:name="[^"]+"' "$MANIFEST" \
              | sed -E 's/.*android:name="([^"]+)".*/\1/' \
              | sort -u)

# Allowlist:
#   USE_BIOMETRIC                    — we declared it (API 28+ unlock).
#   USE_FINGERPRINT                  — auto-pulled by local_auth for the
#                                      pre-API-28 fingerprint API. Biometric
#                                      only; not a network permission.
#   *.DYNAMIC_RECEIVER_NOT_EXPORTED  — AndroidX-generated internal permission
#                                      scoped to our own package; gates
#                                      LocalBroadcastManager receivers.
#                                      Not a network permission.
#
# What this script is REALLY guarding against: INTERNET, ACCESS_NETWORK_STATE,
# ACCESS_WIFI_STATE, READ_*, WRITE_*, CAMERA, RECORD_AUDIO, etc.
UNEXPECTED=""

is_allowed() {
  case "$1" in
    android.permission.USE_BIOMETRIC) return 0 ;;
    android.permission.USE_FINGERPRINT) return 0 ;;
    *.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION) return 0 ;;
    *) return 1 ;;
  esac
}

echo ""
echo "[verify] Permissions found in release manifest:"
while IFS= read -r p; do
  [ -z "$p" ] && continue
  if is_allowed "$p"; then
    echo "  OK  $p"
  else
    echo "  XX  $p"
    UNEXPECTED="$UNEXPECTED $p"
  fi
done <<< "$PERMISSIONS"

if [ -n "$UNEXPECTED" ]; then
  echo ""
  echo "[verify] FAIL — unexpected permissions in release build:$UNEXPECTED" >&2
  echo "[verify] VaultSnap is local-only. Release builds must NEVER request INTERNET or any other permission beyond USE_BIOMETRIC." >&2
  exit 3
fi

echo ""
echo "[verify] PASS — release manifest is offline-clean."
exit 0
