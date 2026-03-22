import Foundation

/// Settings persistence and folder validation — mirrors electron/fileOperations.ts
enum FileOperations {

    /// Application Support directory for settings
    static var dataDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("keynote-deployer")
    }

    private static var settingsPath: URL { dataDirectory.appendingPathComponent("settings.json") }

    // MARK: - Settings

    static func loadSettings() throws -> AppSettings {
        guard FileManager.default.fileExists(atPath: settingsPath.path) else {
            return .default
        }
        let data = try Data(contentsOf: settingsPath)
        let saved = try JSONDecoder().decode(AppSettings.self, from: data)
        return saved
    }

    static func saveSettings(_ settings: AppSettings) throws {
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(settings)
        try data.write(to: settingsPath)
    }

    // MARK: - Folder Validation

    struct FolderValidation: Sendable {
        let valid: Bool
        let folderPath: String
        let metadata: KeynoteMetadata?
        let error: String?
    }

    static func validateKeynoteFolder(_ folderPath: String) throws -> FolderValidation {
        let fm = FileManager.default
        let headerPath = (folderPath as NSString).appendingPathComponent("assets/header.json")
        let mainJsPath = (folderPath as NSString).appendingPathComponent("assets/player/main.js")

        guard fm.fileExists(atPath: headerPath) else {
            return FolderValidation(valid: false, folderPath: folderPath, metadata: nil, error: "Missing assets/header.json — not a Keynote HTML export")
        }

        guard fm.fileExists(atPath: mainJsPath) else {
            return FolderValidation(valid: false, folderPath: folderPath, metadata: nil, error: "Missing assets/player/main.js — not a Keynote HTML export")
        }

        let headerData = try Data(contentsOf: URL(fileURLWithPath: headerPath))
        let metadata = try JSONDecoder().decode(KeynoteMetadata.self, from: headerData)

        return FolderValidation(valid: true, folderPath: folderPath, metadata: metadata, error: nil)
    }

    // MARK: - Token Detection

    struct TokenDetection: Sendable {
        let found: Bool
        let token: String?
        let source: String?
    }

    static func detectVercelToken() -> TokenDetection {
        let home = NSHomeDirectory()
        let locations = [
            "\(home)/.local/share/com.vercel.cli/auth.json",
            "\(home)/Library/Application Support/com.vercel.cli/auth.json",
        ]

        for loc in locations {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: loc)),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = json["token"] as? String else { continue }
            return TokenDetection(found: true, token: token, source: loc)
        }

        return TokenDetection(found: false, token: nil, source: nil)
    }
}
