import Foundation

struct AppSettings: Codable, Sendable {
    var vercelToken: String
    var vercelTeamId: String
    var theme: ThemeMode
    var autoCopyUrl: Bool
    var enableRuntimeVerification: Bool
    var projectNamePrefix: String
    var lastFolderPath: String
    var secureEmbed: Bool
    var embedAllowedDomains: String

    static let `default` = AppSettings(
        vercelToken: "",
        vercelTeamId: "team_E1wAzl9zyAPrlGzyjmcXNuxd",
        theme: .system,
        autoCopyUrl: true,
        enableRuntimeVerification: false,
        projectNamePrefix: "",
        lastFolderPath: "",
        secureEmbed: true,
        embedAllowedDomains: "*.imaginelabstudios.com *.framer.app"
    )
}

enum ThemeMode: String, Codable, Sendable {
    case light, dark, system
}
