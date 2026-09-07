#!/usr/bin/env python3
"""Collect a minimal, read-only GitHub observation for Structured Current State.

This tool intentionally collects observations only. It never interprets them as
CI, Security, Review, Acceptance, or merge decisions, and it never writes to
GitHub.
"""

from __future__ import annotations

import argparse
import http.client
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional, Tuple


API_BASE = "https://api.github.com"
API_HOST = "api.github.com"
API_VERSION = "2022-11-28"
USER_AGENT = "ai-development-github-state-observer/1.0"
SHA_PATTERN = re.compile(r"^[0-9a-fA-F]{40}$")
REPOSITORY_PATTERN = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
ENV_NAME_PATTERN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
ISSUE_STATES = {"open", "closed"}
WORKFLOW_STATUSES = {"queued", "in_progress", "completed", "waiting", "requested", "pending"}
WORKFLOW_CONCLUSIONS = {"action_required", "cancelled", "failure", "neutral", "startup_failure", "success", "skipped", "stale", "timed_out"}
REVIEW_STATES = {"APPROVED", "CHANGES_REQUESTED", "COMMENTED", "DISMISSED", "PENDING"}


class CollectionError(Exception):
    def __init__(self, operation: str, kind: str, detail: str, status: Optional[int] = None):
        super().__init__(detail)
        self.operation = operation
        self.kind = kind
        self.detail = detail
        self.status = status


@dataclass
class Response:
    payload: Any
    source_url: str
    next_url: Optional[str]


def positive_number(value: str) -> int:
    try:
        number = int(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError("must be a positive integer") from error
    if number < 1:
        raise argparse.ArgumentTypeError("must be a positive integer")
    return number


def repository_name(value: str) -> str:
    if not REPOSITORY_PATTERN.fullmatch(value):
        raise argparse.ArgumentTypeError("must be in owner/repository form")
    return value


def environment_name(value: str) -> str:
    if not ENV_NAME_PATTERN.fullmatch(value):
        raise argparse.ArgumentTypeError("must be a valid environment variable name")
    return value


def observed_at(value: Optional[str]) -> str:
    if value is None:
        return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as error:
        raise argparse.ArgumentTypeError("must be an RFC 3339 timestamp") from error
    if parsed.tzinfo is None:
        raise argparse.ArgumentTypeError("must include a timezone")
    return parsed.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def parse_next_link(value: Optional[str]) -> Optional[str]:
    if not value:
        return None
    for part in value.split(","):
        match = re.search(r"<([^>]+)>;\s*rel=\"?next\"?", part)
        if match:
            return match.group(1)
    return None


def source_url(path: str, query: Optional[Mapping[str, str]] = None) -> str:
    encoded = urllib.parse.urlencode(query or {})
    return f"{API_BASE}{path}" + (f"?{encoded}" if encoded else "")


def reject_invalid_unicode(value: Any) -> None:
    if isinstance(value, str):
        if any(0xD800 <= ord(character) <= 0xDFFF for character in value):
            raise UnicodeDecodeError("utf-8", b"", 0, 1, "JSON string contained a surrogate code point")
    elif isinstance(value, dict):
        for key, item in value.items():
            reject_invalid_unicode(key)
            reject_invalid_unicode(item)
    elif isinstance(value, list):
        for item in value:
            reject_invalid_unicode(item)


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, new_url):  # type: ignore[no-untyped-def]
        return None


class GitHubTransport:
    def __init__(self, token: Optional[str]):
        self.token = token
        self.opener = urllib.request.build_opener(NoRedirect())

    def get(self, operation: str, path: str, query: Optional[Mapping[str, str]] = None) -> Response:
        return self._read(operation, source_url(path, query))

    def get_url(self, operation: str, url: str) -> Response:
        parsed = urllib.parse.urlparse(url)
        if parsed.scheme != "https" or parsed.netloc != API_HOST or parsed.username or parsed.password:
            raise CollectionError(operation, "UNTRUSTED_PAGINATION_URL", "pagination URL is not GitHub API")
        return self._read(operation, url)

    def _read(self, operation: str, url: str) -> Response:
        headers = {
            "Accept": "application/vnd.github+json",
            "User-Agent": USER_AGENT,
            "X-GitHub-Api-Version": API_VERSION,
        }
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"
        request = urllib.request.Request(url, headers=headers, method="GET")
        try:
            with self.opener.open(request, timeout=20) as response:
                try:
                    raw = response.read().decode("utf-8")
                    payload = json.loads(raw)
                    reject_invalid_unicode(payload)
                except (UnicodeDecodeError, json.JSONDecodeError) as error:
                    raise CollectionError(operation, "INVALID_JSON", "GitHub response was not JSON") from error
                return Response(payload=payload, source_url=url, next_url=parse_next_link(response.headers.get("Link")))
        except CollectionError:
            raise
        except urllib.error.HTTPError as error:
            raise CollectionError(operation, "HTTP_ERROR", f"GitHub returned HTTP {error.code}", error.code) from error
        except TimeoutError as error:
            raise CollectionError(operation, "NETWORK_ERROR", "GitHub request timed out") from error
        except urllib.error.URLError as error:
            raise CollectionError(operation, "NETWORK_ERROR", "GitHub request could not be completed") from error
        except (http.client.HTTPException, OSError) as error:
            raise CollectionError(operation, "NETWORK_ERROR", "GitHub request could not be completed") from error


