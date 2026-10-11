import Foundation

public enum ProvisionedCapabilities {
    /// UI availability hint from the profile embedded in the already installed
    /// bundle. iOS still verifies signatures and enforces the actual entitlement;
    /// this parser never grants access or treats a profile as user read consent.
    public static func healthKit(in profile: Data) -> Bool {
        guard profile.count <= 2 * 1024 * 1024,
              let start = profile.range(of: Data("<plist".utf8)),
              let end = profile.range(of: Data("</plist>".utf8), in: start.lowerBound..<profile.endIndex) else { return false }
        let xml = profile.subdata(in: start.lowerBound..<end.upperBound)
        guard let root = try? PropertyListSerialization.propertyList(from: xml, format: nil) as? [String: Any],
              let entitlements = root["Entitlements"] as? [String: Any],
              let enabled = entitlements["com.apple.developer.healthkit"] as? Bool else { return false }
        return enabled
    }
}
