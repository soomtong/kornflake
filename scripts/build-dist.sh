#!/usr/bin/env bash
set -euo pipefail

# Builds Kornflake.app and packages it as dist/Kornflake-<version>-<arch>.dmg.
# The version comes from the app's Info.plist (set in build-app.sh); the arch is the host's unless --arch is given.
# The release workflow (.github/workflows/release.yml) looks for assets by this name.
# An existing DMG is kept unless --force is given, so a released file is not replaced by mistake.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/Kornflake.app"
DIST="$ROOT/dist"

FORCE=0
ARCH="$(uname -m)"
while [ $# -gt 0 ]; do
    case "$1" in
        -f|--force)
            FORCE=1
            shift
            ;;
        --arch)
            ARCH="${2:-}"
            shift 2 || { echo "--arch needs a value" >&2; exit 1; }
            ;;
        -h|--help)
            echo "Usage: $0 [--force] [--arch arm64|x86_64]"
            echo "  --force  overwrite an existing dist/Kornflake-<version>-<arch>.dmg"
            echo "  --arch   target architecture (default: $(uname -m))"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

"$ROOT/scripts/build-app.sh" --arch "$ARCH"

BUILT_ARCHS="$(lipo -archs "$APP/Contents/MacOS/Kornflake")"
if [ "$BUILT_ARCHS" != "$ARCH" ]; then
    echo "Expected a $ARCH binary but got: $BUILT_ARCHS" >&2
    exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$DIST/Kornflake-$VERSION-$ARCH.dmg"

if [ -e "$DMG" ] && [ "$FORCE" -ne 1 ]; then
    echo "$DMG already exists. Use --force to overwrite it." >&2
    exit 1
fi

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

mkdir -p "$DIST"
hdiutil create \
    -volname "Kornflake $VERSION" \
    -srcfolder "$STAGING" \
    -format UDZO \
    -ov \
    -quiet \
    "$DMG"

echo "Built $DMG"
shasum -a 256 "$DMG"
