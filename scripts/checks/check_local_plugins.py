#!/usr/bin/env python3
"""Run isolated CLI and dictation-hook checks without credentials."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
checks = pathlib.Path(__file__).resolve().parent
with tempfile.TemporaryDirectory(prefix="speek-local-plugin-checks-") as directory:
    binary = str(pathlib.Path(directory) / "checks")
    sources = [str(root / "Speek/Integrations" / name) for name in ("MCPTypes.swift", "LocalPluginStore.swift")]
    subprocess.run(["xcrun", "swiftc", "-parse-as-library", *sources, str(checks / "LocalPluginChecks.swift"), "-o", binary], check=True)
    subprocess.run([binary, str(checks / "local_plugin_fixture.py")], check=True, timeout=30)
