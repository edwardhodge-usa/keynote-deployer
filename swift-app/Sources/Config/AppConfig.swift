import Foundation

/// App-wide configuration constants mirroring the Electron app's defaults.
enum AppConfig {
    static let defaultTeamId = "team_E1wAzl9zyAPrlGzyjmcXNuxd"
    static let defaultAllowedDomains = "*.imaginelabstudios.com *.framer.app"
    static let bundleIdentifier = "com.imaginelabstudios.keynote-deployer"

    /// Converts a title to a kebab-case Vercel project name
    static func toKebabCase(_ string: String) -> String {
        string
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s-]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: "-", options: .regularExpression)
            .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
