import Foundation
import Testing
@testable import Visitant

// Serialized because playback timers share the main run loop.
@MainActor
@Suite(.serialized)
final class TranscriptStateTests {
    private var tempURLs: [URL] = []

    deinit {
        for url in tempURLs {
            try? FileManager.default.removeItem(at: url)
        }
    }

    @Test func loadParsesTranscriptAndResetsPlayback() throws {
        let url = try writeTranscript("""
        - First step [10s]
        - Second step
        """)
        let state = TranscriptState()

        state.load(url: url)

        #expect(state.steps == [
            Step(id: 0, text: "First step", duration: 10),
            Step(id: 1, text: "Second step", duration: nil)
        ])
        #expect(state.index == 0)
        #expect(state.elapsedInStep == 0)
        #expect(!state.playing)
        #expect(state.sourceError == nil)
    }

    @Test func nextPrevAndRestartKeepIndexInBounds() throws {
        let url = try writeTranscript("""
        - One
        - Two
        """)
        let state = TranscriptState()
        state.load(url: url)

        state.next()
        #expect(state.index == 1)

        state.next()
        #expect(state.index == 1)

        state.prev()
        #expect(state.index == 0)

        state.prev()
        #expect(state.index == 0)

        state.playPause()
        #expect(state.playing)

        state.restart()
        #expect(state.index == 0)
        #expect(state.elapsedInStep == 0)
        #expect(!state.playing)
    }

    @Test func failedLoadStoresSourceErrorAndClearsSteps() {
        let state = TranscriptState()

        state.load(url: URL(fileURLWithPath: "/tmp/visitant-missing-\(UUID().uuidString).md"))

        #expect(state.steps.isEmpty)
        #expect(state.sourceError?.hasPrefix("load failed:") == true)
    }

    @Test func timedPlaybackAdvancesAndStopsAtEnd() async throws {
        let url = try writeTranscript("""
        - One [0.1s]
        - Two [0.1s]
        """)
        let state = TranscriptState()
        state.load(url: url)

        state.playPause()
        try await waitUntil(timeout: 2) { !state.playing }

        #expect(state.index == 1)
        #expect(!state.playing)
        #expect(abs(state.elapsedInStep) < 0.001)
    }

    @Test func untimedStepDoesNotAutoAdvance() async throws {
        let url = try writeTranscript("""
        - One
        - Two [0.1s]
        """)
        let state = TranscriptState()
        state.load(url: url)

        state.playPause()
        try await Task.sleep(for: .milliseconds(250))

        #expect(state.index == 0)
        #expect(state.playing)
        state.restart()
    }

    private func waitUntil(timeout: TimeInterval, _ done: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !done() && Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func writeTranscript(_ contents: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VisitantTests", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appendingPathComponent("\(UUID().uuidString).md")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        tempURLs.append(url)
        return url
    }
}
