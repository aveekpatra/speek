#!/usr/bin/env python3
"""Check coding queue and CLI event parsing with a fake executor. No agent runs."""
from pathlib import Path
import platform
import subprocess
import tempfile
root = Path(__file__).resolve().parents[2]
checks = Path(__file__).resolve().parent
with tempfile.TemporaryDirectory(prefix="speek-coding-checks-") as directory:
    target = ("arm64" if platform.machine() == "arm64" else "x86_64") + "-apple-macos14.0"
    binary = Path(directory) / "coding-checks"
    subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-target", target,
                    str(root / "Speek/Actions/CodingTaskManager.swift"),
                    str(checks / "CodingTaskStubs.swift"), str(checks / "CodingTaskChecks.swift"),
                    "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True, timeout=30)
