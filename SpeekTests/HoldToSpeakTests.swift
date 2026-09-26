import Testing
@testable import Speek

struct HoldToSpeakTests {
    @Test func normalHoldFinishesOnRelease() {
        var hold = HoldToSpeak()
        #expect(hold.press())
        #expect(!hold.press())
        #expect(!hold.didStartRecording())
        #expect(hold.release())
        #expect(!hold.release())
    }

    @Test func releaseDuringStartupFinishesWhenReady() {
        var hold = HoldToSpeak()
        #expect(hold.press())
        #expect(!hold.release())
        #expect(!hold.press())
        #expect(hold.didStartRecording())
        #expect(!hold.isEngaged)
    }

    @Test func interruptionDoesNotStartAnotherRecordingOnRelease() {
        var hold = HoldToSpeak()
        #expect(hold.press())
        hold.cancel()
        #expect(!hold.release())
        #expect(!hold.didStartRecording())
        #expect(hold.press())
    }
}
