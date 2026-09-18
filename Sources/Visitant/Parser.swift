// Parser: converts a Markdown transcript file into an array of Steps.
//
// Transcript format — each step is a Markdown list item:
//
//   Timed (auto-advance after the given duration):
//     - Step text [5s]      ← seconds
//     - Step text [1.5m]    ← minutes
//     - Step [1m]. More text
//
//   Untimed (wait for manual next):
//     - Step text
//
//   Blank lines and lines starting with # are ignored, so you can use
//   headings and paragraphs as section labels or notes.

import Foundation

/// A single presentation cue — either auto-advancing (duration != nil)
/// or waiting for a manual keypress (duration == nil).
struct Step: Identifiable, Equatable {
    let id: Int
    let text: String
    /// nil = untimed; positive = duration in seconds.
    let duration: Double?
}

enum TranscriptParser {
    // Matches:  - Some text
    //           * Some text
    // Groups:   1 = text
    private static let listItem: NSRegularExpression = {
        let pattern = #"^\s*[-*]\s+(.+?)\s*$"#
        return try! NSRegularExpression(pattern: pattern)
    }()

    // Matches timer markers anywhere in a list item, e.g. [5s], [1.5m], [2M].
    // Groups: 1 = number, 2 = unit (s/m)
    private static let timerMarker: NSRegularExpression = {
        let pattern = #"\[\s*(\d+(?:\.\d+)?)\s*(s|m)\s*\]"#
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    private static let repeatedWhitespace: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"\s+"#)
    }()

    private static let whitespaceBeforePunctuation: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"\s+([.,;:!?])"#)
    }()

    private static let duplicatedPunctuationAcrossRemovedMarker: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"([.,;:!?])\s+\1"#)
    }()

    /// Parse a transcript string and return all steps in order.
    static func parse(_ src: String) -> [Step] {
        var steps: [Step] = []
        var i = 0
        for raw in src.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let range = NSRange(line.startIndex..<line.endIndex, in: line)

            guard let m = listItem.firstMatch(in: line, range: range), m.numberOfRanges == 2 else {
                // Non-list lines (paragraphs, headings already filtered above) are silently skipped.
                continue
            }

            let rawText = substring(line, m.range(at: 1))
            let parsed = parseTimer(in: rawText)
            steps.append(Step(id: i, text: parsed.text, duration: parsed.duration))
            i += 1
        }
        return steps
    }

    private static func parseTimer(in rawText: String) -> (text: String, duration: Double?) {
        let range = NSRange(rawText.startIndex..<rawText.endIndex, in: rawText)
        guard let marker = timerMarker.firstMatch(in: rawText, range: range), marker.numberOfRanges == 3 else {
            return (rawText, nil)
        }

        let n = Double(substring(rawText, marker.range(at: 1))) ?? 0
        let unit = substring(rawText, marker.range(at: 2)).lowercased()
        let seconds = unit == "m" ? n * 60.0 : n
        return (removingTimerMarker(marker.range, from: rawText), seconds)
    }

    private static func removingTimerMarker(_ markerRange: NSRange, from text: String) -> String {
        guard let range = Range(markerRange, in: text) else { return text }
        var cleaned = text
        cleaned.removeSubrange(range)
        cleaned = replacingMatches(in: cleaned, using: repeatedWhitespace, with: " ")
        cleaned = replacingMatches(in: cleaned, using: duplicatedPunctuationAcrossRemovedMarker, with: "$1")
        cleaned = replacingMatches(in: cleaned, using: whitespaceBeforePunctuation, with: "$1")
        return cleaned.trimmingCharacters(in: .whitespaces)
    }

    private static func replacingMatches(in text: String, using regex: NSRegularExpression, with template: String) -> String {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }

    // NSRegularExpression returns NSRange (based on UTF-16 offsets), but Swift strings
    // use Unicode scalar positions. Range(nsRange, in: swiftString) does the conversion.
    private static func substring(_ s: String, _ r: NSRange) -> String {
        guard let range = Range(r, in: s) else { return "" }
        return String(s[range])
    }
}
