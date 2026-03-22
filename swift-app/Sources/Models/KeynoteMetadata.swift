import Foundation

struct KeynoteMetadata: Codable, Sendable {
    let title: String
    let slideCount: Int
    let width: Int
    let height: Int

    init(title: String, slideCount: Int, width: Int = 1920, height: Int = 1080) {
        self.title = title
        self.slideCount = slideCount
        self.width = width
        self.height = height
    }

    /// Parse from Keynote export header.json which uses varying key names
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // title can appear as "title" or "name"
        if let t = try container.decodeIfPresent(String.self, forKey: .title) {
            title = t
        } else if let n = try container.decodeIfPresent(String.self, forKey: .name) {
            title = n
        } else {
            title = "Untitled"
        }

        // slideCount can appear as "slideCount" or derived from "slides" array
        if let sc = try container.decodeIfPresent(Int.self, forKey: .slideCount) {
            slideCount = sc
        } else if let slides = try container.decodeIfPresent([AnyCodable].self, forKey: .slides) {
            slideCount = slides.count
        } else {
            slideCount = 0
        }

        width = try container.decodeIfPresent(Int.self, forKey: .width) ?? 1920
        height = try container.decodeIfPresent(Int.self, forKey: .height) ?? 1080
    }

    private enum CodingKeys: String, CodingKey {
        case title, name, slideCount, slides, width, height
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(slideCount, forKey: .slideCount)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
    }
}

/// Minimal wrapper so we can decode heterogeneous JSON arrays from header.json
struct AnyCodable: Codable, Sendable {
    init(from decoder: Decoder) throws {
        // We only need to count array elements, not decode values
        _ = try decoder.singleValueContainer()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encodeNil()
    }
}
