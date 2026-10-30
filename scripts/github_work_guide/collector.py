"""Allowlisted GitHub read transport and bounded acquisition (existing gh auth).

One Collector reads one repository. The repository comes from config/github-work-guide.json;
every route is built from it and checked against a per-repository allowlist.
"""
import base64
import re
import subprocess
import time
from dataclasses import asdict, dataclass

from .core import (CLOSED_PR_OMITTED, DEFAULT_CHECKS, DEFAULT_REVIEW, Invalid, digest, names, number, now,
                   repo_name, require, seal, source_url, strict_json, validate, validate_settings)

class SettingFileError(Invalid):
    """A .github/pr-gate-* file was read but its lines are not usable names."""


# Files read from the default branch. Only their presence and lines are used, never executed.
SETTING_FILES = ('.github/pr-gate-checks', '.github/pr-gate-review')


def prefix(repo):
    return f'repos/{repo_name(repo)}'


def rest_route(repo):
    return re.compile(re.escape(prefix(repo)) + r'(?:|/issues|/issues/[1-9][0-9]*(?:/comments)?|/pulls/[1-9][0-9]*(?:/reviews|/comments)?'
                      r'|/commits/[0-9a-f]{40}/(?:check-runs|statuses))\Z')


def content_route(repo, path):
    require(path in SETTING_FILES, 'content path not allowlisted')
    return f'{prefix(repo)}/contents/{path}'


def setting_lines(text, strip=False):
    """Lines of a pr-gate-* file, parsed like scripts/check-pr-head.sh reads pr-gate-checks: one trailing CR
    is removed, whitespace-only lines and lines starting with # in the first column are skipped, and check
    names keep their spaces (the merge gate looks for exactly that name). Review kinds (strip=True) lose all
    whitespace, as the check-pr-head.sh versions that read pr-gate-review do."""
    require(isinstance(text, str) and len(text) <= 10_000, 'setting file')
    rows = [line[:-1] if line.endswith('\r') else line for line in text.split('\n')]
    rows = [line for line in rows if line.strip() and not line.startswith('#')]
    if strip:
        rows = [''.join(line.split()) for line in rows]
    return list(dict.fromkeys(rows))
CONNECTIONS = {
    'threads': ('reviewThreads', 'id isResolved isOutdated'),
    'closing': ('closingIssuesReferences', 'number repository { nameWithOwner }'),
}


# Highest value config/github-work-guide.json may set per repository. pages is fixed by rest_request (10).
MAXIMUM = {'pages': 10, 'items': 20000, 'calls': 2000, 'seconds': 900}


@dataclass(frozen=True)
class Limits:
    pages: int = 10  # Per connection, not per repository.
    items: int = 5000  # All returned list nodes, including checks/comments.
    calls: int = 500
    seconds: int = 180

    def __post_init__(self):
        for field, maximum in MAXIMUM.items():
            require(type(getattr(self, field)) is int and 0 < getattr(self, field) <= maximum, 'invalid limit')


def rest_request(repo, path, page=None):
    require(isinstance(path, str) and rest_route(repo).fullmatch(path) is not None, 'read route not allowlisted')
    query = ''
    if path == prefix(repo) + '/issues':
        require(page is not None, 'issue list requires page')
        query = 'state=all&sort=created&direction=asc&'
    if page is not None:
        require(type(page) is int and 1 <= page <= 10, 'invalid page')
        query += f'per_page=100&page={page}'
    return path + ('?' + query if query else '')


def connection_query(kind):
    """Fixed query text; owner and name are GraphQL variables, never spliced into the query."""
    require(kind in CONNECTIONS, 'unknown connection')
    name, fields = CONNECTIONS[kind]
    return ('query($owner:String!,$name:String!,$number:Int!,$cursor:String){repository(owner:$owner,name:$name)'
            '{pullRequest(number:$number){' + name + '(first:100,after:$cursor){nodes{' + fields + '}'
            'pageInfo{hasNextPage endCursor}}}}}')


