#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 5 || $# -gt 6 ]]; then
  echo "Usage: $0 <repo-identity> <pr-number> <expected-sha> <after-comment-id> <after-review-id> [timeout-seconds]" >&2
  exit 2
fi

REPO_IDENTITY="$1"
PR="$2"
EXPECTED_SHA="$3"
AFTER_COMMENT_ID="$4"
AFTER_REVIEW_ID="$5"
TIMEOUT="${6:-300}"
INTERVAL=5
START="$(date +%s)"
SHORT10="${EXPECTED_SHA:0:10}"

command -v gh >/dev/null 2>&1 || { echo "ERROR: gh not found" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 not found" >&2; exit 1; }

if [[ "$REPO_IDENTITY" != */*/* ]]; then
  echo "ERROR: repository identity must be HOST/owner/repo" >&2
  exit 1
fi
if [[ ! "$AFTER_COMMENT_ID" =~ ^[0-9]+$ ]]; then
  echo "ERROR: after-comment-id must be a numeric GitHub issue comment id" >&2
  exit 1
fi
if [[ ! "$AFTER_REVIEW_ID" =~ ^[0-9]+$ ]]; then
  echo "ERROR: after-review-id must be a numeric GitHub pull request review id" >&2
  exit 1
fi

HOST="${REPO_IDENTITY%%/*}"
REPO_PATH="${REPO_IDENTITY#*/}"
OWNER="${REPO_PATH%%/*}"
REPO_NAME="${REPO_PATH#*/}"

gh auth status --hostname "$HOST" >/dev/null 2>&1 || {
  echo "ERROR: gh authentication is not available for $HOST" >&2
  exit 1
}

TMPDIR_RUN="$(mktemp -d "${TMPDIR:-/tmp}/pr-review-codex.XXXXXX")"
trap 'rm -rf "$TMPDIR_RUN"' EXIT

while :; do
  NOW="$(date +%s)"
  ELAPSED=$((NOW - START))

  gh api --hostname "$HOST" --paginate --slurp \
    "repos/$REPO_PATH/issues/$PR/comments?per_page=100" \
    >"$TMPDIR_RUN/issue-comments.json"
  gh api --hostname "$HOST" --paginate --slurp \
    "repos/$REPO_PATH/pulls/$PR/comments?per_page=100" \
    >"$TMPDIR_RUN/review-comments.json"
  gh api --hostname "$HOST" --paginate --slurp \
    "repos/$REPO_PATH/pulls/$PR/reviews?per_page=100" \
    >"$TMPDIR_RUN/reviews.json"
  gh api graphql --hostname "$HOST" --paginate --slurp \
    -f query='query($owner: String!, $name: String!, $number: Int!, $endCursor: String) {
      repository(owner: $owner, name: $name) {
        pullRequest(number: $number) {
          reviewThreads(first: 100, after: $endCursor) {
            nodes {
              id
              isResolved
              comments(first: 20) {
                nodes {
                  author { login __typename }
                  body
                  createdAt
                  outdated
                }
              }
            }
            pageInfo { hasNextPage endCursor }
          }
        }
      }
    }' \
    -f owner="$OWNER" \
    -f name="$REPO_NAME" \
    -F number="$PR" \
    >"$TMPDIR_RUN/review-threads.json"

  RESULT="$(python3 - "$TMPDIR_RUN/issue-comments.json" "$TMPDIR_RUN/review-comments.json" "$TMPDIR_RUN/reviews.json" "$TMPDIR_RUN/review-threads.json" "$EXPECTED_SHA" "$SHORT10" "$AFTER_COMMENT_ID" "$AFTER_REVIEW_ID" <<'PY'
import json, re, sys

issue_path, review_path, reviews_path, threads_path, sha, short10, after_comment_id, after_review_id = sys.argv[1:]
after_comment_id = int(after_comment_id)
after_review_id = int(after_review_id)

ALLOWED_CODEX_LOGINS = {
    'chatgpt-codex-connector',
    'chatgpt-codex-connector[bot]',
}

def flatten_pages(path):
    with open(path, encoding='utf-8') as f:
        pages = json.load(f)
    out = []
    for page in pages:
        if isinstance(page, list):
            out.extend(page)
        elif isinstance(page, dict):
            out.append(page)
    return out

def is_allowed_rest_actor(item):
    user = item.get('user') or {}
    login = (user.get('login') or '').lower()
    actor_type = user.get('type') or ''
    return login in ALLOWED_CODEX_LOGINS and actor_type == 'Bot'

def is_allowed_graphql_actor(comment):
    author = comment.get('author') or {}
    login = (author.get('login') or '').lower()
    actor_type = author.get('__typename') or ''
    return login in ALLOWED_CODEX_LOGINS and actor_type == 'Bot'

def severities_in(body):
    return [sev for sev in ('P0', 'P1', 'P2') if re.search(rf'\b{sev}\b', body or '')]

issue_comments = flatten_pages(issue_path)
review_comments = flatten_pages(review_path)
reviews = flatten_pages(reviews_path)
thread_pages = flatten_pages(threads_path)

request_comment = next(
    (c for c in issue_comments if int(c.get('id') or 0) == after_comment_id),
    None,
)
if request_comment is None:
    print("ERROR=request comment id was not found")
    sys.exit(4)

eligible_review_ids = set()
for r in reviews:
    if not is_allowed_rest_actor(r):
        continue
    rid = int(r.get('id') or 0)
    if rid <= after_review_id:
        continue
    if (r.get('commit_id') or '') != sha:
        continue
    body = r.get('body') or ''
    if 'Reviewed commit:' not in body or (short10 not in body and sha not in body):
        continue
    eligible_review_ids.add(rid)

review_seen = bool(eligible_review_ids)
review_ids_text = ','.join(str(v) for v in sorted(eligible_review_ids))

review_comment_id = None
for c in issue_comments:
    cid = int(c.get('id') or 0)
    if cid <= after_comment_id:
        continue
    body = c.get('body') or ''
    if is_allowed_rest_actor(c) and 'Reviewed commit:' in body and (short10 in body or sha in body):
        review_comment_id = cid
        break

new_severities = []
for c in review_comments:
    if not is_allowed_rest_actor(c):
        continue
    if (c.get('commit_id') or '') != sha:
        continue
    review_id = int(c.get('pull_request_review_id') or 0)
    if review_id not in eligible_review_ids:
        continue
    new_severities.extend(severities_in(c.get('body') or ''))

unresolved_severities = []
unresolved_thread_ids = []
for page in thread_pages:
    pr = (((page.get('data') or {}).get('repository') or {}).get('pullRequest') or {})
    threads = ((pr.get('reviewThreads') or {}).get('nodes') or [])
    for thread in threads:
        if thread.get('isResolved'):
            continue
        matched = False
        for c in ((thread.get('comments') or {}).get('nodes') or []):
            if not is_allowed_graphql_actor(c):
                continue
            if c.get('outdated'):
                continue
            found = severities_in(c.get('body') or '')
            if found:
                unresolved_severities.extend(found)
                matched = True
        if matched:
            unresolved_thread_ids.append(thread.get('id') or '<unknown>')

all_findings = new_severities + unresolved_severities
auto_blocking = [sev for sev in all_findings if sev in ('P0', 'P1')]
p2_findings = [sev for sev in all_findings if sev == 'P2']
print(f"REVIEW_SEEN={1 if review_seen else 0}")
print(f"REVIEW_IDS={review_ids_text}")
print(f"REVIEW_COMMENT_ID={review_comment_id or ''}")
print(f"REQUEST_COMMENT_ID={after_comment_id}")
print(f"REQUEST_CREATED_AT={request_comment.get('created_at') or ''}")
print(f"AFTER_REVIEW_ID={after_review_id}")
print(f"NEW_FINDING_COUNT={len(new_severities)}")
print(f"UNRESOLVED_FINDING_COUNT={len(unresolved_severities)}")
print(f"AUTO_BLOCKING_COUNT={len(auto_blocking)}")
print(f"P2_CLASSIFICATION_COUNT={len(p2_findings)}")
if all_findings:
    print("FINDING_SEVERITIES=" + ','.join(sorted(set(all_findings))))
if unresolved_thread_ids:
    print("UNRESOLVED_THREAD_IDS=" + ','.join(unresolved_thread_ids))
PY
)"

  REVIEW_SEEN="$(printf '%s\n' "$RESULT" | awk -F= '$1=="REVIEW_SEEN"{print $2}')"
  AUTO_BLOCKING_COUNT="$(printf '%s\n' "$RESULT" | awk -F= '$1=="AUTO_BLOCKING_COUNT"{print $2}')"
  P2_CLASSIFICATION_COUNT="$(printf '%s\n' "$RESULT" | awk -F= '$1=="P2_CLASSIFICATION_COUNT"{print $2}')"

  if [[ "$REVIEW_SEEN" -eq 1 ]]; then
    printf '%s\n' "$RESULT"
    echo "EXPECTED_SHA=$EXPECTED_SHA"
    echo "AFTER_COMMENT_ID=$AFTER_COMMENT_ID"
    echo "AFTER_REVIEW_ID=$AFTER_REVIEW_ID"
    if [[ "$AUTO_BLOCKING_COUNT" -gt 0 ]]; then
      echo "STATUS=REVIEW_CHANGES_REQUIRED"
      exit 3
    fi
    if [[ "$P2_CLASSIFICATION_COUNT" -gt 0 ]]; then
      echo "STATUS=REVIEW_P2_CLASSIFICATION_REQUIRED"
      exit 4
    fi
    echo "STATUS=REVIEW_PASSED"
    exit 0
  fi

  if [[ "$ELAPSED" -ge "$TIMEOUT" ]]; then
    echo "ERROR: timed out waiting for a new Codex review of $EXPECTED_SHA after review id $AFTER_REVIEW_ID" >&2
    exit 1
  fi

  sleep "$INTERVAL"
done
