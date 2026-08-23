#!/usr/bin/env bash
#
# Assemble build/Nexus.app from the Swift package.
#
# Architecture is a build parameter, never a branch and never a universal
# binary: `NEXUS_ARCH=x86_64 scripts/build-app.sh` produces the Intel artifact
# from the same commit as the arm64 one.
#
# Signing matters more here than it does for most applications. macOS keys TCC
# grants — Accessibility, Screen Recording — to the code signature, so an
# ad-hoc signature (which changes on every build) resets every grant Nexus has
# been given. Any *stable* identity keeps them; a self-signed certificate works
# as well as an Apple one (D1).

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
ROOT="$PWD"

NEXUS_ARCH="${NEXUS_ARCH:-arm64}"
case "$NEXUS_ARCH" in
    arm64 | x86_64) ;;
    *)
        echo "Unsupported NEXUS_ARCH: $NEXUS_ARCH (expected arm64 or x86_64)." >&2
        exit 1
        ;;
esac

CONFIGURATION="${CONFIGURATION:-release}"
APP_NAME="Nexus"
EXECUTABLE="NexusApp"
BUNDLE_ID="com.congbui.nexus"
APP_DIR="$ROOT/build/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

swift build --package-path "$ROOT" -c "$CONFIGURATION" --arch "$NEXUS_ARCH" --product "$EXECUTABLE"
BIN_PATH="$(swift build --package-path "$ROOT" -c "$CONFIGURATION" --arch "$NEXUS_ARCH" --show-bin-path)"

# Rebuild the bundle from scratch. Reusing it lets a stale binary of the other
# architecture survive and be signed as if it belonged here.
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BIN_PATH/$EXECUTABLE" "$MACOS_DIR/$EXECUTABLE"
cp "$ROOT/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"

# The icon is committed rather than generated: `Resources/AppIcon.icns` is the
# one source of the mark, and there is no PNG to build it from. A bundle without
# it looks broken in the Finder, so a missing icon is a build failure.
if [[ ! -f "$ROOT/Resources/AppIcon.icns" ]]; then
    echo "Missing $ROOT/Resources/AppIcon.icns — the bundle would have no icon." >&2
    exit 1
fi
cp "$ROOT/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
# The menu-bar item's template images. Without them the status item draws nothing
# at all, which looks exactly like Nexus having failed to launch.
cp "$ROOT/Resources/NexusTemplate.png" "$ROOT/Resources/NexusTemplate@2x.png" "$RESOURCES_DIR/"

# SwiftPM emits a target's resources as a sibling .bundle next to the
# executable. Nexus declares none today, so this copies whatever is there and
# does not insist there be any — a target that gains resources is picked up
# without a change here.
for bundle in "$BIN_PATH"/*.bundle; do
    [[ -d "$bundle" ]] || continue
    cp -R "$bundle" "$RESOURCES_DIR/"
done

# Guard: a bundle whose binary is the wrong architecture will not launch, and a
# binary built above LSMinimumSystemVersion fails on the oldest supported system
# rather than being refused at install time. Check both before signing.
MIN_SYSTEM_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$CONTENTS_DIR/Info.plist")"
BINARY_ARCHS="$(lipo -archs "$MACOS_DIR/$EXECUTABLE" 2> /dev/null || echo unknown)"
if [[ "$BINARY_ARCHS" != "$NEXUS_ARCH" ]]; then
    echo "Built binary is '$BINARY_ARCHS' but this run targets '$NEXUS_ARCH'." >&2
    exit 1
fi
BINARY_MIN="$(otool -l "$MACOS_DIR/$EXECUTABLE" | awk '/LC_BUILD_VERSION/{f=1} f&&/^ *minos/{print $2; exit}')"
if [[ -n "$BINARY_MIN" ]]; then
    lowest="$(printf '%s\n%s\n' "$MIN_SYSTEM_VERSION" "$BINARY_MIN" | sort -V | head -1)"
    if [[ "$lowest" != "$BINARY_MIN" ]]; then
        echo "Binary requires macOS $BINARY_MIN but Info.plist advertises $MIN_SYSTEM_VERSION." >&2
        exit 1
    fi
fi

# Signing identity: whatever the caller asked for, then the local development
# certificate by name, then any valid codesigning identity, then ad hoc — which
# is announced, because it is the one that costs the user their TCC grants.
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ -z "$CODESIGN_IDENTITY" || "$CODESIGN_IDENTITY" == "-" ]]; then
    CODESIGN_IDENTITY="$(
        security find-identity -v -p codesigning 2> /dev/null |
            awk -F'"' '/"Bugler Local Dev"/{print $2; exit}'
    )"
fi
if [[ -z "$CODESIGN_IDENTITY" ]]; then
    CODESIGN_IDENTITY="$(
        security find-identity -v -p codesigning 2> /dev/null |
            awk -F'"' '/^ *[0-9]+\)/{print $2; exit}'
    )"
fi

# `--identifier` because the executable is NexusApp and the bundle is Nexus:
# codesign would otherwise derive an identifier from the binary's name, and TCC
# would file the grants under a name nothing else uses.
if [[ -n "$CODESIGN_IDENTITY" ]]; then
    codesign --force --sign "$CODESIGN_IDENTITY" --identifier "$BUNDLE_ID" "$APP_DIR"
    echo "Signed with: $CODESIGN_IDENTITY"
else
    codesign --force --sign - --identifier "$BUNDLE_ID" "$APP_DIR"
    echo "WARNING: no codesigning identity found; signed ad hoc." >&2
    echo "         An ad-hoc signature changes on every build, so every Accessibility and" >&2
    echo "         Screen Recording grant resets. Create any stable certificate —" >&2
    echo "         Keychain Access > Certificate Assistant > Create a Certificate" >&2
    echo "         (type: Code Signing) — and build again." >&2
fi

codesign --verify --strict "$APP_DIR"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$CONTENTS_DIR/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$CONTENTS_DIR/Info.plist")"
echo "Built $APP_DIR — $VERSION ($BUILD), $NEXUS_ARCH, min macOS $MIN_SYSTEM_VERSION"