class GhReadOnly:
    """Bound to one repository. No public arbitrary command/query/method facility; never reads token values."""
    def __init__(self, repo):
        self.repo = repo_name(repo)

    @staticmethod
    def _run(args, timeout, missing_ok=False):
        try:
            proc = subprocess.run(['gh', 'api', '--hostname', 'github.com', *args],
                                  capture_output=True, timeout=timeout, check=False)
        except (OSError, subprocess.TimeoutExpired):
            raise Invalid('GitHub transport unavailable/timeout') from None
        # Only "not found" is a result (absent file, invisible repository); stderr is never printed or stored.
        if proc.returncode != 0 and missing_ok and b'HTTP 404' in proc.stderr:
            return None
        require(proc.returncode == 0, 'GitHub read failed (auth/permission/rate/network); details omitted')
        require(len(proc.stdout) <= 10_000_000, 'API response too large')
        try:
            return strict_json(proc.stdout.decode('utf-8'))
        except UnicodeError:
            raise Invalid('invalid API encoding') from None

    def get(self, path, page, timeout):
        # The repository metadata may be 404 (private without access, or a wrong name): reported, not failed.
        return self._run(['--method', 'GET', rest_request(self.repo, path, page)], timeout,
                         missing_ok=path == prefix(self.repo))

    def content(self, path, ref, timeout):
        """Text of an allowlisted file on `ref`, or None when it does not exist."""
        require(isinstance(ref, str) and 0 < len(ref) <= 255, 'invalid ref')
        value = self._run(['--method', 'GET', '--raw-field', f'ref={ref}', content_route(self.repo, path)],
                          timeout, missing_ok=True)
        if value is None:
            return None
        require(isinstance(value, dict) and value.get('type') == 'file' and value.get('encoding') == 'base64'
                and isinstance(value.get('content'), str), 'content schema')
        try:
            return base64.b64decode(value['content'], validate=False).decode('utf-8')
        except (ValueError, UnicodeError):
            raise Invalid('invalid content encoding') from None

    def connection(self, kind, n, cursor, timeout):
        number(n)
        require(cursor is None or isinstance(cursor, str) and 0 < len(cursor) <= 1024, 'invalid cursor')
        owner, name = self.repo.split('/')
        args = ['graphql', '-f', 'query=' + connection_query(kind), '-f', f'owner={owner}', '-f', f'name={name}',
                '-F', f'number={n}']
        if cursor is not None:
            args += ['-f', 'cursor=' + cursor]
        return self._run(args, timeout)


