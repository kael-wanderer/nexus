#!/usr/bin/env bash
#
# Package build/Nexus.app into a distributable disk image.
#
# One image per architecture, named after the version and the architecture that
# produced it: `NEXUS_ARCH=x86_64 scripts/build-app.sh && scripts/make-dmg.sh`
# packages the Intel artifact from the same commit as the Apple Silicon one.
#
# Nothing here is bundled beyond the app and a symlink to /Applications:
# hdiutil is Apple's, and a third-party DMG builder would be a dependency in the
# release path with its own provenance question.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
ROOT="$PWD"

APP_NAME="Nexus"
EXECUTABLE="NexusApp"
APP_DIR="$ROOT/build/$APP_NAME.app"

if [[ ! -d "$APP_DIR" ]]; then
    echo "No $APP_DIR — run scripts/build-app.sh first." >&2
    exit 1
fi

PLIST="$APP_DIR/Contents/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"

# The architecture is read from the artifact rather than from the environment. A
# stale bundle from the other architecture would otherwise be packaged under
# this one's name, which is the same class of mistake build-app.sh guards
# against by rebuilding the bundle from scratch.
ARCH="$(lipo -archs "$APP_DIR/Contents/MacOS/$EXECUTABLE")"
case "$ARCH" in
    arm64 | x86_64) ;;
    *)
        echo "Unexpected architecture in the bundle: '$ARCH'." >&2
        exit 1
        ;;
esac

# The signature is verified before packaging, not after. An image is a read-only
# artifact; discovering a broken signature inside one means rebuilding the image
# rather than re-signing it.
codesign --verify --strict "$APP_DIR"

DMG_PATH="$ROOT/build/$APP_NAME-$VERSION-$ARCH.dmg"
STAGE="$(mktemp -d)"

cp -R "$APP_DIR" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG_PATH"

BACKGROUND_PNG="$ROOT/scripts/dmg-background.png"

# Detach tolerating the "Resource busy" flake: Finder or Spotlight may still
# hold the freshly styled volume for a second after the window closes.
detach_retry() {
    local device="$1" attempt
    for attempt in 1 2 3 4 5; do
        if hdiutil detach "$device" > /dev/null 2>&1; then return 0; fi
        sleep 2
    done
    hdiutil detach "$device" -force > /dev/null
}

# DMG_FANCY=1 (the default) arranges the Finder window the user sees on open:
# the two icon positions, no toolbar, and a background picture if there is one to
# use. It needs Finder scripting, so CI sets DMG_FANCY=0 and gets the plain
# image — the same contents, laid out by Finder's defaults.
if [[ "${DMG_FANCY:-1}" == "1" ]]; then
    if [[ -f "$BACKGROUND_PNG" ]]; then
        mkdir "$STAGE/.background"
        cp "$BACKGROUND_PNG" "$STAGE/.background/background.png"
        BACKGROUND_LINE='set background picture of opts to file ".background:background.png"'
    else
        BACKGROUND_LINE='-- no scripts/dmg-background.png: the window keeps its plain background'
    fi

    # Kept outside $STAGE: hdiutil would otherwise copy the growing image into
    # itself until the disk filled.
    RW_DMG="$(mktemp -u "${TMPDIR:-/tmp}/nexus-rw.XXXXXX").dmg"
    # Built under a unique volume name. A volume already called "Nexus" — an
    # earlier image the user still has mounted — is what `tell disk` would
    # otherwise style, and this image would ship with no .DS_Store at all.
    BUILD_VOLNAME="$APP_NAME-dmg-$$"
    hdiutil create \
        -volname "$BUILD_VOLNAME" \
        -srcfolder "$STAGE" \
        -fs HFS+ -format UDRW -ov -quiet \
        "$RW_DMG"
    ATTACH_OUT="$(hdiutil attach "$RW_DMG" -readwrite -noverify -nobrowse)"
    # Detach by device node: the rename below moves the mount point.
    DEV_NODE="$(echo "$ATTACH_OUT" | awk 'NR==1 {print $1}')"
    MOUNT_DIR="$(echo "$ATTACH_OUT" | awk -F'\t' '/\/Volumes\// {print $NF; exit}')"

    osascript > /dev/null << EOF
tell application "Finder"
    -- macOS registers a freshly attached -nobrowse volume lazily: the first
    -- \`tell disk\` errors -1728 ("Can't get disk") if Finder has not
    -- enumerated it yet. Probing \`exists disk\` forces that enumeration.
    set waited to 0
    repeat until (exists disk "$BUILD_VOLNAME") or waited > 50
        delay 0.2
        set waited to waited + 1
    end repeat
    tell disk "$BUILD_VOLNAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 200, 800, 640}
        set opts to the icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 100
        $BACKGROUND_LINE
        set position of item "$APP_NAME.app" of container window to {150, 195}
        set position of item "Applications" of container window to {450, 195}
        -- Forces Finder to flush the view settings into the volume's .DS_Store
        -- before the detach. Without it the styled window appears only
        -- sometimes, depending on which build won the write race.
        update without registering applications
        delay 2
        close
    end tell
end tell
EOF
    sleep 2
    sync
    # An unstyled image is a silent regression — it looks like a normal DMG — so
    # a missing .DS_Store fails the run rather than shipping.
    if [[ ! -f "$MOUNT_DIR/.DS_Store" ]]; then
        echo "Finder never wrote $MOUNT_DIR/.DS_Store — the styled layout would be missing." >&2
        detach_retry "$DEV_NODE" || true
        rm -f "$RW_DMG"
        exit 1
    fi
    diskutil rename "$MOUNT_DIR" "$APP_NAME" > /dev/null
    detach_retry "$DEV_NODE"
    hdiutil convert "$RW_DMG" -format UDZO -ov -quiet -o "$DMG_PATH" > /dev/null
    rm -f "$RW_DMG"
else
    hdiutil create \
        -volname "$APP_NAME $VERSION" \
        -srcfolder "$STAGE" \
        -ov -format UDZO \
        -quiet \
        "$DMG_PATH"
fi

rm -rf "$STAGE"

# Verify what actually came out, rather than what was asked for: the image
# mounts, the app inside it is the architecture this run claims, and its
# signature survived the copy.
MOUNT="$(mktemp -d)"
hdiutil attach "$DMG_PATH" -mountpoint "$MOUNT" -nobrowse -quiet -readonly
trap 'hdiutil detach "$MOUNT" -quiet 2> /dev/null || true; rmdir "$MOUNT" 2> /dev/null || true' EXIT

MOUNTED_APP="$MOUNT/$APP_NAME.app"
MOUNTED_ARCH="$(lipo -archs "$MOUNTED_APP/Contents/MacOS/$EXECUTABLE")"
if [[ "$MOUNTED_ARCH" != "$ARCH" ]]; then
    echo "Packaged app is '$MOUNTED_ARCH' but the image is named '$ARCH'." >&2
    exit 1
fi
codesign --verify --strict "$MOUNTED_APP"

SIZE="$(du -h "$DMG_PATH" | cut -f1 | tr -d ' ')"
echo "Built $DMG_PATH — $VERSION ($BUILD), $ARCH, $SIZE, signature verified from the mounted image"
shasum -a 256 "$DMG_PATH"

# Notarisation is deliberately not attempted here: it needs a Developer ID
# certificate, which Nexus does not have. A self-signed image raises Gatekeeper
# on any machine but the one that built it, and saying so is more useful than a
# script that appears to handle it. The README's right-click → Open instructions
# are the other half of this.
echo "Not notarised: the signing identity is self-signed. Gatekeeper will warn on other machines."
