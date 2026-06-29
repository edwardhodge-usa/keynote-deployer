import SwiftUI
import AVFoundation

/// Frame-accurate "Review Markers" timeline. Each slide is a hold span on a
/// continuous frame timeline; transitions are the gaps. Select a boundary handle →
/// the preview shows that exact frame; ±1-frame buttons / ←→ keys nudge it and the
/// preview re-renders instantly (zero-tolerance seek). Pure edits go through
/// `SlideMarkLogic`. Uses the AppKit `VideoPreview` (never SwiftUI VideoPlayer).
struct TimelineEditorView: View {
    let player: AVPlayer
    let frameCount: Int
    let fps: Double
    let onConfirm: ([SlideMark]) -> Void
    let onBack: () -> Void

    @State private var marks: [SlideMark]
    @State private var selected: MarkerRef = MarkerRef(slide: 0, edge: .start)
    @FocusState private var focused: Bool

    init(player: AVPlayer, frameCount: Int, fps: Double, initialMarks: [SlideMark],
         onConfirm: @escaping ([SlideMark]) -> Void, onBack: @escaping () -> Void) {
        self.player = player; self.frameCount = frameCount; self.fps = fps
        self.onConfirm = onConfirm; self.onBack = onBack
        _marks = State(initialValue: initialMarks)
    }

    private var selectedFrame: Int {
        guard marks.indices.contains(selected.slide) else { return 0 }
        return selected.edge == .start ? marks[selected.slide].holdStart : marks[selected.slide].holdEnd
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Review Markers").font(.title2.weight(.semibold))
            Text("Select a marker, step it frame-by-frame, and watch the frame. Holds are solid; transitions are the gaps.")
                .foregroundStyle(.secondary)

            VideoPreview(player: player).frame(height: 240).clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                Text("Slide \(selected.slide + 1)/\(marks.count) · \(selected.edge == .start ? "hold start" : "hold end")")
                    .font(.callout.weight(.medium))
                Spacer()
                Text("frame \(selectedFrame) · \(String(format: "%.3fs", Double(selectedFrame)/fps))")
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button { step(-1) } label: { Label("−1 frame", systemImage: "backward.frame") }
                Button { step(1) } label: { Label("+1 frame", systemImage: "forward.frame") }
                Spacer()
                Button { marks = SlideMarkLogic.split(at: selectedFrame, marks: marks) } label: { Label("Split", systemImage: "scissors") }
                Button { marks = SlideMarkLogic.merge(slide: selected.slide, marks: marks); clampSelection() } label: { Label("Merge", systemImage: "arrow.triangle.merge") }
                    .disabled(marks.count <= 1 || selected.slide >= marks.count - 1)
            }

            timeline

            HStack {
                Button("Back") { onBack() }
                Spacer()
                Button("Encode & Deploy") { onConfirm(marks) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!SlideMarkLogic.isValid(marks, frameCount: frameCount))
            }
        }
        .focusable()
        .focused($focused)
        .onAppear { focused = true; seek(selectedFrame) }
        .onKeyPress(.leftArrow) { step(-1); return .handled }
        .onKeyPress(.rightArrow) { step(1); return .handled }
        .onChange(of: selected) { _, _ in seek(selectedFrame) }
    }

    private var timeline: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let px = { (f: Int) in CGFloat(f) / CGFloat(max(frameCount - 1, 1)) * w }
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(.secondary.opacity(0.12)).frame(height: 26)
                ForEach(marks.indices, id: \.self) { i in
                    let x0 = px(marks[i].holdStart), x1 = px(marks[i].holdEnd)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.accentColor.opacity(0.35))
                        .frame(width: max(2, x1 - x0), height: 26)
                        .offset(x: x0)
                    handle(MarkerRef(slide: i, edge: .start), x: x0)
                    handle(MarkerRef(slide: i, edge: .end), x: x1)
                }
            }
        }
        .frame(height: 34)
    }

    private func handle(_ ref: MarkerRef, x: CGFloat) -> some View {
        Rectangle()
            .fill(ref == selected ? Color.white : Color.accentColor)
            .frame(width: ref == selected ? 3 : 2, height: 32)
            .offset(x: x - 1)
            .contentShape(Rectangle().inset(by: -6))
            .onTapGesture { selected = ref }
    }

    private func step(_ delta: Int) {
        guard marks.indices.contains(selected.slide) else { return }
        let proposed = selectedFrame + delta
        let clamped = SlideMarkLogic.clamp(proposed, ref: selected, marks: marks, frameCount: frameCount)
        if selected.edge == .start { marks[selected.slide].holdStart = clamped }
        else { marks[selected.slide].holdEnd = clamped }
        seek(clamped)
    }

    private func clampSelection() {
        if selected.slide >= marks.count { selected = MarkerRef(slide: max(0, marks.count - 1), edge: .start) }
    }

    private func seek(_ frame: Int) {
        player.seek(to: CMTime(seconds: Double(frame) / fps, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
    }
}