class Collector:
    def __init__(self, repo, transport=None, limits=None, required_checks=None):
        self.repo = repo_name(repo)
        self.prefix = prefix(self.repo)
        self.transport = transport or GhReadOnly(self.repo)
        self.limits = limits or Limits()
        # Set in config/github-work-guide.json; otherwise .github/pr-gate-checks of the repository decides.
        self.required_checks = None if required_checks is None else names(list(required_checks))
        self.started = time.monotonic()
        self.calls = 0
        self.nodes = 0
        self.connections = []

    def call(self, function, *args):
        remaining = self.limits.seconds - (time.monotonic() - self.started)
        require(self.calls < self.limits.calls and remaining > 0, 'API/time limit reached')
        self.calls += 1
        result = function(*args, min(30, remaining))
        require(time.monotonic() - self.started <= self.limits.seconds, 'time limit reached')
        return result

    def count(self, rows):
        require(isinstance(rows, list), 'API list missing')
        self.nodes += len(rows)
        require(self.nodes <= self.limits.items, 'item limit reached')

    def pages(self, path, field=None):
        marker = {'route': path, 'pages': 0, 'count': 0, 'complete': False}
        self.connections.append(marker)
        result = []
        expected = None
        for page in range(1, self.limits.pages + 1):
            response = self.call(self.transport.get, path, page)
            marker['pages'] = page
            if field:
                require(isinstance(response, dict) and type(response.get('total_count')) is int, 'check count missing')
                if expected is None:
                    expected = response['total_count']
                require(expected == response['total_count'], 'check count changed during pagination')
                rows = response.get(field)
            else:
                rows = response
            self.count(rows)
            require(len(rows) <= 100, 'invalid page size')
            result += rows
            marker['count'] = len(result)
            if len(rows) < 100:
                require(expected is None or len(result) == expected, 'partial check results')
                marker['complete'] = True
                return result
        raise Invalid('page limit reached')

    def connection(self, kind, n):
        marker = {'route': f'pr:{n}:{kind}', 'pages': 0, 'count': 0, 'complete': False}
        self.connections.append(marker)
        result, cursor, seen = [], None, set()
        for page in range(1, self.limits.pages + 1):
            response = self.call(self.transport.connection, kind, n, cursor)
            require(isinstance(response, dict) and not response.get('errors'), 'GraphQL read error')
            name = CONNECTIONS[kind][0]
            connection = response['data']['repository']['pullRequest'][name]
            rows, info = connection['nodes'], connection['pageInfo']
            self.count(rows)
            require(len(rows) <= 100 and type(info['hasNextPage']) is bool, 'invalid GraphQL pagination')
            result += rows
            marker.update(pages=page, count=len(result))
            if not info['hasNextPage']:
                marker['complete'] = True
                return result
            cursor = info['endCursor']
            require(isinstance(cursor, str) and cursor and cursor not in seen, 'missing/repeated cursor')
            seen.add(cursor)
        raise Invalid('GraphQL page limit reached')

    def settings(self, branch):
        """Per-repository gate settings, read from the default branch. scripts/check-pr-head.sh reads the
        same files from each PR's base branch, so a PR to another branch can be judged differently there."""
        texts = {}
        for path in SETTING_FILES:
            texts[path] = self.call(self.transport.content, path, branch)
        try:
            listed = names(setting_lines(texts['.github/pr-gate-checks']), exact=True) \
                if texts['.github/pr-gate-checks'] is not None and setting_lines(texts['.github/pr-gate-checks']) else []
            kinds = names(setting_lines(texts['.github/pr-gate-review'], strip=True)) \
                if texts['.github/pr-gate-review'] is not None and setting_lines(texts['.github/pr-gate-review'], strip=True) else []
        except (Invalid, TypeError, AttributeError):
            raise SettingFileError('setting file') from None
        checks, checks_source = list(DEFAULT_CHECKS), 'default'
        if self.required_checks is not None:
            checks, checks_source = self.required_checks, 'config'
        elif listed:
            checks, checks_source = listed, 'repository'
        review, review_source = (kinds, 'repository') if kinds else (list(DEFAULT_REVIEW), 'default')
        # The default branch name comes from the repository metadata: a bad one is not a setting-file problem.
        return validate_settings({'default_branch': branch, 'required_checks': checks, 'checks_source': checks_source,
                                  'review': review, 'review_source': review_source})

    def skipped(self, reason):
        coverage = {'status': 'SKIPPED', 'skipped': reason, 'errors': [], 'calls': self.calls,
                    'limits': asdict(self.limits), 'connections': [], 'returned_nodes': 0,
                    'finished_at': now(), 'scope': 'repository metadata only', 'omitted': CLOSED_PR_OMITTED}
        return validate(seal({}, coverage, self.repo))

    def collect(self):
        items, errors, settings = {}, [], None
        PREFIX = self.prefix
        try:
            meta = self.call(self.transport.get, PREFIX, None)
            if meta is None:
                return self.skipped('not_found')
            require(isinstance(meta, dict) and isinstance(meta.get('full_name'), str), 'repository metadata')
            # GitHub matches names without case; the configured spelling must still be the real one.
            require(meta['full_name'] == self.repo, 'repository name mismatch')
            require(type(meta.get('private')) is bool, 'repository visibility')
            # Only PUBLIC repositories are read. A private one is reported as out of scope, not as a failure.
            if meta['private'] is not False or meta.get('visibility') != 'public':
                return self.skipped('private')
            settings = self.settings(meta['default_branch'])
            listing = self.pages(PREFIX + '/issues')
            seen = set()
            for row in listing:
                n = number(row['number'])
                require(n not in seen, 'duplicate issue/PR in pagination')
                seen.add(n)
                kind = 'pr' if 'pull_request' in row else 'issue'
                route = f'{PREFIX}/{"pulls" if kind == "pr" else "issues"}/{n}'
                detail = self.call(self.transport.get, route, None)
                require(detail['number'] == n and detail['html_url'] == source_url(self.repo, kind, n), 'API target mismatch')
                raw = {'detail': detail, 'comments': self.pages(f'{PREFIX}/issues/{n}/comments')}
                require(detail['comments'] == len(raw['comments']), 'comment count changed/partial')
                if kind == 'pr':
                    sha = detail['head']['sha']
                    require(isinstance(sha, str) and re.fullmatch(r'[0-9a-f]{40}', sha), 'invalid head')
                    require(detail['state'] in ('open', 'closed'), 'invalid PR state')
                    # Closed/merged PRs are only shown as "no action"; their review gate is not read (#49).
                    if detail['state'] == 'open':
                        raw.update(checks=self.pages(f'{PREFIX}/commits/{sha}/check-runs', 'check_runs'),
                                   statuses=self.pages(f'{PREFIX}/commits/{sha}/statuses'),
                                   reviews=self.pages(f'{PREFIX}/pulls/{n}/reviews'),
                                   review_comments=self.pages(f'{PREFIX}/pulls/{n}/comments'),
                                   threads=self.connection('threads', n))
                    raw['closing'] = self.connection('closing', n)
                item = {'kind': kind, 'number': n, 'state': 'MERGED' if kind == 'pr' and detail['merged'] else detail['state'].upper(),
                        'title': detail['title'], 'body': detail['body'] or '', 'url': source_url(self.repo, kind, n),
                        'raw': raw, 'hash': digest(raw)}
                items[f'{kind}:{n}'] = item
            # A second inventory catches additions/state changes during the multi-request sweep.
            final = self.pages(PREFIX + '/issues')
            def inventory(rows):
                return sorted((x['number'], x['updated_at'], x['state']) for x in rows)
            require(inventory(listing) == inventory(final), 'inventory changed during collection')
        except SettingFileError:
            # The files were read, but their lines are not usable names.
            errors.append('取得不完全: 既定ブランチの .github/pr-gate-checks / .github/pr-gate-review を読めません。'
                          'ファイルの大きさ（10,000文字まで）・行の長さ（200文字まで）・行数（50まで）・制御文字を確認してください。')
        except (Invalid, KeyError, TypeError, ValueError, AttributeError):
            # Raw error messages may contain remote text or auth diagnostics: never persist them.
            errors.append('取得不完全: schema/権限/rate limit/network/上限/収集中の変化を確認してください。')
        coverage = {'status': 'INCOMPLETE' if errors else 'COMPLETE', 'errors': errors,
                    'calls': self.calls, 'limits': asdict(self.limits), 'connections': self.connections,
                    'returned_nodes': self.nodes, 'finished_at': now(),
                    'scope': 'all issue/PR states; bodies, comments, heads, closing links; '
                             'checks, statuses, reviews, review comments, threads for OPEN PRs only',
                    'omitted': CLOSED_PR_OMITTED}
        snapshot = seal(items, coverage, self.repo, settings)
        # Invalid partial items are not silently emitted as complete.
        try:
            validate(snapshot)
        except (Invalid, KeyError, TypeError, AttributeError):
            coverage['status'] = 'INCOMPLETE'
            coverage['errors'].append('取得した原文のschemaを検証できません。')
            snapshot = seal({}, coverage, self.repo, settings)
        return snapshot