class FixtureTransport:
    """Offline transport used only by deterministic tests.

    For paginated operations, <operation>-page-1.json is read first. A
    following page file creates an in-memory next link, exercising the same
    pagination path as live GitHub responses without network access.
    """

    def __init__(self, directory: Path):
        self.directory = directory

    def get(self, operation: str, path: str, query: Optional[Mapping[str, str]] = None) -> Response:
        page = int((query or {}).get("page", "1"))
        filename = f"{operation}-page-{page}.json" if operation in PAGINATED_OPERATIONS else f"{operation}.json"
        return self._read(operation, filename, page if operation in PAGINATED_OPERATIONS else None)

    def get_url(self, operation: str, url: str) -> Response:
        parsed = urllib.parse.urlparse(url)
        if parsed.scheme != "fixture" or parsed.netloc != operation:
            raise CollectionError(operation, "UNTRUSTED_PAGINATION_URL", "fixture pagination URL is invalid")
        page = int(urllib.parse.parse_qs(parsed.query).get("page", ["0"])[0])
        if page < 2:
            raise CollectionError(operation, "UNTRUSTED_PAGINATION_URL", "fixture pagination page is invalid")
        return self._read(operation, f"{operation}-page-{page}.json", page)

    def _read(self, operation: str, filename: str, page: Optional[int]) -> Response:
        path = self.directory / filename
        if not path.is_file():
            raise CollectionError(operation, "FIXTURE_MISSING", f"fixture is missing: {filename}")
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as error:
            raise CollectionError(operation, "INVALID_JSON", f"fixture is not JSON: {filename}") from error
        if isinstance(payload, dict) and "fixture_error" in payload:
            error = payload["fixture_error"]
            if not isinstance(error, dict):
                raise CollectionError(operation, "INVALID_RESPONSE", "fixture_error must be an object")
            raise CollectionError(
                operation,
                str(error.get("kind", "FIXTURE_ERROR")),
                str(error.get("detail", "fixture requested an error")),
                error.get("status") if isinstance(error.get("status"), int) else None,
            )
        next_url = None
        if page is not None and (self.directory / f"{operation}-page-{page + 1}.json").is_file():
            next_url = f"fixture://{operation}?page={page + 1}"
        return Response(payload=payload, source_url=f"fixture://{filename}", next_url=next_url)


PAGINATED_OPERATIONS = {"workflow-runs", "reviews", "review-comments"}


def as_object(operation: str, payload: Any) -> Dict[str, Any]:
    if not isinstance(payload, dict):
        raise CollectionError(operation, "INVALID_RESPONSE", "response must be an object")
    return payload


def require_number(operation: str, payload: Mapping[str, Any], expected: int) -> None:
    if payload.get("number") != expected:
        raise CollectionError(operation, "IDENTITY_MISMATCH", "response number did not match requested number")


def require_head_sha(operation: str, payload: Mapping[str, Any]) -> str:
    head = payload.get("head")
    value = head.get("sha") if isinstance(head, dict) else None
    if not isinstance(value, str) or not SHA_PATTERN.fullmatch(value):
        raise CollectionError(operation, "INVALID_RESPONSE", "pull request head SHA is missing or invalid")
    return value.lower()


def require_enum(operation: str, field: str, value: Any, allowed: set[str], nullable: bool = False) -> Optional[str]:
    if value is None and nullable:
        return None
    if not isinstance(value, str) or value not in allowed:
        raise CollectionError(operation, "UNKNOWN_ENUM", f"{field} was not a supported value")
    return value


