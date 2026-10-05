import Foundation

/// The app was first built as `sh.ratel.transkribe`; settings and secrets move to the new identifier.
public enum IdentifierMigration {
    public static let bundleIdentifier = "kayrauckilinc.dev.transkribe"
    public static let legacyBundleIdentifier = "sh.ratel.transkribe"

    /// Copies the old app's preferences (not AppKit's own window state) when the new domain
    /// has none yet. Returns whether anything was copied.
    @discardableResult
    public static func migrateDefaults(from legacy: String = legacyBundleIdentifier,
                                       into defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: "transcriptionSettings") == nil,
              defaults.object(forKey: "recordingSource") == nil,
              let old = UserDefaults.standard.persistentDomain(forName: legacy), !old.isEmpty else { return false }
        for (key, value) in old where !key.hasPrefix("NS") && !key.hasPrefix("Apple") {
            defaults.set(value, forKey: key)
        }
        return true
    }
}
