import SwiftUI
import AVFoundation

/// The "Review Markers" phase of the Deploy Video tab. Shows a big live preview of
/// the selected slide's marker frame, a scrubber to move it (exact-frame seek), and
/// a filmstrip of all slide thumbnails. The user drags / adds / removes markers; the
/// approved list becomes BOTH the viewer rest points and the forced encoder keyframes.
///
/// Pure list edits go through `MarkerEditorLogic` (offline-tested). Uses the AppKit
/// `AVPlayerView` wrapper (`VideoPreview`) — never SwiftUI's `AVKit.VideoPlayer`.
struct MarkerEditorView: View {
    let player: AVPlayer
    let videoURL: URL
    let duration: Double
    let onConfirm: ([Double]) -> Void
    let onBack: () -> Void

    @State private var markers: [Double]
    @State private var selected: Int = 0
    @State private var thumbs: [Int: NSImage] = [:]

    init(player: AVPlayer,
         videoURL: URL,
         duration: Double,
         initialMarkers: [Double],
         onConfirm: @escaping ([Double]) -> Void,
         onBack: @escaping () -> Void) {
        self.player = player
        self.videoURL = videoURL
        self.duration = duration
        self.onConfirm = onConfirm
        self.onBack = onBack
        _markers = State(initialValue: initialMarkers)
    }

    /// Scrubber value for the selected marker, clamped between neighbors on write +
    /// seeks the preview to the exact frame.
    private var selectedTime: Binding<Double> {
        Binding(
            get: { markers.indices.contains(selected) ? markers[selected] : 0 },
            set: { proposed in
                guard markers.indices.contains(selected) else { return }
                let t = MarkerEditorLogic.clamp(proposed, index: selected, markers: markers, duration: duration)
                markers[selected] = t
                seek(to: t)
                Task { await regenerateThumb(selected) }
            })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review Markers")
                .font(.title2.weight(.semibold))
            Text("Drag each slide's marker to its settled frame. Add or remove markers as needed — this is the final slide set.")
                .foregroundStyle(.secondary)

            VideoPreview(player: player)
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                Text("Slide \(selected + 1) of \(markers.count)")
                    .font(.callout.weight(.medium))
                Spacer()
                Text(String(format: "%.3fs", selectedTime.wrappedValue))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Slider(value: selectedTime, in: 0...max(duration, 0.001))

            HStack(spacing: 12) {
                Button {
                    addAtPlayhead()
                } label: { Label("Add", systemImage: "plus") }
                Button {
                    removeSelected()
                } label: { Label("Remove", systemImage: "minus") }
                    .disabled(markers.count <= 1)
                Spacer()
            }

            filmstrip

            HStack(spacing: 12) {
                Button("Back") { onBack() }
                Spacer()
                Button("Encode & Deploy") { onConfirm(markers) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!MarkerEditorLogic.isMonotonic(markers) || markers.isEmpty)
            }
        }
        .task { await generateThumbnails() }
        .onChange(of: selected) { _, _ in seek(to: selectedTime.wrappedValue) }
    }

    private var filmstrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(markers.indices, id: \.self) { i in
                    thumbCell(i)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(height: 64)
    }

    private func thumbCell(_ i: Int) -> some View {
        Group {
            if let img = thumbs[i] {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.secondary.opacity(0.15))
            }
        }
        .frame(width: 96, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(i == selected ? Color.accentColor : .clear, lineWidth: 2)
        }
        .onTapGesture { selected = i }
    }

    // MARK: - Actions

    private func seek(to t: Double) {
        let cm = CMTime(seconds: t, preferredTimescale: 600)
        player.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func addAtPlayhead() {
        // Use the midpoint between the selected marker and its next neighbor (or
        // duration). This is always strictly between neighbors → insert keeps the
        // array monotonic. The old code clamped `selectedTime` (= markers[selected]),
        // producing a duplicate timestamp and a non-monotonic array.
        let t = MarkerEditorLogic.insertionTime(after: selected, markers: markers, duration: duration)
        let (m, idx) = MarkerEditorLogic.insert(t, into: markers)
        markers = m
        selected = idx
        Task { await regenerateThumbsFrom(idx) }
    }

    private func removeSelected() {
        let (m, sel) = MarkerEditorLogic.remove(at: selected, from: markers)
        markers = m
        selected = sel
        // Prune stale thumb keys for the dropped top index so the dict doesn't
        // retain an image keyed at a now-out-of-range index.
        thumbs = thumbs.filter { $0.key < markers.count }
        Task { await regenerateThumbsFrom(sel) }
    }

    // MARK: - Thumbnails

    private func generateThumbnails() async {
        for i in markers.indices { await regenerateThumb(i) }
    }

    private func regenerateThumbsFrom(_ start: Int) async {
        for i in markers.indices where i >= start { await regenerateThumb(i) }
    }

    private func regenerateThumb(_ i: Int) async {
        guard markers.indices.contains(i) else { return }
        let asset = AVURLAsset(url: videoURL)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = .zero
        gen.maximumSize = CGSize(width: 192, height: 108)
        let time = CMTime(seconds: markers[i], preferredTimescale: 600)
        do {
            let cg = try await gen.image(at: time).image
            let img = NSImage(cgImage: cg, size: NSSize(width: 96, height: 54))
            await MainActor.run { thumbs[i] = img }
        } catch {
            // Best-effort: a missing thumb just shows the placeholder rectangle.
        }
    }
}
