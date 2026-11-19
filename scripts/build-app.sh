#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
APP_NAME="StealthReader"
VERSION="1.14.1"
BUILD_DIR=$(mktemp -d "${TMPDIR:-/private/tmp}/StealthReader-build.XXXXXX")
STAGED_APP="$BUILD_DIR/$APP_NAME.app"
MODULE_CACHE="${TMPDIR:-/private/tmp}/StealthReader-ModuleCache"
APP_DIR="$PROJECT_DIR/$APP_NAME.app"
ARCHIVE="$PROJECT_DIR/$APP_NAME-macOS-$(uname -m)-v$VERSION.zip"

# Keep compiler caches out of the project and ship only the application bundle.
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources" "$MODULE_CACHE"
swiftc -O -parse-as-library -target "$(uname -m)-apple-macosx13.0" \
    -module-cache-path "$MODULE_CACHE" \
    "$PROJECT_DIR"/Sources/StealthReader/*.swift \
    -o "$STAGED_APP/Contents/MacOS/$APP_NAME" \
    -framework SwiftUI -framework AppKit -framework CoreFoundation
cp "$PROJECT_DIR/Resources/Info.plist" "$STAGED_APP/Contents/Info.plist"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$STAGED_APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$STAGED_APP"
codesign --verify --strict "$STAGED_APP"
plutil -lint "$STAGED_APP/Contents/Info.plist"

# Omit Finder metadata; it can invalidate a signed application after extraction.
ditto --norsrc --noextattr "$STAGED_APP" "$APP_DIR"
if xattr -p com.apple.FinderInfo "$APP_DIR" >/dev/null 2>&1; then
    xattr -d com.apple.FinderInfo "$APP_DIR"
fi
codesign --verify --strict "$APP_DIR"
ditto -c -k --norsrc --noextattr --keepParent "$STAGED_APP" "$ARCHIVE"
unzip -tq "$ARCHIVE"
echo "应用：$APP_DIR"
echo "安装包：$ARCHIVE"
