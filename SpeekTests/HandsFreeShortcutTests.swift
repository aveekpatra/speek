import Testing
@testable import Speek

struct HandsFreeShortcutTests {
    @Test func holdReleaseDuringStartupFinishesWhenReady() {
        var state = HandsFreeShortcut()
        #expect(state.press(at: 0, enabled: false) == .startRecording)
        #expect(state.release(at: 0.1) == .none)
        #expect(state.didStartRecording() == .finishRecording)
        #expect(!state.isEngaged)
    }
    @Test func doubleTapLatchesDuringStartupAndNextPressFinishes() {
        var state = HandsFreeShortcut()
        #expect(state.press(at: 0, enabled: true) == .startRecording)
        #expect(state.release(at: 0.1) == .waitForSecondTap)
        #expect(state.press(at: 0.2, enabled: true) == .none)
        #expect(state.release(at: 0.3) == .none)
        #expect(state.isHandsFree)
        #expect(state.didStartRecording() == .none)
        #expect(state.expireTapWindow(at: 1) == .none)
        #expect(state.press(at: 2, enabled: true) == .finishRecording)
    }
    @Test func longHoldDoesNotLatchAndCancellationClearsPendingTap() {
        var state = HandsFreeShortcut()
        #expect(state.press(at: 0, enabled: true) == .startRecording)
        #expect(state.didStartRecording() == .none)
        #expect(state.release(at: 1) == .finishRecording)
        #expect(state.press(at: 2, enabled: true) == .startRecording)
        #expect(state.release(at: 2.1) == .waitForSecondTap)
        state.cancel()
        #expect(state.expireTapWindow(at: 3) == .none)
        #expect(state.didStartRecording() == .none)
    }
    @Test func tapExpiryDuringStartupWaitsForMicrophone() {
        var state = HandsFreeShortcut()
        #expect(state.press(at: 0, enabled: true) == .startRecording)
        #expect(state.release(at: 0.1) == .waitForSecondTap)
        #expect(state.expireTapWindow(at: 0.2) == .none)
        #expect(state.expireTapWindow(at: 0.5) == .none)
        #expect(state.didStartRecording() == .finishRecording)
    }
}
