#!/usr/bin/env python3
"""Compile production source with isolated local fixtures; never call cloud services."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
CHECKS = [
    ("dictation", "Speek/Assistant/DictationPipeline.swift", "DictationChecks.swift"),
    ("memory", "Speek/Assistant/AssistantMemory.swift", "MemoryChecks.swift"),
    ("prompts", "Speek/Runtime/PromptLibrary.swift", "PromptChecks.swift"),
    ("history", "Speek/Assistant/DictationHistory.swift", "DictationHistoryChecks.swift"),
    ("handsfree", "Speek/Assistant/HandsFreeShortcut.swift", "HandsFreeChecks.swift"),
    ("capture", "Speek/Assistant/VoiceCapturePreferences.swift", "VoiceCaptureChecks.swift"),
    ("recovery", "Speek/Assistant/RecordingRecovery.swift", "RecordingRecoveryChecks.swift"),
]

with tempfile.TemporaryDirectory(prefix="speek-voice-checks-") as temporary:
    for name, source, fixture in CHECKS:
        binary = Path(temporary) / name
        subprocess.run([
            "xcrun", "swiftc", "-o", str(binary), str(ROOT / source),
            str(ROOT / "scripts/checks" / fixture),
        ], check=True)
        subprocess.run([str(binary)], check=True)
print("All seven voice and memory feature checks passed.")
