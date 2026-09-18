// TranscriptState: observable playback state shared between AppController and TranscriptView.
//
// Playback model:
//   • steps is a flat array of Step values parsed from the transcript file.
//   • index points at the "current" step; the view shows a window of steps around it.
//   • When playing, a 0.1 s repeating Timer drives tick(), which accumulates elapsed
//     time and auto-advances to the next step when elapsedInStep >= step.duration.
//   • Untimed steps (duration == nil) are skipped by the timer; the user must advance
//     manually with next()/prev().

import Foundation
import SwiftUI

// @MainActor ensures all property updates happen on the main thread, which is required
// for @Published properties driving SwiftUI updates.
@MainActor
final class TranscriptState: ObservableObject {
    @Published var steps: [Step] = []
    @Published var index: Int = 0
    @Published var elapsedInStep: Double = 0  // seconds elapsed in the current step
    @Published var playing: Bool = false
    @Published var sourceError: String? = nil

    private var timer: Timer?
    private var lastTick: Date?

    /// Parse and load a transcript file, resetting all playback state.
    func load(path: String) {
        load(url: URL(fileURLWithPath: path))
    }

    /// Parse and load a transcript file URL, resetting all playback state.
    func load(url: URL) {
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            steps = TranscriptParser.parse(text)
            index = 0
            elapsedInStep = 0
            playing = false
            sourceError = nil
        } catch {
            sourceError = "load failed: \(error.localizedDescription)"
            steps = []
        }
    }

    func playPause() {
        playing.toggle()
        if playing { startTimer() } else { stopTimer() }
    }

    func next() {
        guard !steps.isEmpty else { return }
        if index < steps.count - 1 {
            index += 1
            elapsedInStep = 0
        }
    }

    func prev() {
        guard !steps.isEmpty else { return }
        if index > 0 { index -= 1 }
        elapsedInStep = 0
    }

    func restart() {
        index = 0
        elapsedInStep = 0
        playing = false
        stopTimer()
    }

    private func startTimer() {
        stopTimer()
        lastTick = Date()
        // 0.1 s interval gives smooth progress-bar animation without excessive CPU.
        // The closure uses [weak self] to avoid a retain cycle (Timer retains its target).
        // Task { @MainActor in } hops to the main actor because Timer callbacks arrive
        // on whatever thread the run loop is scheduled on.
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        lastTick = nil
    }

    /// Called every 0.1 s while playing. Accumulates real elapsed time (not fixed 0.1 s,
    /// so pausing or system load doesn't cause drift) and advances to the next step
    /// when the current step's duration is reached.
    private func tick() {
        let now = Date()
        let dt = lastTick.map { now.timeIntervalSince($0) } ?? 0
        lastTick = now
        guard playing else { return }
        guard index < steps.count else { playing = false; stopTimer(); return }
        let cur = steps[index]
        guard let duration = cur.duration else { return }  // untimed: wait for manual next
        elapsedInStep += dt
        if elapsedInStep >= duration {
            elapsedInStep = 0
            if index + 1 < steps.count {
                index += 1
            } else {
                playing = false
                stopTimer()
            }
        }
    }
}
