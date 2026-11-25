#!/bin/bash
# Installs (or updates) MC Close, a menu-bar app that closes windows from Mission Control.
#
#   curl -fsSL https://github.com/anujbajaj4/fixing_macos/releases/latest/download/install.sh | bash
#
# What it does: downloads MCClose.dmg from the latest GitHub release, copies
# MCClose.app into /Applications (or ~/Applications if that isn't writable),
# and opens it. No sudo. Read it first:
#   https://github.com/anujbajaj4/fixing_macos (install.sh)
#
# Test overrides: MCCLOSE_DMG_URL (file:// works), MCCLOSE_APPS_DIR, MCCLOSE_NO_OPEN=1

say()  { printf '%s\n' "$*"; }
fail() { printf 'MC Close install failed: %s\n' "$*" >&2; exit 1; }

cleanup() {
    if [ -n "${mnt:-}" ] && [ -d "${mnt}" ]; then hdiutil detach -quiet -force "${mnt}" </dev/null >/dev/null 2>&1 || true; fi
    [ -n "${tmp:-}" ] && rm -rf "${tmp}"
}

quit_running_app() {
    pgrep -xq MCClose || return 0
    say "Quitting the running MC Close…"
    osascript -e 'tell application id "io.github.anujbajaj4.MCClose" to quit' </dev/null >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -xq MCClose || return 0
        sleep 0.5
    done
    pkill -x MCClose 2>/dev/null || true
    sleep 0.5
}

# Everything lives in main, called on the last line, so a download cut off
# halfway runs nothing.
main() {
    set -euo pipefail
    local url="${MCCLOSE_DMG_URL:-https://github.com/anujbajaj4/fixing_macos/releases/latest/download/MCClose.dmg}"
    local bundle_id="io.github.anujbajaj4.MCClose"

    [ "$(uname -s)" = Darwin ] || fail "this computer isn't a Mac."
    local os major
    os=$(sw_vers -productVersion)
    major=${os%%.*}
    [ "${major}" -ge 13 ] || fail "MC Close needs macOS 13 (Ventura) or later; this Mac has ${os}."

    tmp=$(mktemp -d "${TMPDIR:-/tmp}/mcclose.XXXXXX")
    mnt="${tmp}/mnt"
    trap cleanup EXIT
    mkdir -p "${mnt}"

    say "Downloading MC Close…"
    curl -fL --progress-bar --retry 2 -o "${tmp}/MCClose.dmg" "${url}" ||
        fail "couldn't download ${url}. Check your internet connection and try again."
    hdiutil attach -nobrowse -readonly -noautoopen -quiet -mountpoint "${mnt}" "${tmp}/MCClose.dmg" </dev/null ||
        fail "couldn't open the downloaded disk image."
    [ -d "${mnt}/MCClose.app" ] || fail "the disk image doesn't contain MCClose.app."

    local apps="${MCCLOSE_APPS_DIR:-/Applications}"
    if [ -z "${MCCLOSE_APPS_DIR:-}" ] && [ ! -w "${apps}" ]; then
        apps="${HOME}/Applications"
        say "/Applications isn't writable for your account, so installing into ${apps} instead."
    fi
    mkdir -p "${apps}"

    local upgrading=0
    [ -d "${apps}/MCClose.app" ] && upgrading=1
    quit_running_app
    rm -rf "${apps:?}/MCClose.app"
    ditto "${mnt}/MCClose.app" "${apps}/MCClose.app"
    xattr -dr com.apple.quarantine "${apps}/MCClose.app" 2>/dev/null || true
    if hdiutil detach -quiet "${mnt}" </dev/null; then rmdir "${mnt}" 2>/dev/null || true; fi

    if [ "${upgrading}" = 1 ]; then
        # Each build has a new ad-hoc signature, so macOS's old Accessibility
        # entry no longer applies. Clear it so the new version can ask again.
        tccutil reset Accessibility "${bundle_id}" >/dev/null 2>&1 || true
    fi

    local version
    version=$(defaults read "${apps}/MCClose.app/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "?")
    say "Installed MC Close ${version} in ${apps}."

    if [ "${MCCLOSE_NO_OPEN:-0}" != 1 ]; then
        open "${apps}/MCClose.app"
        say ""
        say "Next: in the MC Close window, click Open Accessibility Settings and switch MC Close on."
        if [ "${upgrading}" = 1 ]; then
            say "(After an update macOS asks again: switch MC Close on once more.)"
        fi
        say "Then open Mission Control, point at a window and press ⌘W, or click the ✕."
        say "No window? Click the MC Close icon in the menu bar (top right) and choose Set Up…"
    fi
}

main "$@"
