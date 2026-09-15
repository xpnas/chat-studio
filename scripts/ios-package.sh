#!/usr/bin/env bash
# macOS only. Run on a trusted ephemeral runner; never enable shell tracing.
set -euo pipefail
: "${IOS_CERTIFICATE_BASE64:?Missing IOS_CERTIFICATE_BASE64}"
: "${IOS_CERTIFICATE_PASSWORD:?Missing IOS_CERTIFICATE_PASSWORD}"
: "${IOS_PROFILE_BASE64:?Missing IOS_PROFILE_BASE64}"
: "${IOS_TEAM_ID:?Missing IOS_TEAM_ID}"
: "${RUNNER_TEMP:?Must run on an ephemeral GitHub runner}"
export SIGNING_DIR="$RUNNER_TEMP/chatstudio-ios-signing"
mkdir -p "$SIGNING_DIR"
KEYCHAIN="$SIGNING_DIR/build.keychain-db"
PROFILE_DEST=""
cleanup() {
  security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
  if [[ -n "$PROFILE_DEST" ]]; then rm -f "$PROFILE_DEST"; fi
  rm -f "$SIGNING_DIR/cert.p12" "$SIGNING_DIR/profile.mobileprovision" "$SIGNING_DIR/profile.plist"
}
trap cleanup EXIT
python3 - <<'PY'
import base64, os
from pathlib import Path
root = Path(os.environ['SIGNING_DIR'])
for key, name in [('IOS_CERTIFICATE_BASE64','cert.p12'),('IOS_PROFILE_BASE64','profile.mobileprovision')]:
    path = root/name
    path.write_bytes(base64.b64decode(os.environ[key], validate=True)); path.chmod(0o600)
PY
KEYCHAIN_PASSWORD="$(openssl rand -base64 32)"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$SIGNING_DIR/cert.p12" -P "$IOS_CERTIFICATE_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN"
security set-key-partition-list -S apple-tool:,apple:,codesign: -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
security list-keychains -d user -s "$KEYCHAIN" login.keychain-db
security cms -D -i "$SIGNING_DIR/profile.mobileprovision" > "$SIGNING_DIR/profile.plist"
PROFILE_UUID=$(/usr/libexec/PlistBuddy -c 'Print UUID' "$SIGNING_DIR/profile.plist")
mkdir -p "$HOME/Library/MobileDevice/Provisioning Profiles"
PROFILE_DEST="$HOME/Library/MobileDevice/Provisioning Profiles/$PROFILE_UUID.mobileprovision"
cp "$SIGNING_DIR/profile.mobileprovision" "$PROFILE_DEST"
flutter build ios --release --no-codesign --build-number="${BUILD_NUMBER:-1}"
python3 - <<'PY'
import datetime, os, plistlib, re
from pathlib import Path
profile = plistlib.loads((Path(os.environ['SIGNING_DIR'])/'profile.plist').read_bytes())
team = os.environ['IOS_TEAM_ID']
project = Path('ios/Runner.xcodeproj/project.pbxproj')
source = project.read_text()
bundle = re.search(r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);', source).group(1).strip('"')
if profile['TeamIdentifier'][0] != team:
    raise SystemExit('Provisioning profile team mismatch')
if profile['Entitlements']['application-identifier'] != f'{team}.{bundle}':
    raise SystemExit('Use a provisioning profile for the exact Runner bundle identifier')
if profile['ExpirationDate'] < datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None):
    raise SystemExit('Provisioning profile expired')
# Only Runner configs have this entitlement. Do not set a profile on dependencies.
marker = 'CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;'
assert source.count(marker) == 3, 'Unexpected Xcode project layout'
source = source.replace(marker, marker + f'\n\t\t\t\tCODE_SIGN_STYLE = Manual;\n\t\t\t\tDEVELOPMENT_TEAM = "{team}";\n\t\t\t\tCODE_SIGN_IDENTITY = "Apple Distribution";\n\t\t\t\tPROVISIONING_PROFILE_SPECIFIER = "{profile["UUID"]}";')
project.write_text(source)
options = {'method':os.environ.get('IOS_EXPORT_METHOD','app-store-connect'), 'teamID':team,
    'signingStyle':'manual', 'signingCertificate':'Apple Distribution',
    'provisioningProfiles':{bundle:profile['UUID']}, 'manageAppVersionAndBuildNumber':False}
Path('build/ios/ExportOptions.plist').write_bytes(plistlib.dumps(options))
PY
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/ios/archive/Runner.xcarchive archive
xcodebuild -exportArchive -archivePath build/ios/archive/Runner.xcarchive \
  -exportPath build/ios/ipa -exportOptionsPlist build/ios/ExportOptions.plist
