#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
UPDATER_CONFIG="${ROOT_DIR}/config/updater.conf"

if [ ! -f "${UPDATER_CONFIG}" ]; then
    echo "Error: missing updater config at ${UPDATER_CONFIG}" >&2
    exit 1
fi

# shellcheck disable=SC1090
source "${UPDATER_CONFIG}"

if [ -z "${SPARKLE_PRIVATE_KEY:-}" ]; then
    echo "Error: SPARKLE_PRIVATE_KEY is not set" >&2
    exit 1
fi

DERIVED_PUBLIC_KEY="$({
    PRIVATE_KEY_BASE64="${SPARKLE_PRIVATE_KEY}" swift - <<'SWIFT'
import Foundation
import CryptoKit

let env = ProcessInfo.processInfo.environment
let privateKeyBase64 = (env["PRIVATE_KEY_BASE64"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

guard let decodedBytes = Data(base64Encoded: privateKeyBase64) else {
    fputs("Failed to decode SPARKLE_PRIVATE_KEY as base64\n", stderr)
    exit(1)
}

let seedBytes: Data
switch decodedBytes.count {
case 32:
    seedBytes = decodedBytes
case 64:
    seedBytes = decodedBytes.prefix(32)
default:
    fputs("Unexpected Sparkle private key byte length: \(decodedBytes.count)\n", stderr)
    exit(1)
}

do {
    let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: seedBytes)
    print(privateKey.publicKey.rawRepresentation.base64EncodedString())
} catch {
    fputs("Failed to create Curve25519 private key: \(error)\n", stderr)
    exit(1)
}
SWIFT
})"

if [ "${DERIVED_PUBLIC_KEY}" != "${SU_PUBLIC_ED_KEY}" ]; then
    echo "Error: Sparkle private/public key mismatch" >&2
    echo "Expected public key: ${SU_PUBLIC_ED_KEY}" >&2
    echo "Derived public key:  ${DERIVED_PUBLIC_KEY}" >&2
    exit 1
fi

echo "Sparkle keypair verified. Public key matches updater config."
