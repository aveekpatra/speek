#!/usr/bin/env python3
"""Compile and run isolated native-tool and background-task boundary checks.

Never grants permissions, executes AppleScript, or changes calendar/app records.
Model calls are deterministic fakes. Native app checks only compile scripts.
"""
from pathlib import Path
import platform
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
CHECKS = Path(__file__).resolve().parent
SOURCE = ROOT / "Speek"
TARGET = ("arm64" if platform.machine() == "arm64" else "x86_64") + "-apple-macos14.0"
ORGANIZER = SOURCE / "Actions/NativeOrganizerTools.swift"
SCHEDULER = SOURCE / "Runtime/TaskScheduler.swift"
RUNNER = SOURCE / "Runtime/BackgroundAgentRunner.swift"
STUBS = CHECKS / "BackgroundRunnerStubs.swift"
SUITES = {
    "organizer": [ORGANIZER, CHECKS / "OrganizerChecks.swift"],
    "scheduler": [SCHEDULER, RUNNER, STUBS, CHECKS / "SchedulerChecks.swift"],
    "background": [SCHEDULER, RUNNER, STUBS, CHECKS / "BackgroundRunnerChecks.swift"],
    "native-app-scripts": [ORGANIZER, SOURCE / "Actions/NativeAppTools.swift", CHECKS / "NativeAppScriptChecks.swift"],
}
with tempfile.TemporaryDirectory(prefix="speek-native-checks-") as directory:
    for name, files in SUITES.items():
        executable = Path(directory) / name
        subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-target", TARGET, *map(str, files), "-o", str(executable)], check=True)
        subprocess.run([str(executable)], check=True, timeout=30)
