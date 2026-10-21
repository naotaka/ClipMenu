#!/usr/bin/env swift
// Verify the published archive against the public key embedded in the app.
// This deliberately uses only public data, independently of the signing key.
import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("Release verification failed: \(message)\n".utf8))
    exit(1)
}

final class AppcastParser: NSObject, XMLParserDelegate {
    var enclosures: [[String: String]] = []
    var versions: [String] = []
    private var version: String?

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String]) {
        if elementName == "enclosure" { enclosures.append(attributeDict) }
        if elementName == "sparkle:version" { version = "" }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if version != nil { version! += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "sparkle:version", let value = version {
            versions.append(value.trimmingCharacters(in: .whitespacesAndNewlines))
            version = nil
        }
    }
}

guard CommandLine.arguments.count == 5 else {
    fail("usage: verify-release.swift Info.plist archive.dmg appcast.xml expected-download-URL")
}
do {
    let infoData = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
    guard let info = try PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any],
          info["SURequireSignedFeed"] as? Bool == true,
          info["SUVerifyUpdateBeforeExtraction"] as? Bool == true,
          let publicKeyBase64 = info["SUPublicEDKey"] as? String,
          let publicKeyData = Data(base64Encoded: publicKeyBase64),
          let buildNumber = info["CFBundleVersion"] as? String else {
        fail("missing signed-feed/pre-extraction verification policy, public key or build number in app")
    }
    let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
    let archive = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]), options: .mappedIfSafe)
    let feed = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]))
    let delegate = AppcastParser()
    let parser = XMLParser(data: feed)
    parser.shouldResolveExternalEntities = false
    parser.delegate = delegate
    guard parser.parse(), delegate.enclosures.count == 1, let enclosure = delegate.enclosures.first else {
        fail("expected one well-formed update enclosure")
    }
    guard enclosure["url"] == CommandLine.arguments[4],
          enclosure["length"].flatMap(Int.init) == archive.count,
          (enclosure["sparkle:version"] == buildNumber || delegate.versions == [buildNumber]),
          let signatureBase64 = enclosure["sparkle:edSignature"],
          let signature = Data(base64Encoded: signatureBase64),
          publicKey.isValidSignature(signature, for: archive) else {
        fail("URL, size, version, or EdDSA signature does not match the built app")
    }
    print("Release archive signature, URL, size, and build number verified.")
} catch {
    fail(error.localizedDescription)
}