def normalize_issue(payload: Mapping[str, Any], source: str) -> Dict[str, Any]:
    return {
        "number": payload.get("number"),
        "state": payload.get("state"),
        "html_url": payload.get("html_url"),
        "updated_at": payload.get("updated_at"),
        "source_url": source,
    }


def normalize_pr(payload: Mapping[str, Any], source: str) -> Dict[str, Any]:
    head = payload.get("head") if isinstance(payload.get("head"), dict) else {}
    base = payload.get("base") if isinstance(payload.get("base"), dict) else {}
    return {
        "number": payload.get("number"),
        "state": payload.get("state"),
        "merged": payload.get("merged"),
        "head_branch": head.get("ref"),
        "head_sha": head.get("sha"),
        "base_sha": base.get("sha"),
        "html_url": payload.get("html_url"),
        "updated_at": payload.get("updated_at"),
        "source_url": source,
    }


def normalize_run(payload: Mapping[str, Any], expected_sha: str) -> Dict[str, Any]:
    head_sha = payload.get("head_sha")
    status = require_enum("workflow-runs", "status", payload.get("status"), WORKFLOW_STATUSES)
    conclusion = require_enum("workflow-runs", "conclusion", payload.get("conclusion"), WORKFLOW_CONCLUSIONS, nullable=True)
    return {
        "id": payload.get("id"),
        "name": payload.get("name"),
        "event": payload.get("event"),
        "head_sha": head_sha,
        "head_matches_observed_pr": isinstance(head_sha, str) and head_sha.lower() == expected_sha,
        "status": status,
        "conclusion": conclusion,
        "html_url": payload.get("html_url"),
        "workflow_path": payload.get("path"),
        "run_attempt": payload.get("run_attempt"),
        "created_at": payload.get("created_at"),
        "updated_at": payload.get("updated_at"),
    }


def normalize_review(payload: Mapping[str, Any], expected_sha: str) -> Dict[str, Any]:
    commit_id = payload.get("commit_id")
    user = payload.get("user") if isinstance(payload.get("user"), dict) else {}
    state = require_enum("reviews", "state", payload.get("state"), REVIEW_STATES)
    return {
        "id": payload.get("id"),
        "state": state,
        "commit_id": commit_id,
        "head_matches_observed_pr": isinstance(commit_id, str) and commit_id.lower() == expected_sha,
        "submitted_at": payload.get("submitted_at"),
        "html_url": payload.get("html_url"),
        "author_login": user.get("login"),
    }


def normalize_review_comment(payload: Mapping[str, Any], expected_sha: str) -> Dict[str, Any]:
    commit_id = payload.get("commit_id")
    user = payload.get("user") if isinstance(payload.get("user"), dict) else {}
    return {
        "id": payload.get("id"),
        "commit_id": commit_id,
        "head_matches_observed_pr": isinstance(commit_id, str) and commit_id.lower() == expected_sha,
        "path": payload.get("path"),
        "line": payload.get("line"),
        "side": payload.get("side"),
        "in_reply_to_id": payload.get("in_reply_to_id"),
        "html_url": payload.get("html_url"),
        "author_login": user.get("login"),
    }


def paginate(transport: Any, operation: str, path: str, query: Mapping[str, str], list_key: Optional[str]) -> Tuple[List[Dict[str, Any]], List[str]]:
    response = transport.get(operation, path, query)
    pages: List[str] = []
    items: List[Dict[str, Any]] = []
    while True:
        pages.append(response.source_url)
        payload = response.payload
        if list_key is not None:
            payload = as_object(operation, payload).get(list_key)
        if not isinstance(payload, list) or not all(isinstance(item, dict) for item in payload):
            raise CollectionError(operation, "INVALID_RESPONSE", "paginated response did not contain an object list")
        items.extend(payload)
        if not response.next_url:
            return items, pages
        response = transport.get_url(operation, response.next_url)


def target_head_evidence_status(items: List[Mapping[str, Any]]) -> str:
    return "OBSERVED" if items else "NOT_OBSERVED"


