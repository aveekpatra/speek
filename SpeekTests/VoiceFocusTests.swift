import Testing
@testable import Speek

struct VoiceFocusTests {
    @Test func desktopIsNotAStaleAppTarget() {
        #expect(VoiceFocus.isDesktop(bundleID: "com.apple.finder", hasFocusedWindow: false))
        #expect(!VoiceFocus.isDesktop(bundleID: "com.apple.finder", hasFocusedWindow: true))
        #expect(!VoiceFocus.isDesktop(bundleID: "com.openai.chat", hasFocusedWindow: false))
    }

    @Test func editableControlsUseDictation() {
        for role in ["AXTextField", "AXTextArea", "AXComboBox"] {
            #expect(VoiceFocus.acceptsDictation(role: role, enabled: true, secure: false,
                editable: nil, selectedTextWritable: false, selectionWritable: false))
        }
        #expect(VoiceFocus.acceptsDictation(role: "AXGroup", enabled: true, secure: false,
            editable: true, selectedTextWritable: false, selectionWritable: false))
        #expect(VoiceFocus.acceptsDictation(role: "AXGroup", enabled: true, secure: false,
            editable: nil, selectedTextWritable: false, selectionWritable: true))
    }

    @Test func protectedAndReadOnlyFieldsDoNotUseDictation() {
        #expect(!VoiceFocus.acceptsDictation(role: "AXTextField", enabled: true, secure: true,
            editable: true, selectedTextWritable: true, selectionWritable: true))
        #expect(!VoiceFocus.acceptsDictation(role: "AXTextField", enabled: false, secure: false,
            editable: true, selectedTextWritable: true, selectionWritable: true))
        #expect(!VoiceFocus.acceptsDictation(role: "AXTextArea", enabled: true, secure: false,
            editable: false, selectedTextWritable: false, selectionWritable: true))
        for role in ["AXSlider", "AXStaticText", "AXScrollArea"] {
            #expect(!VoiceFocus.acceptsDictation(role: role, enabled: true, secure: false,
                editable: nil, selectedTextWritable: false, selectionWritable: false))
        }
    }
}
