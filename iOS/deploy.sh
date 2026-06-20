#!/bin/zsh
# Bygger og installerer Nyhedsoverblik på en tilsluttet iPad.
# Forudsætter: Xcode installeret, Apple ID tilføjet i Xcode, team valgt
# (se README.md for engangsopsætning).
set -e
cd "$(dirname "$0")"

BUNDLE_ID="dk.lvj.nyhedsoverblik"

echo "→ Regenererer Xcode-projekt (samler nye/slettede filer op)…"
xcodegen generate --quiet

echo "→ Bygger til iOS-enhed…"
xcodebuild -project Nyhedsoverblik.xcodeproj \
           -scheme NyhedsoverblikIOS \
           -destination 'generic/platform=iOS' \
           -configuration Debug \
           -allowProvisioningUpdates \
           -allowProvisioningDeviceRegistration \
           build 2>&1 | grep -E "error|warning: |BUILD" | head -20

APP=$(ls -dt ~/Library/Developer/Xcode/DerivedData/Nyhedsoverblik-*/Build/Products/Debug-iphoneos/Nyhedsoverblik.app 2>/dev/null | head -1)
if [[ -z "$APP" ]]; then
  echo "✗ Kunne ikke finde bygget .app — tjek build-output ovenfor"
  exit 1
fi
echo "→ App: $APP"

echo "→ Finder tilsluttet iPad/iPhone…"
DEVICE=$(xcrun devicectl list devices --json-output /tmp/devices.json >/dev/null 2>&1 && \
  python3 -c "
import json
data = json.load(open('/tmp/devices.json'))
for d in data.get('result', {}).get('devices', []):
    props = d.get('deviceProperties', {})
    hw = d.get('hardwareProperties', {})
    state = d.get('connectionProperties', {}).get('tunnelState', '')
    if state != 'unavailable':
        print(d.get('identifier', ''))
        break
")
if [[ -z "$DEVICE" ]]; then
  echo "✗ Ingen enhed fundet. Er iPad'en tilsluttet med kabel og låst op?"
  echo "  Kør: xcrun devicectl list devices"
  exit 1
fi
echo "→ Enhed: $DEVICE"

echo "→ Installerer…"
xcrun devicectl device install app --device "$DEVICE" "$APP"

echo "→ Starter appen…"
xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE_ID" || true

echo "✓ Færdig. (Gratis Apple ID: appen udløber om 7 dage — kør dette script igen for at forny.)"
