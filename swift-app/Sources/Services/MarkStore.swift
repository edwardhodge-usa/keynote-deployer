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

    private static func storeURL() -> URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let appDir = dir.appendingPathComponent("keynote-deployer", isDirectory: true)
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
}