def empty_observation(args: argparse.Namespace, captured_at: str) -> Dict[str, Any]:
    evidence_status = "NOT_APPLICABLE" if args.pr is None else "NOT_OBSERVED"
    return {
        "observer_schema_version": 1,
        "observed_at": captured_at,
        "repository": args.repository,
        "requested": {"issue_number": args.issue, "pull_request_number": args.pr},
        "collection": {"status": "UNAVAILABLE", "usable_for_state_update": False, "errors": []},
        "issue": {"number": args.issue, "observation_status": "NOT_OBSERVED"},
        "pull_request": None if args.pr is None else {"number": args.pr, "observation_status": "NOT_OBSERVED"},
        "head_consistency": {
            "status": "NOT_APPLICABLE",
            "initial_head_sha": None,
            "final_head_sha": None,
            "initial_source_url": None,
            "final_source_url": None,
        },
        "workflow_runs": {"observed_head_sha": None, "target_head_evidence_status": evidence_status, "security_named_runs": [], "other_runs": [], "nonmatching_head_runs": [], "source_urls": []},
        "reviews": {"target_head_evidence_status": evidence_status, "same_head": [], "other_head": [], "source_urls": []},
        "review_comments": {"target_head_evidence_status": evidence_status, "same_head": [], "other_head": [], "source_urls": []},
        "interpretation": "OBSERVATION_ONLY: this artifact does not set schema v3 verification, acceptance, approval, review classification, stop reason, or merge decision.",
    }


def collect(args: argparse.Namespace, captured_at: str) -> Tuple[Dict[str, Any], int]:
    transport: Any
    if args.fixture_dir:
        transport = FixtureTransport(args.fixture_dir)
    else:
        transport = GitHubTransport(os.environ.get(args.token_env))

    observation = empty_observation(args, captured_at)
    owner, name = args.repository.split("/", 1)
    prefix = f"/repos/{owner}/{name}"
    try:
        issue_response = transport.get("issue", f"{prefix}/issues/{args.issue}")
        issue = as_object("issue", issue_response.payload)
        require_number("issue", issue, args.issue)
        require_enum("issue", "state", issue.get("state"), ISSUE_STATES)
        if "pull_request" in issue:
            raise CollectionError("issue", "IDENTITY_MISMATCH", "response was a pull request")
        observation["issue"] = {"observation_status": "OBSERVED", **normalize_issue(issue, issue_response.source_url)}

        if args.pr is None:
            observation["collection"] = {"status": "COMPLETE", "usable_for_state_update": True, "errors": []}
            return observation, 0

        initial_response = transport.get("pr-initial", f"{prefix}/pulls/{args.pr}")
        initial_pr = as_object("pr-initial", initial_response.payload)
        require_number("pr-initial", initial_pr, args.pr)
        require_enum("pr-initial", "state", initial_pr.get("state"), ISSUE_STATES)
        initial_head = require_head_sha("pr-initial", initial_pr)
        observation["pull_request"] = {"observation_status": "OBSERVED", **normalize_pr(initial_pr, initial_response.source_url)}
        observation["head_consistency"]["initial_head_sha"] = initial_head
        observation["head_consistency"]["initial_source_url"] = initial_response.source_url
        observation["workflow_runs"]["observed_head_sha"] = initial_head

        run_items, run_sources = paginate(
            transport,
            "workflow-runs",
            f"{prefix}/actions/runs",
            {"head_sha": initial_head, "per_page": "100", "page": "1"},
            "workflow_runs",
        )
        normalized_runs = [normalize_run(item, initial_head) for item in run_items]
        observation["workflow_runs"]["security_named_runs"] = [run for run in normalized_runs if run["name"] == "Security" and run["head_matches_observed_pr"]]
        observation["workflow_runs"]["other_runs"] = [run for run in normalized_runs if run["name"] != "Security" and run["head_matches_observed_pr"]]
        observation["workflow_runs"]["nonmatching_head_runs"] = [run for run in normalized_runs if not run["head_matches_observed_pr"]]
        observation["workflow_runs"]["source_urls"] = run_sources
        observation["workflow_runs"]["target_head_evidence_status"] = target_head_evidence_status(
            observation["workflow_runs"]["security_named_runs"] + observation["workflow_runs"]["other_runs"]
        )

        review_items, review_sources = paginate(
            transport,
            "reviews",
            f"{prefix}/pulls/{args.pr}/reviews",
            {"per_page": "100", "page": "1"},
            None,
        )
        normalized_reviews = [normalize_review(item, initial_head) for item in review_items]
        observation["reviews"]["same_head"] = [review for review in normalized_reviews if review["head_matches_observed_pr"]]
        observation["reviews"]["other_head"] = [review for review in normalized_reviews if not review["head_matches_observed_pr"]]
        observation["reviews"]["source_urls"] = review_sources
        observation["reviews"]["target_head_evidence_status"] = target_head_evidence_status(observation["reviews"]["same_head"])

        comment_items, comment_sources = paginate(
            transport,
            "review-comments",
            f"{prefix}/pulls/{args.pr}/comments",
            {"per_page": "100", "page": "1"},
            None,
        )
        normalized_comments = [normalize_review_comment(item, initial_head) for item in comment_items]
        observation["review_comments"]["same_head"] = [comment for comment in normalized_comments if comment["head_matches_observed_pr"]]
        observation["review_comments"]["other_head"] = [comment for comment in normalized_comments if not comment["head_matches_observed_pr"]]
        observation["review_comments"]["source_urls"] = comment_sources
        observation["review_comments"]["target_head_evidence_status"] = target_head_evidence_status(observation["review_comments"]["same_head"])

        final_response = transport.get("pr-final", f"{prefix}/pulls/{args.pr}")
        final_pr = as_object("pr-final", final_response.payload)
        require_number("pr-final", final_pr, args.pr)
        require_enum("pr-final", "state", final_pr.get("state"), ISSUE_STATES)
        final_head = require_head_sha("pr-final", final_pr)
        observation["pull_request"] = {"observation_status": "OBSERVED", **normalize_pr(final_pr, final_response.source_url)}
        observation["head_consistency"]["final_head_sha"] = final_head
        observation["head_consistency"]["final_source_url"] = final_response.source_url
        if final_head != initial_head:
            observation["head_consistency"]["status"] = "MISMATCH"
            observation["collection"] = {
                "status": "UNAVAILABLE",
                "usable_for_state_update": False,
                "errors": [{"operation": "pr-final", "kind": "HEAD_CHANGED_DURING_COLLECTION", "detail": "observed PR head changed during collection"}],
            }
            return observation, 3

        observation["head_consistency"]["status"] = "MATCH"
        observation["collection"] = {"status": "COMPLETE", "usable_for_state_update": True, "errors": []}
        return observation, 0
    except CollectionError as error:
        item: Dict[str, Any] = {"operation": error.operation, "kind": error.kind, "detail": error.detail}
        if error.status is not None:
            item["http_status"] = error.status
        observation["collection"] = {"status": "UNAVAILABLE", "usable_for_state_update": False, "errors": [item]}
        return observation, 3


