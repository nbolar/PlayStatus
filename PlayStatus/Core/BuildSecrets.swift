import Foundation

/// Credentials baked in at build time.
///
/// They live in `PlayStatus/Secrets.plist`, which is gitignored and bundled as a resource:
/// filled in by hand locally, and written by the release workflow from repository secrets.
/// `config/Secrets.example.plist` is the committed template.
///
/// A plist resource rather than an xcconfig feeding `Info.plist`, because the project uses a
/// file-system-synchronized group — a file dropped under `PlayStatus/` is picked up with no
/// `project.pbxproj` edit at all, where wiring a `baseConfigurationReference` by hand means
/// editing the project file.
///
/// A clone without the file still builds and runs. Everything that needs a key checks
/// `isLastFMConfigured` first and degrades to an explanatory disabled state rather than
/// failing at runtime.
///
/// These are not secrets in the cryptographic sense: anything shipped in an app bundle can be
/// extracted from it. Last.fm's desktop clients all work this way, and the key identifies the
/// application, not the user. The per-user session key is the sensitive value, and that lives
/// in the Keychain.
enum BuildSecrets {
    static let lastFMAPIKey: String = infoValue("LastFMAPIKey")
    static let lastFMSharedSecret: String = infoValue("LastFMSharedSecret")

    static var isLastFMConfigured: Bool {
        !lastFMAPIKey.isEmpty && !lastFMSharedSecret.isEmpty
    }

    /// Read once. A missing file is the normal state of a fresh clone, not an error.
    private static let secrets: [String: String] = {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dictionary = plist as? [String: String] else {
            return [:]
        }
        return dictionary
    }()

    private static func infoValue(_ key: String) -> String {
        // Info.plist is the fallback so a build that instead injects these through an xcconfig
        // keeps working without touching this file.
        let raw = secrets[key] ?? (Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "")
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // An unresolved build setting comes through literally as "$(LASTFM_API_KEY)", which
        // would otherwise be sent to Last.fm as if it were a real key.
        if trimmed.hasPrefix("$(") || trimmed.hasPrefix("${") { return "" }
        return trimmed
    }
}
