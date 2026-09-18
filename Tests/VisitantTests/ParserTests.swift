import Testing
@testable import Visitant

struct ParserTests {
    @Test func trailingSecondsTimer() {
        let steps = TranscriptParser.parse("- Step [10s]")

        #expect(steps == [
            Step(id: 0, text: "Step", duration: 10)
        ])
    }

    @Test func inlineMinutesTimerBeforeMoreText() {
        let steps = TranscriptParser.parse("- Step [1m]. More text")

        #expect(steps == [
            Step(id: 0, text: "Step. More text", duration: 60)
        ])
    }

    @Test func inlineDecimalMinutesTimerBetweenWords() {
        let steps = TranscriptParser.parse("- Before [1.5m] after")

        #expect(steps == [
            Step(id: 0, text: "Before after", duration: 90)
        ])
    }

    @Test func untimedBullet() {
        let steps = TranscriptParser.parse("- No timer")

        #expect(steps == [
            Step(id: 0, text: "No timer", duration: nil)
        ])
    }

    @Test func uppercaseMinuteUnit() {
        let steps = TranscriptParser.parse("- Uppercase [2M]")

        #expect(steps == [
            Step(id: 0, text: "Uppercase", duration: 120)
        ])
    }

    @Test func onlyFirstTimerMarkerIsConsumed() {
        let steps = TranscriptParser.parse("- First [1s] second [2s]")

        #expect(steps == [
            Step(id: 0, text: "First second [2s]", duration: 1)
        ])
    }

    @Test func demoStyleInlineTimers() {
        let steps = TranscriptParser.parse("""
        - Or, if you specify the timing mode ([Xx]) you can have it auto time how long you should spend on a point. [10s]. We kick off timing mode by pressing space.
        - Or time 1 minute while we really talk about a slide point [1m]. We can always skip forward.
        """)

        #expect(steps == [
            Step(
                id: 0,
                text: "Or, if you specify the timing mode ([Xx]) you can have it auto time how long you should spend on a point. We kick off timing mode by pressing space.",
                duration: 10
            ),
            Step(
                id: 1,
                text: "Or time 1 minute while we really talk about a slide point. We can always skip forward.",
                duration: 60
            )
        ])
    }
}