def write_output(observation: Mapping[str, Any], output: str) -> None:
    rendered = json.dumps(observation, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    if output == "-":
        sys.stdout.write(rendered)
        return
    path = Path(output)
    try:
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
        with os.fdopen(os.open(path, flags, 0o600), "w", encoding="utf-8") as destination:
            destination.write(rendered)
    except FileExistsError as error:
        raise CollectionError("output", "OUTPUT_EXISTS", "refusing to overwrite an existing observation") from error
    except OSError as error:
        raise CollectionError("output", "OUTPUT_WRITE_FAILED", "could not write observation output") from error


def parse_args(argv: List[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Collect read-only GitHub metadata for Structured Current State.")
    parser.add_argument("--repository", required=True, type=repository_name, help="GitHub repository in owner/repository form")
    parser.add_argument("--issue", required=True, type=positive_number, help="Issue number to observe")
    parser.add_argument("--pr", type=positive_number, help="Optional pull request number to observe")
    parser.add_argument("--output", required=True, help="New JSON output path, or - for stdout")
    parser.add_argument("--token-env", default="GITHUB_TOKEN", type=environment_name, help="Optional environment variable holding a GitHub read token")
    parser.add_argument("--fixture-dir", type=Path, help="Offline fixture directory for tests; no network or token is used")
    parser.add_argument("--observed-at", help="RFC 3339 timestamp for reproducible fixture output; requires --fixture-dir")
    return parser.parse_args(argv)


def main(argv: List[str]) -> int:
    args = parse_args(argv)
    if args.observed_at is not None and args.fixture_dir is None:
        print("argument error: --observed-at requires --fixture-dir", file=sys.stderr)
        return 2
    try:
        captured_at = observed_at(args.observed_at)
    except argparse.ArgumentTypeError as error:
        print(f"argument error: {error}", file=sys.stderr)
        return 2
    observation, exit_code = collect(args, captured_at)
    try:
        write_output(observation, args.output)
    except CollectionError as error:
        print(f"output error: {error.kind}: {error.detail}", file=sys.stderr)
        return 4
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
