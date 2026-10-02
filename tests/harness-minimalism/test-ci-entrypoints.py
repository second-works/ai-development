#!/usr/bin/env python3
"""Keep every tests/*/run-samples.sh entrypoint in Template CI run steps."""

from pathlib import Path
import re
import tempfile


ROOT = Path(__file__).resolve().parents[2]
DIRECT_RUN = re.compile(r"(?m)^[ \t]+run:[ \t]+(?:bash[ \t]+)?(tests/[A-Za-z0-9_-]+/run-samples\.sh)[ \t]*$")


def check(root: Path) -> list[str]:
    workflow = (root / ".github/workflows/ci.yml").read_text(encoding="utf-8")
    inventory = {p.relative_to(root).as_posix() for p in root.glob("tests/*/run-samples.sh")}
    entries = DIRECT_RUN.findall(workflow)
    registered = set(entries)
    problems = []
    if len(entries) != len(registered):
        problems.append("duplicate CI run step for a sample entrypoint")
    for path in sorted(inventory - registered):
        problems.append(f"sample entrypoint has no direct CI run step: {path}")
    for path in sorted(registered - inventory):
        problems.append(f"CI run step points to a missing sample entrypoint: {path}")
    return problems


def fixture_root(tmp: Path, *, suites: tuple[str, ...], commands: tuple[str, ...]) -> Path:
    root = tmp / "repo"
    (root / ".github/workflows").mkdir(parents=True)
    for suite in suites:
        path = root / f"tests/{suite}/run-samples.sh"
        path.parent.mkdir(parents=True)
        path.write_text("#!/bin/bash\n", encoding="utf-8")
    workflow = "name: Template CI\njobs:\n  verification:\n    steps:\n"
    for index, command in enumerate(commands):
        workflow += f"      - name: Sample {index}\n        run: {command}\n"
    (root / ".github/workflows/ci.yml").write_text(workflow, encoding="utf-8")
    return root


with tempfile.TemporaryDirectory(prefix="ci-entrypoints-test-") as temp:
    temp_path = Path(temp)
    cases = [
        (("a", "b"), ("bash tests/a/run-samples.sh", "tests/b/run-samples.sh"), False),
        (("a", "b"), ("bash tests/a/run-samples.sh",), True),
        (("a", "b"), ("bash tests/a/run-samples.sh", "bash -n tests/b/run-samples.sh"), True),
        (("a",), ("bash tests/a/run-samples.sh", "bash tests/missing/run-samples.sh"), True),
        (("a",), ("bash tests/a/run-samples.sh", "bash tests/a/run-samples.sh"), True),
    ]
    for index, (suites, commands, should_fail) in enumerate(cases):
        case_dir = temp_path / str(index)
        case_dir.mkdir()
        result = check(fixture_root(case_dir, suites=suites, commands=commands))
        if bool(result) != should_fail:
            raise AssertionError(f"fixture {index}: unexpected CI coverage result: {result}")

problems = check(ROOT)
if problems:
    raise SystemExit("\n".join(problems))
print("Template CI sample entrypoints match direct run steps")
