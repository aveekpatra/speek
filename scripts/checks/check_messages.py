#!/usr/bin/env python3
"""Verify Messages tools against an isolated SQLite fixture only.

Never reads the real Messages database, grants permissions, or sends a message.
The fixed AppleScript is compiled against the installed dictionary, not executed.
"""
from pathlib import Path
import platform
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
checks = Path(__file__).resolve().parent
with tempfile.TemporaryDirectory(prefix="speek-messages-checks-") as directory:
    target = ("arm64" if platform.machine() == "arm64" else "x86_64") + "-apple-macos14.0"
    binary = Path(directory) / "messages-checks"
    subprocess.run([
        "xcrun", "swiftc", "-swift-version", "6", "-target", target,
        str(root / "Speek/Actions/NativeOrganizerTools.swift"),
        str(root / "Speek/Actions/MessagesTools.swift"),
        str(checks / "MessagesChecks.swift"), "-o", str(binary),
    ], check=True)
    subprocess.run([str(binary)], check=True, timeout=30)
