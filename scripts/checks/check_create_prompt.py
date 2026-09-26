#!/usr/bin/env python3
"""Offline prompt lifecycle checks; provider stubs never make network requests."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
checks = pathlib.Path(__file__).resolve().parent
with tempfile.TemporaryDirectory(prefix="speek-prompt-checks-") as directory:
    helper = pathlib.Path(directory) / "UIHelpers.swift"
    source = (root / "Speek/UI/Pages/ActionConnectionsView.swift").read_text()
    helper.write_text("import SwiftUI\n" + source[source.index("extension View {\n    func settingsSurface"):])
    binary = str(pathlib.Path(directory) / "checks")
    subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-target", "arm64-apple-macos26.0", str(root / "Speek/Assistant/CreatePromptSession.swift"), str(root / "Speek/Assistant/CreatePromptView.swift"), str(helper), str(checks / "CreatePromptChecks.swift"), "-o", binary], check=True)
    subprocess.run([binary], check=True, timeout=20)
