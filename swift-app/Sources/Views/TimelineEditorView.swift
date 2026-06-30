import SwiftUI
import AVFoundation
import AppKit

/// Frame-accurate "Review Markers" timeline (layout A). Each slide is a hold span on
/// a continuous, zoomable frame timeline; transitions are the gaps between holds.
///
/// Interactions (mirrors the approved HTML mockup):
/// - Drag the white **playhead** (or click the track) to scrub — the preview follows.
/// - **Split** cuts the hold under the playhead into two slides (button or right-click).
/// - **Merge**: click a hold zone, Shift-click the adjacent one (both highlight), then
///   Merge (button or right-click).
/// - Drag the cyan **Rest** / green **Go** ticks to retime; or select one and use −1/+1
///   (also ← → keys).
/// - **First** jumps the playhead to frame 0. **Play to next** sweeps the playhead
///   through the transition so you see what plays vs freezes.
///
/// All edits go through `SlideMarkLogic`. Uses the AppKit `VideoPreview` (never the
/// SwiftUI `VideoPlayer`, which SIGABRTs on macOS 26).
struct TimelineEditorView: View {
    let player: AVPlayer
    let frameCount: Int
    let fps: Double
    let onConfirm: ([SlideMark]) -> Void
    let onBack: () -> Void

    @State private var marks: [SlideMark]
    @State private var sel: MarkerRef = MarkerRef(slide: 0, edge: .start)
    @State private var playhead: Int = 0
    @State private var selectedSections: Set<Section> = []   // holds + transitions; multi-select
    @State private var zoom: Double = 3
    @State private var play: PlayState = .frozen
    @State private var timeObserver: Any?
    @State private var undoStack: [[SlideMark]] = []   // snapshots before each edit
    @State private var editingDrag = false             // groups a tick-drag into one undo
    @State private var lengthTargets: [Section] = []    // sections the length sheet edits
    @State private var lengthText = ""
    @State private var showLength = false
    @FocusState private var focused: Bool

    private enum PlayState { case frozen, playing, scrub }

    /// A clickable timeline region: a hold (purple) or the transition after a slide
    /// (green). `transition(i)` is the gap between slide i and i+1.
    private enum Section: Hashable { case hold(Int); case transition(Int) }

    // Mockup palette
    private static let cFreeze = Color(red: 0.369, green: 0.361, blue: 0.902) // 5e5ce6
    private static let cPlay   = Color(red: 0.188, green: 0.820, blue: 0.345) // 30d158
    private static let cRest   = Color(red: 0.392, green: 0.824, blue: 1.0)   // 64d2ff
    private static let TLH: CGFloat = 92

    init(player: AVPlayer, frameCount: Int, fps: Double, initialMarks: [SlideMark],
         onConfirm: @escaping ([SlideMark]) -> Void, onBack: @escaping () -> Void) {
        self.player = player; self.frameCount = frameCount; self.fps = fps
        self.onConfirm = onConfirm; self.onBack = onBack
        _marks = State(initialValue: initialMarks)
        _playhead = State(initialValue: initialMarks.first?.holdStart ?? 0)
    }

    private var total: Int { max(frameCount, 1) }
    private var tickFrame: Int {
        guard marks.indices.contains(sel.slide) else { return 0 }
        return sel.edge == .start ? marks[sel.slide].holdStart : marks[sel.slide].holdEnd
    }
    private var canSplit: Bool { holdContaining(playhead) >= 0 }
    /// Merge needs exactly two ADJACENT holds selected.
    private var mergeHolds: (Int, Int)? {
        guard selectedSections.count == 2 else { return nil }
        let holds = selectedSections.compactMap { s -> Int? in if case .hold(let i) = s { return i } else { return nil } }.sorted()
        guard holds.count == 2, holds[1] - holds[0] == 1 else { return nil }
        return (holds[0], holds[1])
    }
    private var canMerge: Bool { mergeHolds != nil }

