#!/usr/bin/env bash
# Verifies a packaged scrib3.app before it is published.
#
# Usage: scripts/verify-release.sh <app> <version> <arm64|x86_64> [--development] [build-number]
set -euo pipefail

APP="${1:?usage: verify-release.sh <app> <version> <arm64|x86_64> [--development] [build-number]}"
VERSION="${2:?version required}"
ARCH="${3:?architecture required}"
MODE="${4:-release}"
BUILD_NUMBER="${5:-1}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

case "$ARCH" in
    arm64) ARCH_NAME=apple-silicon ;;
    x86_64) ARCH_NAME=intel ;;
    *) printf 'Unsupported architecture: %s\n' "$ARCH" >&2; exit 1 ;;
esac
case "$MODE" in
    release|--development) ;;
    *) printf 'Unknown verification mode: %s\n' "$MODE" >&2; exit 1 ;;
esac
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || { printf 'Invalid build number: %s\n' "$BUILD_NUMBER" >&2; exit 1; }

PARENT="$(cd "$(dirname "$APP")" && pwd)"
APP="$PARENT/$(basename "$APP")"
ARCHIVE="$PARENT/scrib3-$VERSION-$ARCH_NAME.zip"
PLIST="$APP/Contents/Info.plist"
BIN="$APP/Contents/MacOS/scrib3"

fail() { printf '%s\n' "$*" >&2; exit 1; }
require_file() { [[ -s "$1" ]] || fail "Missing or empty: $1"; }

[[ -d "$APP" ]] || fail "Missing app bundle: $APP"
[[ "$(basename "$PARENT")" == "scrib3-$VERSION-$ARCH_NAME" ]] || fail "Unexpected folder name: $PARENT"
require_file "$PLIST"
require_file "$BIN"
require_file "$APP/Contents/Resources/scrib3.icns"
require_file "$APP/Contents/Resources/THIRD_PARTY_NOTICES.txt"
require_file "$APP/Contents/Resources/licenses/WhisperKit-LICENSE"

plist_string() { plutil -extract "$2" raw -expect string "$1"; }
[[ "$(plist_string "$PLIST" CFBundleIdentifier)" == "com.scrib3.app" ]] || fail 'Unexpected bundle identifier'
[[ "$(plist_string "$PLIST" CFBundleShortVersionString)" == "$VERSION" ]] || fail 'Version mismatch'
[[ "$(plist_string "$PLIST" CFBundleVersion)" == "$BUILD_NUMBER" ]] || fail 'Build number mismatch'
[[ "$(plist_string "$PLIST" CFBundleExecutable)" == "scrib3" ]] || fail 'Executable name mismatch'
SERVICE_MESSAGE="$(plutil -extract NSServices.0.NSMessage raw -expect string "$PLIST")" \
    || fail 'Finder service message missing'
[[ "$SERVICE_MESSAGE" == "transcribeWithScrib3" ]] || fail 'Finder service message mismatch'

ARCHS="$(lipo -archs "$BIN")"
case "$ARCH" in
    arm64) [[ "$ARCHS" == *arm64* ]] || fail "Binary is not arm64: $ARCHS" ;;
    x86_64) [[ "$ARCHS" == *x86_64* ]] || fail "Binary is not x86_64: $ARCHS" ;;
esac

if otool -l "$BIN" | /usr/bin/awk '
    $1 == "cmd" && $2 == "LC_RPATH" { pending=1; next }
    pending && $1 == "path" { print $2; pending=0 }
' | grep -Eq '(^|/)\.build/|/Applications/.*/Contents/Developer/'; then
    fail 'Build-directory rpath leaked into the executable'
fi

if otool -L "$BIN" | /usr/bin/awk '
    /^[[:space:]]+/ && / \(compatibility version / {
        sub(/^[[:space:]]+/, ""); sub(/ \(compatibility version .*/, ""); print
    }
' | grep -Ev '^(/usr/lib/|/System/Library/|@loader_path/)' | grep -q .; then
    fail 'Executable links a library outside the system paths'
fi

codesign --verify --deep --strict --verbose=2 "$APP" || fail 'Code signature verification failed'

if [[ "$MODE" == "release" ]]; then
    spctl -a -vvv -t exec "$APP" || fail 'Gatekeeper rejected the app (not notarized?)'
    require_file "$ARCHIVE"
    EXPECTED="$(cat "$ARCHIVE.sha256" 2>/dev/null || true)"
    ACTUAL="$(shasum -a 256 "$ARCHIVE" | /usr/bin/awk '{print $1}')"
    [[ -n "$EXPECTED" && "$EXPECTED" == "$ACTUAL" ]] || fail 'Archive checksum mismatch'
fi

printf 'Verified %s (%s, build %s, %s).\n' "$APP" "$VERSION" "$BUILD_NUMBER" "$ARCH"
