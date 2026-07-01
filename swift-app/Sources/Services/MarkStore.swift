import Foundation

/// Persists edited per-slide hold-span marks so re-deploying the SAME deck reloads
/// the user's timeline edits instead of starting from the auto-detected seed.
///
/// Keyed by a deck **fingerprint** (frame count + fps + byte size). A re-exported
/// deck changes at least one of those, so stale marks for a different export are
/// never applied (their frame indices wouldn't map). Stored as one JSON file in the
/// app's Application Support dir.
enum MarkStore {
    private static let fileName = "timeline-marks.json"

    /// The seed-algorithm version. **Bump this whenever the seed algorithm changes**
    /// so a deck previously hand-tuned under an OLD algorithm auto-reseeds with the
    /// new (better) seed instead of silently loading stale marks. The old edits stay
    /// on disk under their old key (preserved, just not shown). v1 = the original
    /// fixed-threshold seed; v2 = the adaptive seed (sections 03–07).
    static let algorithmVersion = 2

    /// Identifies a specific deck export AT a specific algorithm version. Same bytes +
    /// same decoded geometry + same algorithm → match. A different `algorithmVersion`
    /// yields a different key, so a new algorithm always re-seeds (it never matches the
    /// marks an older algorithm saved). This is the fix for MarkStore shadowing — the
    /// prime suspect behind the "wrong count / less accurate since our changes" report.
    static func fingerprint(path: String, frameCount: Int, fps: Double, algorithmVersion: Int) -> String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let size = (attrs?[.size] as? Int) ?? 0
        let fpsKey = Int((fps * 1000).rounded())
        return "v\(algorithmVersion)-\(frameCount)-\(fpsKey)-\(size)"
    }

    /// Test seam: when set, the mark store lives HERE instead of Application Support.
    /// `nil` in production. Lets tests isolate to a unique temp dir so they never
    /// collide with real app data or each other, and never race on the shared file
    /// (the cold-start `sameVersionRoundTrip` flake). `namedURL()` derives from
    /// `storeURL()`, so it follows the override automatically. `nonisolated(unsafe)`
    /// is safe here: it's nil in production (never mutated), and the only writer — the
    /// `.serialized` test suite — is single-threaded by that trait.
    nonisolated(unsafe) static var storeDirectoryOverride: URL?

    private static func storeURL() -> URL? {
        let appDir: URL
        if let override = storeDirectoryOverride {
            appDir = override
        } else {
            guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
            appDir = dir.appendingPathComponent("keynote-deployer", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent(fileName)
    }

    private static func loadAll() -> [String: [SlideMark]] {
        guard let url = storeURL(), let data = try? Data(contentsOf: url),
              let map = try? JSONDecoder().decode([String: [SlideMark]].self, from: data) else { return [:] }
        return map
    }

    /// Saved marks for a fingerprint, or nil. Best-effort — never throws.
    static func load(_ fingerprint: String) -> [SlideMark]? {
        loadAll()[fingerprint]
    }

    /// Save marks for a fingerprint. Best-effort — a failure is silently ignored
    /// (persistence is a convenience, never blocks a deploy).
    static func save(_ marks: [SlideMark], for fingerprint: String) {
        guard let url = storeURL() else { return }
        var map = loadAll()
        map[fingerprint] = marks
        if let data = try? JSONEncoder().encode(map) {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - Named reuse (survives a re-export)

    /// A saved timeline keyed by DECK IDENTITY (not the exact file). Carries fps +
    /// frameCount so the marks (frame indices) can be re-mapped by TIME onto a
    /// re-exported deck of a different length/framerate.
    struct NamedMarks: Codable, Sendable, Equatable {
        let marks: [SlideMark]
        let fps: Double
        let frameCount: Int
        let savedAt: Double
    }

    private static let namedFileName = "timeline-marks-by-name.json"

    /// Normalize a deck's project name to a stable IDENTITY that survives re-exports:
    /// drop a trailing EXPLICIT version token (`-v3`, `-v16`) only — years and other
    /// numbers are kept so different decks stay distinct. So `ilsquals-2026-v3` and
    /// `ilsquals-2026-v4` share identity `ilsquals-2026`, while `nash-quals-2026` is
    /// left untouched.
    static func deckIdentity(_ projectName: String) -> String {
        var s = projectName.lowercased()
        while let r = s.range(of: "-v\\d+$", options: .regularExpression) { s.removeSubrange(r) }
        let trimmed = s.trimmingCharacters(in: CharacterSet(charactersIn: "-_ "))
        return trimmed.isEmpty ? projectName.lowercased() : trimmed
    }

    private static func namedURL() -> URL? { storeURL()?.deletingLastPathComponent().appendingPathComponent(namedFileName) }

    private static func loadAllNamed() -> [String: NamedMarks] {
        guard let url = namedURL(), let data = try? Data(contentsOf: url),
              let map = try? JSONDecoder().decode([String: NamedMarks].self, from: data) else { return [:] }
        return map
    }

    /// Most-recent saved timeline for a deck identity, or nil.
    static func loadNamed(_ identity: String) -> NamedMarks? { loadAllNamed()[identity] }

    /// Save the edited timeline under a deck identity (in addition to the exact
    /// fingerprint save), so a future re-export of the same deck can reuse it.
    static func saveNamed(_ marks: [SlideMark], identity: String, fps: Double, frameCount: Int, savedAt: Double) {
        guard let url = namedURL() else { return }
        var map = loadAllNamed()
        map[identity] = NamedMarks(marks: marks, fps: fps, frameCount: frameCount, savedAt: savedAt)
        if let data = try? JSONEncoder().encode(map) { try? data.write(to: url, options: .atomic) }
    }

    /// Re-map saved marks (old frame indices) onto a new deck by TIME: frame→seconds
    /// via the saved fps, seconds→frame via the new fps, clamped into the new range and
    /// normalized to a strictly-increasing, valid `[SlideMark]` (drops any that can't
    /// fit without overlapping — so the result always satisfies SlideMarkLogic.isValid
    /// for a non-empty input with toFrameCount ≥ marks.count). Pure.
    static func remap(_ named: NamedMarks, toFps: Double, toFrameCount: Int) -> [SlideMark] {
        guard toFps > 0, named.fps > 0, toFrameCount > 0, !named.marks.isEmpty else { return [] }
        let hi = toFrameCount - 1
        func conv(_ f: Int) -> Int { Swift.max(0, Swift.min(Int(((Double(f) / named.fps) * toFps).rounded()), hi)) }
        var out: [SlideMark] = []
        var prevEnd = -1
        for m in named.marks {
            var hs = Swift.max(conv(m.holdStart), prevEnd + 1)
            if hs > hi { break }                          // no room left → stop (over-packed)
            let he = Swift.max(hs, Swift.min(conv(m.holdEnd), hi))
            hs = Swift.min(hs, he)
            out.append(SlideMark(holdStart: hs, holdEnd: he))
            prevEnd = he
        }
        return out
    }
}
