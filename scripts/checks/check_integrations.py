#!/usr/bin/env python3
"""Run isolated MCP regression checks without credentials or Xcode's test target."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
checks = pathlib.Path(__file__).resolve().parent
server = subprocess.Popen(["/usr/bin/python3", str(checks / "mcp_fixture.py"), "--http"], stdout=subprocess.PIPE, text=True)
try:
    port = server.stdout.readline().strip()
    if not port.isdigit():
        raise RuntimeError("The HTTP fixture did not start")
    with tempfile.TemporaryDirectory(prefix="speek-mcp-checks-") as directory:
        binary = str(pathlib.Path(directory) / "checks")
        sources = sorted(str(p) for p in (root / "Speek/Integrations").glob("*.swift") if not p.name.endswith("View.swift"))
        subprocess.run(["xcrun", "swiftc", "-parse-as-library", *sources, str(checks / "MCPTransportChecks.swift"), "-o", binary], check=True)
        subprocess.run([binary, str(checks / "mcp_fixture.py"), port], check=True, timeout=30)
finally:
    server.terminate()
    server.wait(timeout=5)
