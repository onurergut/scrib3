#!/usr/bin/env bash
# Packages an already-built scrib3.app into a compressed .dmg for
# drag-to-install distribution. Run scripts/package.sh first.
#
# Usage: scripts/make-dmg.sh [arm64|x86_64] [version]
set -euo pipefail

ARCH="${1:-$(uname -m)}"
VERSION="${2:-0.1.0}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP_NAME="scrib3"

ARCH_LABEL="$([ "$ARCH" = "arm64" ] && echo apple-silicon || echo intel)"
OUTROOT="$DIST/scrib3-$VERSION-$ARCH_LABEL"
CONTENTS="$OUTROOT/$APP_NAME.app"
DMG="$OUTROOT/scrib3-$VERSION-$ARCH.dmg"

if [ ! -d "$CONTENTS" ]; then
    echo "error: no app bundle at:" >&2
    echo "         $CONTENTS" >&2
    echo "       Build and sign it first: scripts/package.sh $ARCH $VERSION" >&2
    exit 1
fi

echo "==> Staging $CONTENTS..."
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/scrib3-dmg.XXXXXX")"
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

ditto "$CONTENTS" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"

echo "==> Building compressed DMG..."
rm -f "$DMG"
hdiutil create \
    -volname "$APP_NAME $VERSION" \
    -srcfolder "$STAGE" \
    -ov \
    -format UDZO \
    "$DMG" > /dev/null

shasum -a 256 "$DMG" | awk '{print $1}' > "$DMG.sha256"
echo "Created: $DMG"
