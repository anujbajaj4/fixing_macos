#!/bin/bash
# shellcheck disable=SC2015,SC2016  # "a && ok || bad" is fine here; fake bodies must stay unexpanded
# Tests install.sh on any system (Linux too) with fake macOS tools on PATH.
#   bash Tests/install_test.sh
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
pass=0
failed=0
ok()  { pass=$((pass + 1)); echo "ok   $1"; }
bad() { failed=$((failed + 1)); echo "FAIL $1"; }

# A fake "disk image": a tarball that the fake hdiutil extracts at the mount point.
mkdir -p "$work/src/MCClose.app/Contents/MacOS"
echo '#!/bin/sh' > "$work/src/MCClose.app/Contents/MacOS/MCClose"
chmod +x "$work/src/MCClose.app/Contents/MacOS/MCClose"
tar -C "$work/src" -cf "$work/MCClose.dmg" MCClose.app

bin="$work/bin"
mkdir -p "$bin"
log="$work/calls.log"
fake() { printf '#!/bin/bash\necho "%s $*" >> "%s"\n%s\n' "$1" "$log" "$2" > "$bin/$1"; chmod +x "$bin/$1"; }
fake uname     'echo "${FAKE_UNAME:-Darwin}"'
fake sw_vers   'echo "${FAKE_OS:-14.5}"'
fake hdiutil   'if [ "$1" = attach ]; then for a in "$@"; do last=$a; done; prev=""; for a in "$@"; do [ "$prev" = -mountpoint ] && mp=$a; prev=$a; done; tar -C "$mp" -xf "$last"; elif [ "$1" = detach ]; then for a in "$@"; do last=$a; done; [ -d "$last" ] && rm -rf "${last:?}"/*; fi; true'
fake ditto     'cp -R "$1" "$2"'
fake xattr     'true'
fake defaults  'echo 9.9.9'
fake open      'true'
fake pgrep     'exit 1'
fake pkill     'true'
fake osascript 'true'
fake tccutil   'true'

run() {   # run the installer the way users do: piped into bash
    PATH="$bin:$PATH" MCCLOSE_DMG_URL="${DMG:-file://$work/MCClose.dmg}" \
        MCCLOSE_MIRROR_URL="${MIRROR:-file://$work/missing-mirror.dmg}" MCCLOSE_APPS_DIR="$work/Applications" MCCLOSE_NO_OPEN="${NO_OPEN:-1}" \
        bash < "$root/install.sh" > "$work/out.txt" 2>&1
}

: > "$log"
if run && [ -x "$work/Applications/MCClose.app/Contents/MacOS/MCClose" ]; then ok "fresh install copies the app"; else bad "fresh install"; cat "$work/out.txt"; fi
grep -q "Installed MC Close 9.9.9" "$work/out.txt" && ok "reports the installed version" || bad "version message"
grep -q "^tccutil" "$log" && bad "fresh install shouldn't reset permission" || ok "fresh install leaves permission alone"
grep -q "^xattr -dr com.apple.quarantine" "$log" && ok "removes quarantine flag" || bad "quarantine"
grep -q "^hdiutil attach" "$log" && grep -q "^hdiutil detach" "$log" && ok "mounts and unmounts" || bad "mount/unmount"

: > "$log"
touch "$work/Applications/MCClose.app/stale-file"
if run && [ ! -e "$work/Applications/MCClose.app/stale-file" ]; then ok "upgrade replaces the old app"; else bad "upgrade replace"; fi
grep -q "^tccutil reset Accessibility io.github.anujbajaj4.MCClose" "$log" && ok "upgrade resets stale Accessibility entry" || bad "upgrade tccutil"

: > "$log"
NO_OPEN=0 run && grep -q "^open .*MCClose.app" "$log" && grep -q "Open Accessibility Settings" "$work/out.txt" \
    && ok "opens the app and explains next steps" || bad "open + next steps"

if FAKE_OS=12.7 run; then bad "old macOS should be refused"; else grep -q "needs macOS 13" "$work/out.txt" && ok "refuses macOS 12 with a clear message" || bad "macOS 12 message"; fi
if FAKE_UNAME=Linux run; then bad "non-Mac should be refused"; else grep -q "isn't a Mac" "$work/out.txt" && ok "refuses non-Mac" || bad "non-Mac message"; fi

if DMG="file://$work/missing.dmg" run; then bad "missing download should fail"
else grep -q "couldn't download MC Close from GitHub or the mirror" "$work/out.txt" && ok "download failure (both hosts) is explained" || bad "download failure message"; fi

rm -rf "$work/Applications"
if DMG="file://$work/missing.dmg" MIRROR="file://$work/MCClose.dmg" run \
    && [ -x "$work/Applications/MCClose.app/Contents/MacOS/MCClose" ] && grep -q "Trying the mirror" "$work/out.txt"; then
    ok "falls back to the mirror when GitHub's download server fails"
else bad "mirror fallback"; cat "$work/out.txt"; fi

# A download cut off halfway must run nothing (all work is inside main, called last).
head -c 1500 "$root/install.sh" > "$work/partial.sh"
: > "$log"
PATH="$bin:$PATH" bash < "$work/partial.sh" > /dev/null 2>&1 || true
[ ! -s "$log" ] && ok "truncated script does nothing" || bad "truncated script ran commands"

# bash 3.2 (macOS) misreads "$var…" before non-ASCII characters; require ${var}.
if grep -nE '\$[A-Za-z_][A-Za-z0-9_]*[^ -~]' "$root/install.sh" "$root/scripts/build.sh"; then
    bad "use \${var} before non-ASCII characters (bash 3.2)"
else ok "no \$var directly before non-ASCII"; fi

echo "$pass passed, $failed failed"
[ "$failed" = 0 ]
