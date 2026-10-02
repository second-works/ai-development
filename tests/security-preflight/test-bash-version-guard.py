#!/usr/bin/env python3
"""Verify Bash 5 entry guards before any git/gh/npm/Python side effect."""

import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = [
    ("templates/security/security-preflight.sh", [str(ROOT)], True),
    (".agents/skills/pr-review-fix/scripts/prepare-pr.sh", ["1"], False),
    (".agents/skills/pr-review-fix/scripts/verify-pr-head.sh", ["1", "a" * 40, "b" * 40], False),
    (".agents/skills/pr-review-fix/scripts/wait-checks.sh", ["github.com/owner/repo", "a" * 40], False),
    (".agents/skills/pr-review-fix/scripts/wait-codex-review.sh", ["github.com/owner/repo", "1", "a" * 40, "100", "200", "0"], False),
]


for relative, _, _ in SCRIPTS:
    source = (ROOT / relative).read_text(encoding="utf-8")
    if "BASH_VERSINFO[0] < 5" not in source:
        raise AssertionError(f"{relative}: missing Bash 5 guard")
if '"$BASH" "$SECURITY_PREFLIGHT_SCRIPT"' not in (ROOT / ".agents/skills/pr-review-fix/scripts/wait-checks.sh").read_text(encoding="utf-8"):
    raise AssertionError("wait-checks must run fallback preflight with its verified Bash")

legacy_bash = Path("/bin/bash")
if legacy_bash.exists():
    major = int(subprocess.check_output([str(legacy_bash), "-c", "printf '%s' \"${BASH_VERSINFO[0]}\""], text=True))
    if major < 5:
        with tempfile.TemporaryDirectory(prefix="bash-version-test-") as tmp:
            fixture = Path(tmp)
            calls = fixture / "calls"
            mock = fixture / "mock"
            mock.write_text("#!/bin/sh\nprintf '%s\\n' \"$0\" >> \"$BASH_GUARD_CALLS\"\nexit 99\n", encoding="utf-8")
            mock.chmod(0o755)
            for name in ("git", "gh", "npm", "python3"):
                (fixture / name).symlink_to(mock)
            env = {**os.environ, "PATH": f"{fixture}:/usr/bin:/bin", "BASH_GUARD_CALLS": str(calls)}
            for relative, args, is_security in SCRIPTS:
                result = subprocess.run([str(legacy_bash), str(ROOT / relative), *args], text=True, capture_output=True, env=env, timeout=10)
                output = result.stdout + result.stderr
                if result.returncode == 0 or "Bash 5 or newer required" not in output or f"current {major}." not in output:
                    raise AssertionError(f"{relative}: expected an explanatory nonzero Bash {major} rejection; got {result.returncode}: {output}")
                if is_security and "SECURITY_STATUS=SECURITY_UNAVAILABLE" not in output:
                    raise AssertionError(f"{relative}: missing machine-readable unavailable status: {output}")
                if calls.exists():
                    raise AssertionError(f"{relative}: called an external tool before rejecting Bash {major}")
            print(f"actual Bash {major} early rejection and no external calls passed")
    else:
        print(f"actual Bash 3.2 execution skipped: /bin/bash is {major}; static guards checked")
else:
    print("actual Bash 3.2 execution skipped: /bin/bash is unavailable; static guards checked")
