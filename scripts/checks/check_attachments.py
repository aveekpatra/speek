#!/usr/bin/env python3
"""Check attachment extraction and lifecycle without launching Speek."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
checks = pathlib.Path(__file__).resolve().parent
with tempfile.TemporaryDirectory(prefix="speek-attachment-checks-") as directory:
    helper = pathlib.Path(directory) / "UIHelpers.swift"
    source = (root / "Speek/UI/Pages/ActionConnectionsView.swift").read_text()
    helper.write_text("import SwiftUI\n" + source[source.index("extension View {\n    func settingsSurface"):])
    binary = str(pathlib.Path(directory) / "checks")
    subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-target", "arm64-apple-macos26.0", str(root / "Speek/Assistant/ComposerAttachments.swift"), str(helper), str(checks / "AttachmentChecks.swift"), "-o", binary], check=True)
    subprocess.run([binary], check=True, timeout=30)
