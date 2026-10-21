#!/usr/bin/env python3
"""Exercise release signature gates with disposable keys and synthetic archives."""
from pathlib import Path
import os
import subprocess
import tempfile
import plistlib

ROOT = Path(__file__).resolve().parent.parent
FIXTURE_SOURCE = r'''
import CryptoKit
import Foundation
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let key = Curve25519.Signing.PrivateKey()
let other = Curve25519.Signing.PrivateKey()
let archive = Data("synthetic update without user data".utf8)
try archive.write(to: root.appendingPathComponent("update.dmg"))
try Data("changed update".utf8).write(to: root.appendingPathComponent("tampered.dmg"))
for (name, publicKey) in [("Info.plist", key.publicKey), ("WrongKey.plist", other.publicKey)] {
    let info: [String: Any] = ["SUPublicEDKey": publicKey.rawRepresentation.base64EncodedString(), "CFBundleVersion": "42", "SURequireSignedFeed": true, "SUVerifyUpdateBeforeExtraction": true]
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: root.appendingPathComponent(name))
}
let signature = try key.signature(for: archive).base64EncodedString()
let xml = """
<?xml version="1.0"?><rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><sparkle:version>42</sparkle:version><enclosure url="https://example.com/update.dmg" sparkle:edSignature="\(signature)" length="\(archive.count)" /></item></channel></rss>
"""
try Data(xml.utf8).write(to: root.appendingPathComponent("appcast.xml"))
try Data(xml.replacingOccurrences(of: ">42<", with: ">43<").utf8).write(to: root.appendingPathComponent("wrong-version.xml"))
try Data(xml.replacingOccurrences(of: "length=\"\(archive.count)\"", with: "length=\"0\"").utf8).write(to: root.appendingPathComponent("wrong-length.xml"))
try Data(xml.replacingOccurrences(of: "sparkle:edSignature", with: "unused").utf8).write(to: root.appendingPathComponent("unsigned.xml"))
'''

with tempfile.TemporaryDirectory(prefix="clipm-release-security-") as directory:
    work = Path(directory)
    cache = str(work / "module-cache")
    verifier = work / "verify-release"
    fixture = work / "make-fixtures.swift"
    fixture.write_text(FIXTURE_SOURCE)
    subprocess.run(["xcrun", "swiftc", "-module-cache-path", cache,
                    str(ROOT / "scripts/verify-release.swift"), "-o", str(verifier)], check=True)
    subprocess.run(["xcrun", "swift", "-module-cache-path", cache, str(fixture), str(work)], check=True)

    def verify(label, info="Info.plist", archive="update.dmg", feed="appcast.xml",
               url="https://example.com/update.dmg", expected=1):
        result = subprocess.run([str(verifier), str(work / info), str(work / archive),
                                 str(work / feed), url], capture_output=True, text=True)
        if result.returncode != expected:
            raise AssertionError(f"{label}: {result.stdout}{result.stderr}")
        print(f"PASS: {label}")

    verify("valid signed update", expected=0)
    verify("reject wrong public key", info="WrongKey.plist")
    verify("reject modified archive", archive="tampered.dmg")
    verify("reject wrong build number", feed="wrong-version.xml")
    verify("reject wrong archive length", feed="wrong-length.xml")
    verify("reject unsigned update", feed="unsigned.xml")
    verify("reject unexpected download URL", url="https://example.com/other.dmg")
    for key in ["SURequireSignedFeed", "SUVerifyUpdateBeforeExtraction"]:
        info = plistlib.loads((work / "Info.plist").read_bytes())
        del info[key]
        (work / "MissingPolicy.plist").write_bytes(plistlib.dumps(info))
        verify(f"reject missing {key}", info="MissingPolicy.plist")

# This invalid combination must fail before building or touching credentials.
result = subprocess.run(["bash", str(ROOT / "scripts/release-dmg.sh"),
                         "--skip-notarize", "--publish"], capture_output=True, text=True,
                        env={"PATH": os.environ["PATH"]})
if result.returncode != 1 or "cannot be combined" not in result.stderr:
    raise AssertionError("Unnotarized publishing guard failed")
print("PASS: reject unnotarized publishing")
