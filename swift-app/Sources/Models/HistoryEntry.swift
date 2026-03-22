import Foundation
import SwiftData

@Model
final class HistoryEntry {
    @Attribute(.unique) var id: String
    var projectName: String
    var title: String
    var slideCount: Int
    var url: String
    var folderPath: String
    var date: Date
    var fixesApplied: Int

    init(
        id: String = UUID().uuidString,
        projectName: String,
        title: String,
        slideCount: Int,
        url: String,
        folderPath: String,
        date: Date = .now,
        fixesApplied: Int
    ) {
        self.id = id
        self.projectName = projectName
        self.title = title
        self.slideCount = slideCount
        self.url = url
        self.folderPath = folderPath
        self.date = date
        self.fixesApplied = fixesApplied
    }
}

/// Codable DTO for JSON import/export (SwiftData @Model can't directly conform to Codable)
struct HistoryEntryDTO: Codable, Sendable {
    let id: String
    let projectName: String
    let title: String
    let slideCount: Int
    let url: String
    let folderPath: String
    let date: String
    let fixesApplied: Int

    func toModel() -> HistoryEntry {
        let isoDate = ISO8601DateFormatter().date(from: date) ?? .now
        return HistoryEntry(
            id: id,
            projectName: projectName,
            title: title,
            slideCount: slideCount,
            url: url,
            folderPath: folderPath,
            date: isoDate,
            fixesApplied: fixesApplied
        )
    }
}
