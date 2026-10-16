#!/bin/zsh
set -eu
cd "${0:A:h:h}"
staging=$(mktemp -d "${TMPDIR:-/tmp}/stablebar-installer.XXXXXX")
trap 'rm -rf "$staging"' EXIT
./scripts/build.sh "$staging/StableBar.app"
ln -s /Applications "$staging/Applications"
cat > "$staging/Install StableBar.txt" <<'EOF'
Welcome to StableBar

1. Drag StableBar to Applications.
2. Open StableBar from Applications.
3. Follow the setup to choose your appearance, placement, and startup preferences.

The starter bar needs no special permissions or third-party tools.
Run setup again from Customize StableBar → General, in the StableBar icon in your macOS menu bar.

Requires macOS 14 or later. This build is for the same processor family as the Mac that built it.
EOF
mkdir -p dist
hdiutil create -volname StableBar -srcfolder "$staging" -format UDZO -ov dist/StableBar.dmg
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
    codesign --force --timestamp --sign "$SIGNING_IDENTITY" dist/StableBar.dmg
fi
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit dist/StableBar.dmg --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple dist/StableBar.dmg
    xcrun stapler validate dist/StableBar.dmg
fi
