#!/usr/bin/env python3
"""Turns a capability on for a bundle ID in the Apple Developer account.

  asc_capability.py BUNDLE_ID CAPABILITY

The export (-allowProvisioningUpdates) registers new bundle IDs itself but does not
add capabilities to one already registered: cz.zaruky.app gets App Groups here
before its profile is made (the widget reads its data from the App Group).
A bundle ID not registered yet is left to the export. Standard library only;
needs ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH (the .p8 file).
"""
import base64, json, os, subprocess, sys, time, urllib.error, urllib.request

API = "https://api.appstoreconnect.apple.com/v1"


def b64(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_to_raw(der):
    # ECDSA-Sig-Value ::= SEQUENCE { r INTEGER, s INTEGER } -> r || s, 32 bytes each.
    i = 2 if der[1] < 0x80 else 2 + (der[1] & 0x7F)
    out = b""
    for _ in range(2):
        assert der[i] == 0x02
        n = der[i + 1]
        out += der[i + 2 : i + 2 + n].lstrip(b"\x00").rjust(32, b"\x00")
        i += 2 + n
    return out


def token():
    header = b64(json.dumps({"alg": "ES256", "kid": os.environ["ASC_KEY_ID"], "typ": "JWT"}).encode())
    now = int(time.time())
    claims = {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1080, "aud": "appstoreconnect-v1"}
    signing = f"{header}.{b64(json.dumps(claims).encode())}"
    der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", os.environ["ASC_KEY_PATH"]],
                         input=signing.encode(), check=True, capture_output=True).stdout
    return f"{signing}.{b64(der_to_raw(der))}"


def call(method, path, body=None, allow=()):
    req = urllib.request.Request(API + path, method=method,
                                 data=json.dumps(body).encode() if body else None,
                                 headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as res:
            return json.load(res) if res.status != 204 else {}
    except urllib.error.HTTPError as err:
        if err.code in allow:
            return {"status": err.code}
        sys.exit(f"{method} {path} -> {err.code}: {err.read().decode()[:500]}")


def main(bundle, capability):
    found = [b for b in call("GET", f"/bundleIds?filter[identifier]={bundle}&limit=200")["data"]
             if b["attributes"]["identifier"] == bundle]
    if not found:
        print(f"{bundle} is not registered yet; the export registers it.")
        return
    bundle_id = found[0]["id"]
    caps = call("GET", f"/bundleIds/{bundle_id}/bundleIdCapabilities")["data"]
    if any(c["attributes"]["capabilityType"] == capability for c in caps):
        print(f"{bundle} already has {capability}.")
        return
    call("POST", "/bundleIdCapabilities",
         {"data": {"type": "bundleIdCapabilities", "attributes": {"capabilityType": capability},
                   "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bundle_id}}}}},
         allow=(409,))
    print(f"{capability} turned on for {bundle}.")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
