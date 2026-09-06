# Backlog

Possible options and future ideas. Not committed work, just candidates.

## iOS keyboard microphone (open)

The dictation keyboard cannot start the microphone on a real device: `AVAudioEngine.start()`
fails with CoreAudio error `2003329396` ("input unavailable in the current context").
It works in the simulator, which does not enforce the same audio-session arbitration.

Already tried, did not fix it:
- Audio session `.playAndRecord` + `.spokenAudio` + `.mixWithOthers` (instead of `.duckOthers`).
- `RequestsOpenAccess` (Full Access) + `NSMicrophoneUsageDescription` in the keyboard Info.plist.
- `hasDictationKey = true` override in `KeyboardViewController` (Apple DTS guidance).

This lines up with an open Apple bug (FB16791704): recording from a keyboard extension is not
reliably supported.

### Possible option to try: AVCaptureSession instead of AVAudioEngine

Rewrite `Shared iOS/IOSAudioRecorder.swift` to capture via `AVCaptureSession` +
`AVCaptureDeviceInput` (audio) + `AVCaptureAudioDataOutput`, converting the delivered
`CMSampleBuffer` into the same 16 kHz mono Int16 PCM chunks the Soniox client already consumes.
Several developers report the `captureOutput` delegate fires reliably where `AVAudioEngine`
fails. No guarantee, but it is a genuinely different capture path, not another tweak of the
same engine.

### Fallback if that also fails: dictate in the main app

Move dictation into the main Speek iOS app (microphone works there), then hand the text
back. Downside: no dictation directly inside the field the user is typing in, which is the whole
point of the keyboard. This is why iOS system dictation is a built-in feature and third-party
keyboards struggle here.
