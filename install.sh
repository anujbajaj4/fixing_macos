#!/bin/bash
# Installs (or updates) MC Close, a menu-bar app that closes windows from Mission Control.
#
#   curl -fsSL https://anujbajaj4.github.io/fixing_macos/install.sh | bash
#
# What it does: downloads MCClose.dmg from the latest GitHub release (or, if
# GitHub's download server can't be reached, from the GitHub Pages mirror), copies
# MCClose.app into /Applications (or ~/Applications if that isn't writable),
# and opens it. No sudo. Read it first:
#   https://github.com/anujbajaj4/fixing_macos (install.sh)
#
# Test overrides: MCCLOSE_DMG_URL and MCCLOSE_MIRROR_URL (file:// works),
#                 MCCLOSE_APPS_DIR, MCCLOSE_NO_OPEN=1

say()  { printf '%s\n' "$*"; }
fail() { printf 'MC Close install failed: %s\n' "$*" >&2; exit 1; }

cleanup() {
    if [ -n "${mnt:-}" ] && [ -d "${mnt}" ]; then hdiutil detach -quiet -force "${mnt}" </dev/null >/dev/null 2>&1 || true; fi
    [ -n "${tmp:-}" ] && rm -rf "${tmp}"
}

# What macOS ties the Accessibility permission to: the app's designated requirement.
designated_requirement() {
    codesign -dr - "$1" 2>&1 | sed -n 's/^designated => //p'
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
    local mirror="${MCCLOSE_MIRROR_URL:-https://anujbajaj4.github.io/fixing_macos/MCClose.dmg}"
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
    # Some networks can't reach GitHub's download server (release-assets.githubusercontent.com)
    # and just hang, so give it 10 seconds to connect, then use the mirror.
    if ! curl -fL --progress-bar --connect-timeout 10 --retry 1 -o "${tmp}/MCClose.dmg" "${url}"; then
        say "GitHub's download server didn't answer. Trying the mirror…"
        curl -fL --progress-bar --connect-timeout 15 --retry 1 -o "${tmp}/MCClose.dmg" "${mirror}" ||
            fail "couldn't download MC Close from GitHub or the mirror. Check your internet connection; if GitHub is blocked on your network, setting DNS to 1.1.1.1 in System Settings ▸ Wi-Fi ▸ Details ▸ DNS often helps."
    fi
    hdiutil attach -nobrowse -readonly -noautoopen -quiet -mountpoint "${mnt}" "${tmp}/MCClose.dmg" </dev/null ||
        fail "couldn't open the downloaded disk image."
    [ -d "${mnt}/MCClose.app" ] || fail "the disk image doesn't contain MCClose.app."

    local apps="${MCCLOSE_APPS_DIR:-/Applications}"
    if [ -z "${MCCLOSE_APPS_DIR:-}" ] && [ ! -w "${apps}" ]; then
        apps="${HOME}/Applications"
        say "/Applications isn't writable for your account, so installing into ${apps} instead."
    fi
    mkdir -p "${apps}"

    local upgrading=0 old_req=""
    if [ -d "${apps}/MCClose.app" ]; then
        upgrading=1
        old_req=$(designated_requirement "${apps}/MCClose.app")
    fi
    quit_running_app
    rm -rf "${apps:?}/MCClose.app"
    ditto "${mnt}/MCClose.app" "${apps}/MCClose.app"
    xattr -dr com.apple.quarantine "${apps}/MCClose.app" 2>/dev/null || true
    if hdiutil detach -quiet "${mnt}" </dev/null; then rmdir "${mnt}" 2>/dev/null || true; fi

    # Releases signed with the same certificate keep their Accessibility permission.
    # If the signature changed (e.g. an ad-hoc build), the old entry no longer applies:
    # clear it so the new version can ask again.
    local reset=0 new_req
    new_req=$(designated_requirement "${apps}/MCClose.app")
    if [ "${upgrading}" = 1 ]; then
        case "${new_req}" in
            *cdhash*) reset=1 ;;
            *) [ -n "${old_req}" ] && [ "${old_req}" = "${new_req}" ] || reset=1 ;;
        esac
        if [ "${reset}" = 1 ]; then
            tccutil reset Accessibility "${bundle_id}" >/dev/null 2>&1 || true
        fi
    fi

    local version
    version=$(defaults read "${apps}/MCClose.app/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "?")
    say "Installed MC Close ${version} in ${apps}."

    if [ "${MCCLOSE_NO_OPEN:-0}" != 1 ]; then
        open "${apps}/MCClose.app"
        say ""
        say "Next: in the MC Close window, click Open Accessibility Settings and switch MC Close on."
        if [ "${upgrading}" = 1 ] && [ "${reset}" = 1 ]; then
            say "(This update needs the permission again: switch MC Close on once more.)"
        elif [ "${upgrading}" = 1 ]; then
            say "(Your Accessibility permission carries over: nothing to do.)"
        fi
        say "Then open Mission Control, point at a window and press ⌘W, or click the ✕."
        say "No window? Click the MC Close icon in the menu bar (top right) and choose Set Up…"
    fi
}

main "$@"
