#!/usr/bin/env python3
"""Redact secrets from a matter-server commissioning log while keeping every line.

Produces a COMPLETE (not excerpted) log suitable for attaching to a public
GitHub issue: only sensitive tokens (Wi-Fi credentials, IPKs, passcode, BLE MACs,
attestation challenge) are masked; all lines/flow are preserved.
"""
import sys

# exact-string -> placeholder (order matters: longer/hex first is fine here)
REPLACEMENTS = {
    # Wi-Fi credentials (plaintext + hex encodings seen in the log)
    "4855415745492d4855425633": "<WIFI_SSID_HEX>",
    "53687573686930373035": "<WIFI_PASSWORD_HEX>",
    "HUAWEI-HUBV3": "<WIFI_SSID>",
    "Shushi0705": "<WIFI_PASSWORD>",
    # Identity Protection Keys (fabric secrets)
    "d28a56b22947cee0161353bf91869797": "<IPK_REDACTED>",
    "f212f6c648a654ee128f83175bd6d41c": "<OP_IPK_REDACTED>",
    # Setup passcode
    "38866535": "<PASSCODE_REDACTED>",
    # BLE peripheral MAC addresses
    "D2:1F:41:BC:D8:AC": "AA:AA:AA:AA:AA:AA",
    "C5:F1:F7:7D:F8:12": "BB:BB:BB:BB:BB:BB",
    # Attestation challenge (ephemeral session secret)
    "31b62683fabf643d68b47bc848d8023c": "<ATTEST_CHALLENGE_REDACTED>",
}


def main(src, dst):
    with open(src, "r", errors="replace") as f:
        data = f.read()
    for secret, placeholder in REPLACEMENTS.items():
        data = data.replace(secret, placeholder)
    with open(dst, "w") as f:
        f.write(data)
    # verify nothing sensitive leaked
    leaked = [s for s in REPLACEMENTS if s in data]
    print(f"Wrote {dst}")
    if leaked:
        print("WARNING: still present:", leaked)
    else:
        print("OK: all listed secrets redacted")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
