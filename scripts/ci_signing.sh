#!/bin/bash
# CI only: loads the release signing certificate from the repository secrets
# MCCLOSE_SIGNING_P12 (base64 of the .p12) and MCCLOSE_SIGNING_PASSWORD into a
# temporary keychain, and tells scripts/build.sh to sign with it. Signing every
# release with the same certificate lets macOS keep MC Close's Accessibility
# permission across updates. Without the secrets, builds are signed ad hoc.
set -euo pipefail

if [ -z "${MCCLOSE_SIGNING_P12:-}" ] || [ -z "${MCCLOSE_SIGNING_PASSWORD:-}" ]; then
    echo "::warning::No signing certificate in the repository secrets; building ad hoc (users will need to re-allow Accessibility after updating)."
    exit 0
fi

kc="${RUNNER_TEMP}/mcclose-signing.keychain-db"
kcpw=$(openssl rand -hex 16)
security create-keychain -p "${kcpw}" "${kc}"
security set-keychain-settings -lut 21600 "${kc}"
security unlock-keychain -p "${kcpw}" "${kc}"
printf '%s' "${MCCLOSE_SIGNING_P12}" | base64 --decode > "${RUNNER_TEMP}/mcclose.p12"
security import "${RUNNER_TEMP}/mcclose.p12" -k "${kc}" -P "${MCCLOSE_SIGNING_PASSWORD}" -T /usr/bin/codesign >/dev/null
rm -f "${RUNNER_TEMP}/mcclose.p12"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "${kcpw}" "${kc}" >/dev/null
# Put it on the search list so codesign finds the identity.
existing=$(security list-keychains -d user | tr -d '"' | xargs)
# shellcheck disable=SC2086  # the existing list is several paths
security list-keychains -d user -s "${kc}" ${existing}

# A self-made certificate isn't trusted by default; trust it for code signing on this runner only.
security find-certificate -c "MC Close Signing" -p "${kc}" > "${RUNNER_TEMP}/mcclose-cert.pem"
sudo security add-trusted-cert -d -r trustRoot -p codeSign -k /Library/Keychains/System.keychain \
    "${RUNNER_TEMP}/mcclose-cert.pem" || echo "(could not mark the certificate trusted; trying to sign anyway)"
security find-identity -v -p codesigning "${kc}" || true

echo "MCCLOSE_SIGN_IDENTITY=MC Close Signing" >> "${GITHUB_ENV}"
echo "MCCLOSE_KEYCHAIN=${kc}" >> "${GITHUB_ENV}"
echo "Signing certificate ready."
