#!/bin/bash
# Build ClipMenu and assemble a runnable .app bundle, then launch it.
#
# Why a bundle: ClipMenu is an LSUIElement menu-bar agent. The LSUIElement key
# (and proper menu-bar / status-item registration) only takes effect when the
# binary runs inside a .app bundle — `swift run` launches a bare executable and
# the status-bar icon may not appear. Use this script instead of `swift run`.
#
# Usage:  ./scripts/run.sh [debug|release]
set -euo pipefail

cd "$(dirname "$0")/.."           # package root (app/)
CONFIG="${1:-debug}"

# Build the direct / Developer ID variant: compile in Sparkle so the auto-update
# UI is present locally. This mirrors .github/workflows/release.yml; the Mac App
# Store build (scripts/build-appstore.sh) deliberately leaves this unset, so Sparkle
# is excluded there (see Package.swift).
export CLIPMENU_SPARKLE=1

# Apple Silicon only: ClipMenu targets macOS 26, which Intel Macs cannot run, so
# we never ship an x86_64 slice. `--arch arm64` makes that explicit — the build
# fails loudly on a non-Apple-Silicon toolchain instead of silently producing an
# Intel binary.
swift build -c "$CONFIG" --arch arm64
BIN_PATH="$(swift build -c "$CONFIG" --arch arm64 --show-bin-path)"

# App display name follows the major version: 2.x.x -> "ClipMenu 2",
# 3.x.x -> "ClipMenu 3". Derived from CFBundleShortVersionString so bumping the
# major is the only edit needed. The bundle file and the user-visible name
# (CFBundleName / CFBundleDisplayName) take the versioned name; the executable
# and bundle id stay "ClipMenu" / com.dragonapp.clipmenu-2 so a user's settings and
# history carry across major versions.
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
MAJOR="${VERSION%%.*}"
APP_NAME="ClipMenu ${MAJOR}"

APP=".build/${APP_NAME}.app"
rm -rf ".build/ClipMenu.app" "$APP"   # also clear any old un-versioned bundle
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_PATH/ClipMenu" "$APP/Contents/MacOS/ClipMenu"
cp Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName ${APP_NAME}" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string ${APP_NAME}" "$APP/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName ${APP_NAME}" "$APP/Contents/Info.plist"

# App icon. CFBundleIconFile in Info.plist names "AppIcon"; macOS looks for
# Contents/Resources/AppIcon.icns. Without this the .app shows a generic icon
# in Finder, System Settings ▸ Login Items, the Gatekeeper prompt and the About box.
mkdir -p "$APP/Contents/Resources"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Copy the SwiftPM resource bundle (JS action scripts, menu-bar icon) into
# Contents/Resources so the .app is self-contained and can be moved/signed.
# AppResources looks for it there (Bundle.main.resourceURL/ClipMenu_ClipMenu.bundle);
# without this copy it only resolves via an absolute build path. SwiftPM marks
# the copied files read-only, so make them writable or the next run's rm fails.
RESOURCE_BUNDLE="ClipMenu_ClipMenu.bundle"
if [ -d "$BIN_PATH/$RESOURCE_BUNDLE" ]; then
    mkdir -p "$APP/Contents/Resources"
    cp -R "$BIN_PATH/$RESOURCE_BUNDLE" "$APP/Contents/Resources/$RESOURCE_BUNDLE"
    chmod -R u+w "$APP/Contents/Resources/$RESOURCE_BUNDLE"
fi

# Embed Sparkle.framework (auto-update). The SPARKLE build copies it into BIN_PATH;
# the executable finds it via the @loader_path/../Frameworks rpath (Package.swift).
# cp -R preserves the framework's internal symlinks (Versions/Current, etc.).
if [ -d "$BIN_PATH/Sparkle.framework" ]; then
    mkdir -p "$APP/Contents/Frameworks"
    cp -R "$BIN_PATH/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
    chmod -R u+w "$APP/Contents/Frameworks/Sparkle.framework"
fi

# Code-sign. Prefer a stable self-signed identity named "$SIGN_IDENTITY" if it
# exists in the keychain: signing with a stable identity keeps the Accessibility
# (TCC) grant across rebuilds, so you grant it once. Fall back to ad-hoc (whose
# hash changes every build, forcing a re-grant). To create the identity, see
# scripts/run.sh header / the README: Keychain Access ▸ Certificate Assistant ▸
# Create a Certificate… (Self-Signed Root, type "Code Signing"), name it below.
SIGN_IDENTITY="ClipMenu Dev"
# Note: no `-v` — a self-signed dev cert is reported "not trusted" (Gatekeeper
# won't honor it), but it signs fine and TCC keys on the stable identity, which
# is all we need. `-v` would hide it.
if security find-identity -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
    IDENTITY="$SIGN_IDENTITY"
    echo "Signing with identity: $SIGN_IDENTITY (TCC grant persists across rebuilds)"
else
    IDENTITY="-"
    echo "Ad-hoc signing ($SIGN_IDENTITY not found) — Accessibility grant resets each rebuild."
fi
# Sign the embedded Sparkle framework inside-out, before sealing the app — a
# nested framework must be signed first or the app's seal won't validate it.
# --deep is fine for a local dev build; release.yml signs each nested component
# explicitly with the hardened runtime for notarization.
if [ -d "$APP/Contents/Frameworks/Sparkle.framework" ]; then
    codesign --force --deep --sign "$IDENTITY" "$APP/Contents/Frameworks/Sparkle.framework" 2>/dev/null || true
fi
codesign --force --sign "$IDENTITY" "$APP" 2>/dev/null || true

echo "Assembled $APP"
# Relaunch cleanly if a previous instance is running.
pkill -x ClipMenu 2>/dev/null || true
open "$APP"
echo "Launched. Look for the clipboard icon in the menu bar (top-right)."
