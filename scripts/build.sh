#!/bin/bash
# Builds MC Close without Xcode (the Command Line Tools are enough):
#   scripts/build.sh            -> build/MCClose.app and build/MCClose.dmg (universal, ad-hoc signed)
#   scripts/build.sh --test     -> also compiles and runs the logic tests first
# Needs macOS with `xcode-select --install` done.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
version=$(tr -d '[:space:]' < VERSION)
app_name="MCClose"
bundle_id="io.github.anujbajaj4.MCClose"
min_macos="13.0"
build="$root/build"
app="$build/${app_name}.app"

[ "$(uname -s)" = Darwin ] || { echo "This builds a Mac app, so it has to run on a Mac." >&2; exit 1; }
sdk=$(xcrun --sdk macosx --show-sdk-path)

if [ "${1:-}" = "--test" ]; then
    echo "==> Logic tests"
    mkdir -p "$build"
    xcrun swiftc -sdk "$sdk" Sources/Core/*.swift Tests/main.swift -o "$build/core-tests"
    "$build/core-tests"
fi

echo "==> Compiling MC Close ${version} (arm64 + x86_64, macOS ${min_macos}+)"
rm -rf "$app" "$build/arm64" "$build/x86_64"
for arch in arm64 x86_64; do
    mkdir -p "$build/$arch"
    xcrun swiftc -O -parse-as-library -whole-module-optimization \
        -sdk "$sdk" -target "${arch}-apple-macos${min_macos}" \
        -module-name "$app_name" \
        Sources/Core/*.swift Sources/MCClose/*.swift \
        -o "$build/$arch/$app_name"
done

mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
lipo -create "$build/arm64/$app_name" "$build/x86_64/$app_name" -output "$app/Contents/MacOS/$app_name"

if [ -d assets/AppIcon.iconset ]; then
    iconutil -c icns assets/AppIcon.iconset -o "$app/Contents/Resources/AppIcon.icns"
fi

cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>${app_name}</string>
    <key>CFBundleIdentifier</key><string>${bundle_id}</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>MC Close</string>
    <key>CFBundleDisplayName</key><string>MC Close</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${version}</string>
    <key>CFBundleVersion</key><string>${version}</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>${min_macos}</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>MC Close. Free and open source.</string>
</dict>
</plist>
EOF
plutil -lint "$app/Contents/Info.plist"

# Releases are signed with one long-lived self-made certificate (MCCLOSE_SIGN_IDENTITY, set up
# by scripts/ci_signing.sh), so macOS sees every version as the same app and keeps its
# Accessibility permission. Without it, sign ad hoc (no Apple Developer account needed).
identity="${MCCLOSE_SIGN_IDENTITY:--}"
sign_args=(--force --deep --sign "$identity" --identifier "$bundle_id")
if [ -n "${MCCLOSE_KEYCHAIN:-}" ]; then sign_args+=(--keychain "${MCCLOSE_KEYCHAIN}"); fi
if [ "$identity" = "-" ]; then echo "==> Signing (ad hoc)"; else echo "==> Signing with \"${identity}\""; fi
codesign "${sign_args[@]}" "$app"
codesign --verify --deep --strict "$app"
echo "designated requirement: $(codesign -dr - "$app" 2>&1 | sed -n 's/^designated => //p')"
echo "architectures: $(lipo -archs "$app/Contents/MacOS/$app_name")"

echo "==> Disk image"
stage="$build/dmg"
rm -rf "$stage" "$build/${app_name}.dmg"
mkdir -p "$stage"
ditto "$app" "$stage/${app_name}.app"
ln -s /Applications "$stage/Applications"
hdiutil create -quiet -volname "MC Close ${version}" -srcfolder "$stage" -fs HFS+ -format UDZO \
    "$build/${app_name}.dmg"
rm -rf "$stage"
echo "Built $app"
echo "Built $build/${app_name}.dmg"
