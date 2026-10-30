#!/usr/bin/env bash
# Notarizes and staples a signed scrib3.app, then re-zips it.
#
# Prerequisites (run once, on your machine):
#   xcrun notarytool store-credentials scrib3-profile \
#     --apple-id "you@example.com" --team-id TEAMID --password "app-specific-pw"
#
# Usage:
#   scripts/notarize.sh dist/scrib3-<ver>-apple-silicon/scrib3.app
set -euo pipefail

APP="${1:?usage: notarize.sh <path/to/scrib3.app>}"
PROFILE="${NOTARY_PROFILE:-scrib3-profile}"
PARENT="$(cd "$(dirname "$APP")" && pwd)"
APP="$PARENT/$(basename "$APP")"
PACKAGE_NAME="$(basename "$PARENT")"
case "$PACKAGE_NAME" in
    scrib3-*-apple-silicon|scrib3-*-intel) ;;
    *) printf 'Use the architecture-named folder created by package.sh.\n' >&2; exit 1 ;;
esac
OUT="$PARENT/$PACKAGE_NAME.zip"

echo "==> Verifying signature before notarization ..."
codesign --verify --deep --strict --verbose=2 "$APP"
spctl -a -vvv -t exec "$APP" || echo "(spctl may fail until notarized — expected)"

TMPZIP="$(mktemp -d)/scrib3.zip"
echo "==> Zipping for notarization ..."
ditto -c -k --keepParent --norsrc "$APP" "$TMPZIP"

echo "==> Submitting to the notary service (this can take a few minutes) ..."
xcrun notarytool submit "$TMPZIP" --keychain-profile "$PROFILE" --wait

echo "==> Stapling ..."
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "==> Gatekeeper assessment after stapling ..."
spctl -a -vvv -t exec "$APP"

echo "==> Re-zipping the stapled app next to it ..."
ditto -c -k --keepParent --norsrc "$APP" "$OUT"
shasum -a 256 "$OUT" | awk '{print $1}' > "$OUT.sha256"
echo "Notarized package: $OUT"
