"""Offline local plugin fixture."""
import json
import sys
import time

payload = json.load(sys.stdin)
mode = sys.argv[1]
if mode == "echo":
    print(json.dumps({"payload": payload, "arguments": sys.argv[2:]}))
elif mode == "hook":
    print(json.dumps({"text": payload["text"].upper()}))
elif mode == "invalid-hook":
    print("not JSON")
elif mode == "wait":
    time.sleep(20)
elif mode == "large":
    print("x" * (2 * 1024 * 1024))
elif mode == "fail":
    sys.exit(2)
