#!/usr/bin/env bash
set -euo pipefail

# Builds Kornflake.app and packages it as dist/Kornflake-<version>.dmg.
# The version comes from the app's Info.plist (set in build-app.sh).
# An existing DMG is kept unless --force is given, so a released file is not replaced by mistake.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/Kornflake.app"
DIST="$ROOT/dist"

FORCE=0
for arg in "$@"; do
    case "$arg" in
        -f|--force) FORCE=1 ;;
        -h|--help)
            echo "Usage: $0 [--force]"
            echo "  --force  overwrite an existing dist/Kornflake-<version>.dmg"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg" >&2
            exit 1
            ;;
    esac
done

"$ROOT/scripts/build-app.sh"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$DIST/Kornflake-$VERSION.dmg"

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
