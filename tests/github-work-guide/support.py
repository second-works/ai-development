"""Shared test setup: import path and the repository the fixtures come from.

The fixtures are PUBLIC data captured from second-works/hermes-self-improvement, where the harness
was first written, so tests seal them for that repository with its gate settings. Nothing here is
read from the network.
"""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = Path(__file__).resolve().parent / 'fixtures'
if str(ROOT / 'scripts') not in sys.path:
    sys.path.insert(0, str(ROOT / 'scripts'))

from github_work_guide import core  # noqa: E402

REPO = 'second-works/hermes-self-improvement'
PREFIX = f'repos/{REPO}'
# Its .github/pr-gate-checks at the time of the fixtures, and the Codex review it then used.
SETTINGS = {'default_branch': 'main', 'required_checks': ['ci', 'Security Preflight', 'Analyze (python)'],
            'checks_source': 'repository', 'review': ['codex'], 'review_source': 'default'}


def seal(items, coverage, repo=REPO, settings=SETTINGS):
    return core.seal(items, coverage, repo, settings)


def source_url(kind, n, repo=REPO):
    return core.source_url(repo, kind, n)


def gate(item, settings=SETTINGS):
    return core.gate(item, settings)