    var body: some View {
        // ScrollView keeps the window from being forced past the screen (its min
        // height is ~0); the footer is pinned below so it's always reachable.
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Review Markers").font(.title2.weight(.semibold))
                    Text("Drag the playhead to scrub. Click a hold (purple) or transition (green) to select; Shift-click to add more. Right-click → Set length… to type an exact frame count for one or all selected. Split cuts the hold under the playhead; two adjacent holds → Merge. Drag the cyan Rest / green Go ticks, or select one and use −1/+1.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

                    preview

                    controls

                    HStack(spacing: 12) {
                        Text("Zoom").font(.caption).foregroundStyle(.secondary)
                        Slider(value: $zoom, in: 1...16).frame(width: 220)
                        Text("\(zoom, specifier: "%.1f")×").font(.caption.monospaced()).foregroundStyle(.secondary)
                        Text(selInfo).font(.caption.monospaced()).foregroundStyle(.tertiary)
                        Spacer()
                    }

                    GeometryReader { geo in timeline(geo.size.width) }
                        .frame(height: Self.TLH + 14)
                }
                .padding(24)
            }

            Divider()

            HStack {
                Button("Back") { stopPlay(); onBack() }
                Spacer()
                Button("Encode & Deploy") { stopPlay(); onConfirm(marks) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!SlideMarkLogic.isValid(marks, frameCount: frameCount))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .focusable()
        .focused($focused)
        .onAppear { focused = true; seek(playhead) }
        .onKeyPress(.leftArrow) { step(-1); return .handled }
        .onKeyPress(.rightArrow) { step(1); return .handled }
        .onChange(of: sel) { _, _ in if play != .playing { seek(tickFrame) } }
        .sheet(isPresented: $showLength) { lengthSheet }
    }

