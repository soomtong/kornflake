#!/usr/bin/env bash
set -euo pipefail

# Builds Kornflake.app for one architecture (the host's by default).
# Apple Silicon can cross-build the Intel app with --arch x86_64, and the reverse also works.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/Kornflake.app"

ARCH="$(uname -m)"
while [ $# -gt 0 ]; do
    case "$1" in
        --arch)
            ARCH="${2:-}"
            shift 2 || { echo "--arch needs a value" >&2; exit 1; }
            ;;
        -h|--help)
            echo "Usage: $0 [--arch arm64|x86_64]"
            echo "  --arch  target architecture (default: $(uname -m))"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

case "$ARCH" in
    arm64|x86_64) ;;
    *)
        echo "Unsupported architecture: $ARCH (use arm64 or x86_64)" >&2
        exit 1
        ;;
esac

cd "$ROOT"

if [ ! -f "$ROOT/assets/AppIcon.icns" ]; then
    "$ROOT/scripts/make-icon.sh"
fi

swift build -c release --arch "$ARCH"
BIN="$(swift build -c release --arch "$ARCH" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN/Kornflake" "$APP/Contents/MacOS/Kornflake"
cp "$ROOT/assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp -R "$BIN/Kornflake_Kornflake.bundle" "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Kornflake</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.kornflake.preview</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Kornflake</string>
    <key>CFBundleDisplayName</key>
    <string>Kornflake</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.3.1</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>LSUIElement</key>
    <false/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "Built $APP ($ARCH)"
