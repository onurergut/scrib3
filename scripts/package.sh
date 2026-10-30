#!/usr/bin/env bash
# Builds one architecture and produces a ZIP with a SHA-256 checksum.
# Set CODESIGN_IDENTITY to a Developer ID Application identity for
# distribution; otherwise signing is ad-hoc.
#
# Usage: scripts/package.sh [arm64|x86_64] [version] [build-number]
set -euo pipefail

ARCH="${1:-$(uname -m)}"
VERSION="${2:-0.1.0}"
BUILD_NUMBER="${3:-1}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP_NAME="scrib3"
BUNDLE="$DIST/$APP_NAME.app"

case "$ARCH" in
    arm64) ARCH_NAME=apple-silicon ;;
    x86_64) ARCH_NAME=intel ;;
    *) printf 'Unsupported architecture: %s\n' "$ARCH" >&2; exit 1 ;;
esac
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { printf 'Invalid version: %s\n' "$VERSION" >&2; exit 1; }
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || { printf 'Invalid build number: %s\n' "$BUILD_NUMBER" >&2; exit 1; }

OUTROOT="$DIST/scrib3-$VERSION-$ARCH_NAME"
ARCHIVE="$OUTROOT/scrib3-$VERSION-$ARCH_NAME.zip"

printf '==> Building %s for %s (release)...\n' "$APP_NAME" "$ARCH"
cd "$ROOT"
swift build --manifest-cache none -c release --arch "$ARCH"
BIN="$(swift build --manifest-cache none -c release --arch "$ARCH" --show-bin-path)/$APP_NAME"
[[ -x "$BIN" ]] || { printf 'Build did not produce %s\n' "$BIN" >&2; exit 1; }

printf '==> Assembling %s...\n' "$BUNDLE"
rm -rf "$BUNDLE" "$OUTROOT"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources/licenses"
EXE="$BUNDLE/Contents/MacOS/$APP_NAME"
PLIST="$BUNDLE/Contents/Info.plist"
cp "$BIN" "$EXE"
cp "$ROOT/Resources/Info.plist" "$PLIST"
cp "$ROOT/Resources/scrib3.icns" "$BUNDLE/Contents/Resources/scrib3.icns"
cp "$ROOT/THIRD_PARTY_NOTICES.txt" "$BUNDLE/Contents/Resources/"

set_plist() {
    /usr/libexec/PlistBuddy -c "Delete :$1" "$PLIST" > /dev/null 2>&1 || true
    /usr/libexec/PlistBuddy -c "Add :$1 $2 $3" "$PLIST"
}
set_plist CFBundleShortVersionString string "$VERSION"
set_plist CFBundleVersion string "$BUILD_NUMBER"

printf 'APPL????' > "$BUNDLE/Contents/PkgInfo"

copy_license() {
    [[ -s "$1" ]] || { printf 'Required license missing or empty: %s\n' "$1" >&2; exit 1; }
    cp "$1" "$BUNDLE/Contents/Resources/licenses/$2"
}
copy_license "$ROOT/.build/checkouts/WhisperKit/LICENSE" WhisperKit-LICENSE
copy_license "$ROOT/.build/checkouts/swift-argument-parser/LICENSE.txt" swift-argument-parser-LICENSE

# SwiftPM adds build-directory rpaths. Remove them from the packaged copy.
LOAD_COMMANDS="$(otool -l "$EXE")"
RPATHS="$(printf '%s\n' "$LOAD_COMMANDS" | /usr/bin/awk '
    $1 == "cmd" && $2 == "LC_RPATH" { pending=1; next }
    pending && $1 == "path" { sub(/^[[:space:]]*path /, ""); sub(/ \(offset [0-9]+\)$/, ""); print; pending=0 }
' | sort -u)"
while IFS= read -r rpath; do
    case "$rpath" in
        "$ROOT/.build"|"$ROOT/.build/"*|*/.build/*|/Applications/*/Contents/Developer/*|/Library/Developer/*)
            install_name_tool -delete_rpath "$rpath" "$EXE" ;;
    esac
done <<< "$RPATHS"

printf '==> Signing...\n'
SIGN_ARGS=(--force --sign "${CODESIGN_IDENTITY:--}")
if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    SIGN_ARGS+=(--options runtime --timestamp)
    SIGN_STATE="signed with '$CODESIGN_IDENTITY' (Hardened Runtime). Run scripts/notarize.sh before distributing."
else
    SIGN_STATE='ad-hoc signed (NOT for distribution; set CODESIGN_IDENTITY to sign properly).'
fi
codesign "${SIGN_ARGS[@]}" --entitlements "$ROOT/Resources/scrib3.entitlements" "$BUNDLE"
codesign --verify --deep --strict --verbose=2 "$BUNDLE"

printf '==> Moving to arch-named folder...\n'
mkdir -p "$OUTROOT"
mv "$BUNDLE" "$OUTROOT/"
CONTENTS="$OUTROOT/$APP_NAME.app"

printf '==> Zipping...\n'
ditto -c -k --keepParent --norsrc "$CONTENTS" "$ARCHIVE"
DIGEST="$(shasum -a 256 "$ARCHIVE")"
printf '%s\n' "${DIGEST%% *}" > "$ARCHIVE.sha256"

bash "$ROOT/scripts/verify-release.sh" "$CONTENTS" "$VERSION" "$ARCH" --development "$BUILD_NUMBER"

APP_SIZE="$(du -sh "$CONTENTS" | /usr/bin/awk '{print $1}')"
ZIP_SIZE="$(du -sh "$ARCHIVE" | /usr/bin/awk '{print $1}')"
BIN_SIZE="$(du -sh "$CONTENTS/Contents/MacOS/$APP_NAME" | /usr/bin/awk '{print $1}')"
printf '\n==================== scrib3 %s (%s), build %s ====================\n' "$VERSION" "$ARCH" "$BUILD_NUMBER"
printf 'Bundle:        %s\nZip:           %s  (%s)\nApp size:      %s\nExecutable:    %s\nSigning:       %s\nChecksum:      %s.sha256\n' \
    "$CONTENTS" "$ARCHIVE" "$ZIP_SIZE" "$APP_SIZE" "$BIN_SIZE" "$SIGN_STATE" "$ARCHIVE"