    private var lengthSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(lengthTargets.count > 1 ? "Set length for \(lengthTargets.count) sections" : "Set length")
                .font(.headline)
            Text(lengthTargets.count > 1
                 ? "Each selected hold/transition is set to this many frames."
                 : sectionDescription(lengthTargets.first))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                TextField("frames", text: $lengthText)
                    .textFieldStyle(.roundedBorder).frame(width: 110)
                    .onSubmit { applyLength() }
                Text("frames").foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { showLength = false }
                Button("Apply") { applyLength() }
                    .buttonStyle(.borderedProminent)
                    .disabled(Int(lengthText) == nil)
            }
        }
        .padding(20).frame(width: 320)
    }

    private func sectionDescription(_ s: Section?) -> String {
        guard let s else { return "" }
        switch s {
        case .hold(let i): return "Hold of slide \(i + 1) (Rest → Go), in frames."
        case .transition(let i): return "Transition from slide \(i + 1) to \(i + 2), in frames."
        }
    }

    // MARK: - Preview

    private var preview: some View {
        ZStack(alignment: .topLeading) {
            VideoPreview(player: player)
                .aspectRatio(16.0/9.0, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: 300)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            HStack {
                Text("Slide \(currentSlide + 1) / \(marks.count)")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
                Spacer()
                Text(stateLabel)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(stateBG, in: RoundedRectangle(cornerRadius: 6))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .overlay(alignment: .bottomLeading) {
            Text("frame \(displayFrame) · \(String(format: "%.3fs", Double(displayFrame)/max(fps,1)))")
                .font(.caption.monospaced())
                .foregroundStyle(Self.cRest)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
                .padding(12)
        }
    }

    private var displayFrame: Int { play == .frozen ? tickFrame : playhead }
    private var currentSlide: Int { play == .frozen ? sel.slide : slideAt(playhead) }
    private var stateLabel: String { switch play { case .frozen: return "❚❚ FROZEN"; case .playing: return "▶ PLAYING"; case .scrub: return "⌖ SCRUB" } }
    private var stateBG: Color {
        switch play {
        case .frozen: return Self.cFreeze.opacity(0.3)
        case .playing: return Self.cPlay.opacity(0.3)
        case .scrub: return Color.white.opacity(0.25)
        }
    }
    private var selInfo: String {
        guard !selectedSections.isEmpty else { return "" }
        if canMerge { return "2 adjacent holds selected — mergeable" }
        return "\(selectedSections.count) selected — right-click → Set length…"
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 10) {
            Button { goFirst() } label: { Label("First", systemImage: "backward.end.fill") }
            Button { playToNext() } label: { Label("Play to next", systemImage: "play.fill") }
                .disabled(play == .playing || slideAt(playhead) >= marks.count - 1)

            Picker("", selection: $sel.edge) {
                Text("❚❚ Rest").tag(MarkerEdge.start)
                Text("▶ Go").tag(MarkerEdge.end)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 150)

            Button { step(-1) } label: { Image(systemName: "minus") }
            Button { step(1) } label: { Image(systemName: "plus") }

            Button { doSplit() } label: { Label("Split", systemImage: "scissors") }
                .disabled(!canSplit)
            Button { doMerge() } label: { Label("Merge", systemImage: "arrow.triangle.merge") }
                .disabled(!canMerge)
            Button { undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                .disabled(undoStack.isEmpty)
                .keyboardShortcut("z", modifiers: .command)

            Spacer()
            Text("\(sel.edge == .start ? "Rest" : "Go") · frame \(tickFrame) · playhead \(playhead)f")
                .font(.caption.monospaced()).foregroundStyle(.secondary)
        }
    }

    // MARK: - Timeline

    private func timeline(_ viewport: CGFloat) -> some View {
        let contentW = max(viewport, viewport * CGFloat(zoom))
        return ScrollView(.horizontal, showsIndicators: true) {
            ZStack(alignment: .topLeading) {
                // background (scrub target: click/drag moves the playhead)
                RoundedRectangle(cornerRadius: 8).fill(.secondary.opacity(0.12))
                    .frame(width: contentW, height: Self.TLH)

                ForEach(marks.indices, id: \.self) { i in
                    holdSegments(i, contentW)
                }
                ForEach(marks.indices, id: \.self) { i in
                    tickView(i, .start, contentW)
                    tickView(i, .end, contentW)
                }
                playheadView(contentW)
            }
            .frame(width: contentW, height: Self.TLH, alignment: .topLeading)
            .coordinateSpace(name: "tl")
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("tl"))
                    .onChanged { v in scrubTo(frameAt(v.location.x, contentW)) }
                    .onEnded { _ in if play == .scrub { play = .frozen } }
            )
            .contextMenu {
                Button("Split at playhead (\(playhead)f)") { doSplit() }.disabled(!canSplit)
                Button("Merge selected zones") { doMerge() }.disabled(!canMerge)
            }
        }
        .frame(height: Self.TLH + 12)
    }

    @ViewBuilder
    private func holdSegments(_ i: Int, _ contentW: CGFloat) -> some View {
        let m = marks[i]
        let x0 = px(m.holdStart, contentW), x1 = px(m.holdEnd, contentW)
        let holdSel = selectedSections.contains(.hold(i))
        // hold (frozen, purple) block — click to select; right-click to set length
        RoundedRectangle(cornerRadius: 4)
            .fill(Self.cFreeze.opacity(holdSel ? 0.75 : 0.32))
            .frame(width: max(3, x1 - x0), height: 38)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Self.cRest, lineWidth: holdSel ? 2 : 0))
            .offset(x: x0, y: 26)
            .onTapGesture { selectSection(.hold(i), shift: NSEvent.modifierFlags.contains(.shift)) }
            .contextMenu { sectionMenu(.hold(i)) }
        // transition (plays, green) band into next slide — also selectable
        if i < marks.count - 1 {
            let xn = px(marks[i + 1].holdStart, contentW)
            let transSel = selectedSections.contains(.transition(i))
            RoundedRectangle(cornerRadius: 3)
                .fill(Self.cPlay.opacity(transSel ? 0.85 : 0.5))
                .frame(width: max(2, xn - x1), height: 38)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white, lineWidth: transSel ? 2 : 0))
                .offset(x: x1, y: 26)
                .onTapGesture { selectSection(.transition(i), shift: NSEvent.modifierFlags.contains(.shift)) }
                .contextMenu { sectionMenu(.transition(i)) }
        }
    }

    @ViewBuilder
    private func sectionMenu(_ s: Section) -> some View {
        Button("Set length…") { beginLengthEdit([s]) }
        if selectedSections.count > 1 && selectedSections.contains(s) {
            Button("Set length for \(selectedSections.count) selected…") { beginLengthEdit(Array(selectedSections)) }
        }
        Divider()
        Button("Split at playhead") { doSplit() }.disabled(!canSplit)
        Button("Merge selected holds") { doMerge() }.disabled(!canMerge)
    }

    private func tickView(_ i: Int, _ edge: MarkerEdge, _ contentW: CGFloat) -> some View {
        let ref = MarkerRef(slide: i, edge: edge)
        let f = edge == .start ? marks[i].holdStart : marks[i].holdEnd
        let isSel = (sel == ref)
        let color = edge == .start ? Self.cRest : Self.cPlay
        return RoundedRectangle(cornerRadius: 2)
            .fill(color)
            .frame(width: isSel ? 7 : 5, height: 62)
            .overlay(isSel ? RoundedRectangle(cornerRadius: 2).stroke(color.opacity(0.5), lineWidth: 3) : nil)
            .contentShape(Rectangle().inset(by: -6))
            .offset(x: px(f, contentW) - (isSel ? 3.5 : 2.5), y: 14)
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("tl"))
                    .onChanged { v in
                        if !editingDrag { pushUndo(); editingDrag = true }   // one undo per drag
                        sel = ref
                        let clamped = SlideMarkLogic.clamp(frameAt(v.location.x, contentW), ref: ref, marks: marks, frameCount: frameCount)
                        if edge == .start { marks[i].holdStart = clamped } else { marks[i].holdEnd = clamped }
                        play = .frozen; seek(clamped)
                    }
                    .onEnded { _ in editingDrag = false }
            )
    }

    private func playheadView(_ contentW: CGFloat) -> some View {
        Rectangle()
            .fill(Color.white)
            .frame(width: 2, height: Self.TLH)
            .shadow(color: .white.opacity(0.8), radius: 3)
            .overlay(alignment: .top) {
                Image(systemName: "arrowtriangle.down.fill").font(.system(size: 11)).foregroundStyle(.white).offset(y: -2)
            }
            .contentShape(Rectangle().inset(by: -7))
            .offset(x: px(playhead, contentW) - 1)
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("tl"))
                    .onChanged { v in scrubTo(frameAt(v.location.x, contentW)) }
                    .onEnded { _ in if play == .scrub { play = .frozen } }
            )
    }

    // MARK: - Geometry

    private func px(_ f: Int, _ contentW: CGFloat) -> CGFloat {
        CGFloat(f) / CGFloat(max(total - 1, 1)) * contentW
    }
    private func frameAt(_ x: CGFloat, _ contentW: CGFloat) -> Int {
        let f = Int((x / max(contentW, 1) * CGFloat(max(total - 1, 1))).rounded())
        return min(max(f, 0), total - 1)
    }
    private func slideAt(_ f: Int) -> Int {
        var idx = 0
        for (i, m) in marks.enumerated() where f >= m.holdStart { idx = i }
        return idx
    }
    private func holdContaining(_ f: Int) -> Int {
        marks.firstIndex { f >= $0.holdStart && f < $0.holdEnd } ?? -1
    }

    // MARK: - Actions

    private func scrubTo(_ f: Int) {
        guard play != .playing else { return }
        playhead = f; play = .scrub; seek(f)
    }
    // First = move the playhead to frame 0 and show it. Stay in .scrub so the preview
    // shows frame 0 (not the selected tick's frame, which .frozen would display).
    private func goFirst() { stopPlay(); scrubTo(0) }

    private func pushUndo() {
        undoStack.append(marks)
        if undoStack.count > 100 { undoStack.removeFirst() }
    }
    private func undo() {
        guard let prev = undoStack.popLast() else { return }
        marks = prev
        selectedSections = []
        if sel.slide >= marks.count { sel = MarkerRef(slide: max(0, marks.count - 1), edge: .start) }
        play = .frozen
        seek(tickFrame)
    }

    private func step(_ d: Int) {
        guard play != .playing, marks.indices.contains(sel.slide) else { return }
        pushUndo()
        let clamped = SlideMarkLogic.clamp(tickFrame + d, ref: sel, marks: marks, frameCount: frameCount)
        if sel.edge == .start { marks[sel.slide].holdStart = clamped } else { marks[sel.slide].holdEnd = clamped }
        play = .frozen; seek(clamped)
    }

    private func selectSection(_ s: Section, shift: Bool) {
        if shift {
            if selectedSections.contains(s) { selectedSections.remove(s) } else { selectedSections.insert(s) }
        } else {
            selectedSections = [s]
        }
    }

    // MARK: - Set length (type a frame count for a section or all selected)

    private func sectionLength(_ s: Section) -> Int {
        switch s {
        case .hold(let i):
            guard marks.indices.contains(i) else { return 0 }
            return marks[i].holdEnd - marks[i].holdStart
        case .transition(let i):
            guard marks.indices.contains(i), marks.indices.contains(i + 1) else { return 0 }
            return marks[i + 1].holdStart - marks[i].holdEnd
        }
    }

    /// Set a section to `n` frames by moving holdEnd (Go) — never the Rest or the next
    /// slide's Rest — clamped within neighbors.
    private func setSectionLength(_ s: Section, _ n: Int) {
        let nn = max(0, n)
        switch s {
        case .hold(let i):
            guard marks.indices.contains(i) else { return }
            let upper = i < marks.count - 1 ? marks[i + 1].holdStart - 1 : frameCount - 1
            marks[i].holdEnd = min(max(marks[i].holdStart, marks[i].holdStart + nn), max(marks[i].holdStart, upper))
        case .transition(let i):
            guard marks.indices.contains(i), marks.indices.contains(i + 1) else { return }
            let lower = marks[i].holdStart
            let upper = marks[i + 1].holdStart - 1
            marks[i].holdEnd = min(max(lower, marks[i + 1].holdStart - nn), max(lower, upper))
        }
    }

    private func beginLengthEdit(_ targets: [Section]) {
        guard !targets.isEmpty else { return }
        lengthTargets = targets
        lengthText = String(sectionLength(targets[0]))
        showLength = true
    }

    private func applyLength() {
        guard let n = Int(lengthText) else { return }
        pushUndo()
        for s in lengthTargets { setSectionLength(s, n) }   // each touches only its own holdEnd
        selectedSections = []
        showLength = false
        play = .frozen
        seek(tickFrame)
    }

    private func doSplit() {
        guard canSplit else { return }
        pushUndo()
        let i = holdContaining(playhead)
        marks = SlideMarkLogic.split(at: playhead, marks: marks)
        selectedSections = []
        sel = MarkerRef(slide: max(0, i), edge: .start)
        play = .frozen; seek(tickFrame)
    }

    private func doMerge() {
        guard let (a, _) = mergeHolds else { return }
        pushUndo()
        marks = SlideMarkLogic.merge(slide: a, marks: marks)
        selectedSections = []
        sel = MarkerRef(slide: min(a, marks.count - 1), edge: .start)
        play = .frozen; seek(tickFrame)
    }

    // MARK: - Play-to-next (sweeps the playhead through the transition)

    private func playToNext() {
        // Play from WHERE THE PLAYHEAD IS, not the last-selected slide. The current
        // slide is the one the playhead sits in/after.
        let cur = slideAt(playhead)
        guard play != .playing, cur < marks.count - 1, fps > 0 else { return }
        sel = MarkerRef(slide: cur, edge: .start)
        let go = marks[cur].holdEnd
        let nextRest = marks[cur + 1].holdStart
        let target = Double(nextRest) / fps
        play = .playing
        let goTime = CMTime(seconds: Double(go) / fps, preferredTimescale: 600)
        player.seek(to: goTime, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            // Seek completion fires on an arbitrary queue; hop to main before touching
            // MainActor state (timeObserver) or starting the periodic observer.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let interval = CMTime(value: 1, timescale: CMTimeScale(max(2.0, fps * 2)))
                    timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
                        MainActor.assumeIsolated {
                            let t = time.seconds
                            playhead = min(nextRest, max(go, Int((t * fps).rounded())))
                            if t >= target - 0.0005 {
                                finishPlay(landingOn: cur + 1)
                            }
                        }
                    }
                    player.play()
                }
            }
        }
    }

    private func finishPlay(landingOn slide: Int) {
        player.pause()
        if let ob = timeObserver { player.removeTimeObserver(ob); timeObserver = nil }
        sel = MarkerRef(slide: min(slide, marks.count - 1), edge: .start)
        playhead = marks[sel.slide].holdStart
        play = .frozen
        seek(playhead)
    }

    private func stopPlay() {
        player.pause()
        if let ob = timeObserver { player.removeTimeObserver(ob); timeObserver = nil }
        if play == .playing { play = .frozen }
    }

    private func seek(_ frame: Int) {
        guard fps > 0 else { return }
        player.seek(to: CMTime(seconds: Double(frame) / fps, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
    }
}
