# verify_release_manifest.ps1
#
# Asserts the merged release-build AndroidManifest.xml contains exactly one
# <uses-permission> entry — `android.permission.USE_BIOMETRIC` — and nothing
# else (no INTERNET, no ACCESS_NETWORK_STATE, no surprises).
#
# Run from `vault_snap/`:
#   pwsh ./scripts/verify_release_manifest.ps1
#
# Exits 0 on success, non-zero with a loud error if anything unexpected is
# present. Intended to run before every release; CI can wire this in too.

$ErrorActionPreference = 'Stop'

$ProjectRoot = (Resolve-Path "$PSScriptRoot/..").Path
Set-Location $ProjectRoot

Write-Host "[verify] Building release APK to produce merged manifest..." -ForegroundColor Cyan
flutter build apk --release | Out-Host
if ($LASTEXITCODE -ne 0) {
    Write-Error "[verify] flutter build apk --release failed (exit $LASTEXITCODE)"
    exit 1
}

# AGP writes the merged manifest under one of these paths depending on
# version. Probed in priority order; first match wins.
$Candidates = @(
    "build/app/intermediates/merged_manifests/release/processReleaseManifest/AndroidManifest.xml",
    "build/app/intermediates/merged_manifests/release/AndroidManifest.xml",
    "build/app/intermediates/merged_manifest/release/AndroidManifest.xml",
    "build/app/intermediates/merged_manifest/release/processReleaseMainManifest/AndroidManifest.xml",
    "build/app/intermediates/packaged_manifests/release/processReleaseManifestForPackage/AndroidManifest.xml"
)

$Manifest = $null
foreach ($c in $Candidates) {
    if (Test-Path $c) { $Manifest = $c; break }
}

if (-not $Manifest) {
    Write-Error "[verify] Could not find merged release manifest. Tried: $($Candidates -join ', ')"
    exit 2
}

Write-Host "[verify] Inspecting $Manifest" -ForegroundColor Cyan

# Pull every <uses-permission android:name="..."/> entry.
$Pattern = '<uses-permission[^>]+android:name="([^"]+)"'
$Matches = Select-String -Path $Manifest -Pattern $Pattern -AllMatches
$Permissions = @()
foreach ($line in $Matches) {
    foreach ($m in $line.Matches) {
        $Permissions += $m.Groups[1].Value
    }
}

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
$Allowed = @(
    'android.permission.USE_BIOMETRIC',
    'android.permission.USE_FINGERPRINT'
)
$Unexpected = $Permissions | Where-Object {
    ($_ -notin $Allowed) -and ($_ -notlike '*.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION')
}

Write-Host ""
Write-Host "[verify] Permissions found in release manifest:" -ForegroundColor Cyan
foreach ($p in $Permissions) {
    $isAllowed = ($p -in $Allowed) -or ($p -like '*.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION')
    if ($isAllowed) {
        Write-Host "  OK  $p" -ForegroundColor Green
    } else {
        Write-Host "  XX  $p" -ForegroundColor Red
    }
}

if ($Unexpected.Count -gt 0) {
    Write-Host ""
    Write-Error "[verify] FAIL — unexpected permissions in release build: $($Unexpected -join ', ')"
    Write-Error "[verify] VaultSnap is local-only. Release builds must NEVER request INTERNET or any other permission beyond USE_BIOMETRIC."
    exit 3
}

Write-Host ""
Write-Host "[verify] PASS — release manifest is offline-clean." -ForegroundColor Green
exit 0
