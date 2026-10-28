#!/bin/zsh
# Source from the repository root. Configuration contains a public certificate
# fingerprint, never a private key or a Keychain password.

twister_load_signing_configuration() {
  local configuration=${TWISTER_SIGNING_CONFIG:-"$PWD/Configuration/Signing.plist"}
  local configured_mode="" configured_identity=""
  if [[ -f "$configuration" ]]; then
    plutil -lint "$configuration" >/dev/null || { print -u2 "Invalid signing configuration: $configuration"; return 1; }
    configured_mode=$(plutil -extract Mode raw -expect string -o - "$configuration") || { print -u2 "Signing configuration requires a string Mode."; return 1; }
    if plutil -type IdentitySHA1 "$configuration" >/dev/null 2>&1; then
      configured_identity=$(plutil -extract IdentitySHA1 raw -expect string -o - "$configuration") || { print -u2 "IdentitySHA1 must be a string."; return 1; }
    fi
  elif [[ -n "${TWISTER_SIGNING_CONFIG:-}" ]]; then
    print -u2 "Signing configuration does not exist: $configuration"; return 1
  fi

  twister_signing_mode=${TWISTER_SIGNING_MODE:-${configured_mode:-ad-hoc}}
  twister_signing_identity=${TWISTER_SIGNING_IDENTITY:-$configured_identity}
  if [[ -z "$twister_signing_identity" && "$twister_signing_mode" == ad-hoc ]]; then twister_signing_identity="-"; fi
  case "$twister_signing_mode" in
    ad-hoc)
      if [[ "$twister_signing_identity" != "-" ]]; then print -u2 "A certificate identity requires explicit local, apple-development, or developer-id signing mode."; return 1; fi
      twister_signing_flags=(--force --sign - --options 0 --timestamp=none)
      ;;
    local|apple-development|developer-id)
      if [[ ! "$twister_signing_identity" =~ '^[0-9A-Fa-f]{40}$' ]]; then print -u2 "Stable signing requires the exact 40-hex certificate SHA-1, not a certificate name."; return 1; fi
      twister_signing_identity=${twister_signing_identity:u}
      twister_signing_flags=(--force --sign "$twister_signing_identity")
      if [[ "$twister_signing_mode" != developer-id ]]; then
        twister_signing_flags+=(--options 0 --timestamp=none)
      else
        twister_signing_flags+=(--options runtime --timestamp)
      fi
      ;;
    *) print -u2 "Signing Mode must be ad-hoc, local, apple-development, or developer-id."; return 1 ;;
  esac
  if [[ -n "${TWISTER_NOTARY_PROFILE:-}" && "$twister_signing_mode" != developer-id ]]; then
    print -u2 "Notarization requires developer-id signing mode."; return 1
  fi
  export TWISTER_SIGNING_MODE="$twister_signing_mode"
  export TWISTER_SIGNING_IDENTITY="$twister_signing_identity"
}

twister_require_release_signing() {
  local scope=${1:-release}
  if [[ "$twister_signing_mode" == apple-development || "$twister_signing_mode" == developer-id ]]; then return 0; fi
  # The release integration fixture uses an isolated, validated loopback feed.
  # Publishing never accepts this exception, even when its flag is inherited.
  if [[ "$scope" == local-test && "${TWISTER_ALLOW_AD_HOC_TEST_RELEASE:-}" == 1 ]]; then return 0; fi
  # A pinned local certificate is suitable only for explicit local integration
  # tests. Distributed releases must use an Apple-issued signing identity.
  if [[ "$scope" == local-test && "$twister_signing_mode" == local ]]; then return 0; fi
  print -u2 "Release signing is not configured. Pin an Apple Development or Developer ID certificate in Configuration/Signing.plist; local and ad-hoc releases are refused."
  return 1
}

twister_verify_release_app() {
  twister_verify_signing_identity "$1" || return 1
}

twister_verify_signing_identity() {
  local code=$1
  if [[ "$twister_signing_mode" == ad-hoc ]]; then return 0; fi
  codesign --verify --strict --test-requirement "=certificate leaf = H\"$twister_signing_identity\"" "$code" || return 1
  if [[ "$twister_signing_mode" == developer-id ]]; then
    codesign --verify --strict --test-requirement '=anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists' "$code" || {
      print -u2 "developer-id mode requires an Apple-issued Developer ID Application certificate."; return 1
    }
  elif [[ "$twister_signing_mode" == apple-development ]]; then
    # Apple's securityd development branch: WWDR CA and Mac Development leaf.
    # https://github.com/apple-oss-distributions/Security/blob/db15acbe6a7f257a859ad9a3bb86097bfe0679d9/securityd/src/clientid.cpp#L207-L211
    codesign --verify --strict --test-requirement '=anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.1] exists and certificate leaf[field.1.2.840.113635.100.6.1.12] exists' "$code" || {
      print -u2 "apple-development mode requires an Apple-issued Mac Development certificate."; return 1
    }
  fi
}
