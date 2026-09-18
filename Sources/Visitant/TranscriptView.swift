// TranscriptView: the SwiftUI content of the floating overlay window.
//
// Layout strategy:
//   • The root view expands to the full NSWindow so the translucent panel and
//     overlays track live resize.
//   • The transcript list takes the spare vertical space, while the footer stays
//     pinned to the bottom.
//
// Move vs. resize in move mode:
//   • Window moving is handled by isMovableByWindowBackground (set in AppController).
//     AppKit's background drag yields to SwiftUI gesture recognizers, so ResizeGrip
//     takes priority when the user drags from that corner.
//   • ResizeGrip uses a plain DragGesture with no competing move gesture to fight.

import AppKit
import SwiftUI

@MainActor
final class OverlaySettings: ObservableObject {
    @Published var interactive: Bool = false
    @Published var panelOpacity: Double

    init(panelOpacity: Double) {
        self.panelOpacity = panelOpacity
    }
}

// MARK: - ResizeGrip

/// Drag handle in the bottom-right corner, visible only in move mode.
/// Resizes the window by tracking total translation from drag start,
/// keeping the top-left corner anchored. macOS window origin is bottom-left,
/// so growing downward means decreasing y.
///
/// The start frame is @GestureState rather than @State: it resets automatically
/// when the drag ends, and @State is a macro that needs the full Xcode toolchain.
private struct ResizeGrip: View {
    @GestureState private var startFrame: NSRect?

    var body: some View {
        Image(systemName: "arrow.down.right.square.fill")
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(.blue)
            .padding(6)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .updating($startFrame) { value, startFrame, _ in
                        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.level == .floating }) else { return }
                        let start = startFrame ?? window.frame
                        startFrame = start
                        let newW = max(380, start.width + value.translation.width)
                        let newH = max(160, start.height + value.translation.height)
                        // Anchor top-left: growing height pushes origin down (y decreases).
                        let newOrigin = NSPoint(x: start.minX, y: start.minY - (newH - start.height))
                        window.setFrame(NSRect(origin: newOrigin, size: NSSize(width: newW, height: newH)), display: true)
                    }
            )
    }
}

// MARK: - TranscriptView

struct TranscriptView: View {
    @ObservedObject var state: TranscriptState
    @ObservedObject var settings: OverlaySettings

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            statusBar
            stepsList
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            progressBar
            if settings.interactive {
                helpBar
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(minWidth: 380, maxWidth: .infinity, minHeight: 160, maxHeight: .infinity, alignment: .topLeading)
        .background(panel)
        .overlay(alignment: .topTrailing) {
            if settings.interactive { moveModeIndicator }
        }
        .overlay(alignment: .bottomTrailing) {
            if settings.interactive { ResizeGrip() }
        }
    }

    // MARK: - Panel background

    /// Rounded-rectangle backdrop. Slightly gray (not pure white) so text stays
    /// readable against both light and dark content behind the window, while
    /// still remaining semi-transparent.
    private var panel: some View {
        let fill = settings.interactive
            ? Color(red: 0.84, green: 0.92, blue: 1.0, opacity: settings.panelOpacity)
            : Color(white: 0.90, opacity: settings.panelOpacity)
        let stroke = settings.interactive
            ? Color.blue.opacity(0.92)
            : Color.black.opacity(0.08)
        let lineWidth: CGFloat = settings.interactive ? 1.5 : 0.5

        return RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(fill)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(stroke, lineWidth: lineWidth)
            )
        // No SwiftUI .shadow() here: the system window shadow (hasShadow=true in main.swift)
        // casts from the composited content, following the rounded shape automatically.
        // A SwiftUI shadow on the outer frame would be clipped by the window edge anyway.
    }

    private var moveModeIndicator: some View {
        Image(systemName: "hand.point.up.left.fill")
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(
                Circle()
                    .fill(Color.blue.opacity(0.95))
                    .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 1)
            )
            .padding(8)
    }

    // MARK: - Subviews

    private var statusBar: some View {
        let label: String = state.steps.isEmpty
            ? "no transcript"
            : (state.playing ? "PLAYING" : "PAUSED")
                + " · \(state.index + 1)/\(state.steps.count)"
        return Text(label)
            .font(.system(size: 10, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(state.playing ? Color.blue.opacity(0.85) : Color.black.opacity(0.45))
    }

    @ViewBuilder private var stepsList: some View {
        if let err = state.sourceError {
            Text(err).font(.system(size: 13)).foregroundStyle(.red)
        } else if state.steps.isEmpty {
            Text("open a transcript from the status menu")
                .font(.system(size: 13))
                .foregroundStyle(.black.opacity(0.5))
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(state.steps.indices, id: \.self) { i in
                            stepRow(state.steps[i], at: i)
                                .id(i)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .onAppear {
                    proxy.scrollTo(state.index, anchor: .top)
                }
                .onChange(of: state.index) { _, newIndex in
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(newIndex, anchor: .top)
                    }
                }
            }
        }
    }

    private func stepRow(_ step: Step, at i: Int) -> some View {
        let isCurrent = i == state.index
        let isPast = i < state.index
        let size: CGFloat = isCurrent ? 20 : (isPast ? 12 : 14)
        let weight: Font.Weight = isCurrent ? .bold : .medium
        let opacity: Double = isCurrent ? 1.0 : (isPast ? 0.45 : 0.75)
        return Text(step.text)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(Color.black.opacity(isCurrent ? 0.92 : 0.55))
            // Italic signals an untimed step — no auto-advance, requires manual next.
            .italic(step.duration == nil)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(opacity)
    }

    /// Thin bar showing elapsed fraction of the current timed step's duration.
    /// Shows zero fill for untimed steps (duration == nil).
    private var progressBar: some View {
        GeometryReader { geo in
            let cur = state.steps.indices.contains(state.index) ? state.steps[state.index] : nil
            let pct: Double = {
                guard let d = cur?.duration, d > 0 else { return 0 }
                return min(1, state.elapsedInStep / d)
            }()
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(.black.opacity(0.08))
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.blue.opacity(0.75))
                    .frame(width: geo.size.width * pct)
            }
        }
        .frame(height: 3)
    }

    private var helpBar: some View {
        Text("⌃⌥Space play/pause · ⌃⌥→ next · ⌃⌥← prev · ⌃⌥R restart · ⌃⌥H hide · ⌃⌥M move · ⌃⌥C capture · ⌃⌥Q quit")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.black.opacity(0.35))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
