#!/usr/bin/env python3
"""Weekly read-only check of every repository in config/github-work-guide.json (#220).

No model, no GitHub writes, no deletion. For each repository, within that repository's own time and
API limits, it collects Issues/PRs, compares them with the previous complete run, and reads the CI of
the default branch. Repositories that follow the ai-development Issue form (format "full") also get the
work guide; the others (format "simple") get only the changes, Issues/PRs left OPEN for 14 days or more,
and the default branch's CI. Everything goes into one report:
runs/periodic-summaries/<YYYYMMDD-HHMM>.md (UTC). Each repository's run is runs/<owner>--<name>/periodic-<stamp>.

Run it from a dedicated check checkout (a detached git worktree of this repository). With --update it
first moves that checkout to origin/main; it refuses when the checkout is on a branch or has tracked
changes, so it never moves someone's working branch.
Exit 0 when every repository was checked or is private, 1 when any repository stopped (incomplete,
not found, or an error) or --update could not update the checkout (see the report), 2 for usage errors,
3 when the check itself crashed (traceback on stderr).
"""
import argparse
import os
from datetime import datetime, timedelta, timezone
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from github_work_guide.collector import Collector, Limits  # noqa: E402
from github_work_guide.config import CONFIG, load_config  # noqa: E402
from github_work_guide.core import (KINDS, SKIP_REASONS, Invalid, build_plan, diff, load_run, markdown,  # noqa: E402
                                    safe_text, save_run, settings_text)

# Present only in the dedicated check checkout (runs/ is not tracked). --update refuses without it.
MARKER = 'runs/.periodic-check-checkout'
# Time for the updated child beyond the sum of the repositories' own time limits.
CHILD_MARGIN_SECONDS = 1800
# Weekly runs. A check that failed after collecting keeps its snapshot as periodic-<stamp>-snapshot for
# inspection; it is never the next baseline, because its changes were not reported.
RUN_NAME = re.compile(r'periodic-\d{8}-\d{4}\Z')
STAMP = re.compile(r'\d{8}-\d{4}\Z')
WARN_RATIO = 0.8
STALE_DAYS = 14
# Cancelled runs are left out of last_completed in branch_ci, so they never hide or raise a failure.
OK_CONCLUSIONS = ('success', 'skipped', 'neutral', 'stale')  # stale: GitHub retired an old run, no code failed
FORMAT_FALLBACK = '判定できないため簡易版'
# Budget for the format check (up to 2 calls) and the CI read (1 call) after the collection.
AFTER_LIMITS = Limits(calls=5, seconds=120)

# Japanese words for the values the report shows (#225). The saved JSON keeps the original values.
COVERAGE_LABELS = {'COMPLETE': '完了', 'INCOMPLETE': '不完全', 'SKIPPED': '対象外'}
CHANGE_LABELS = {'ADDED': '新規', 'CHANGED': '更新あり', 'UNAVAILABLE': '今回は取得できない（削除・解決とは限らない）'}
FORMAT_SOURCE_LABELS = {'repository': 'リポジトリの構成から判定', 'config': '設定ファイルで指定'}
RUN_STATUS_LABELS = {'completed': '完了', 'in_progress': '実行中', 'queued': '待機中', 'waiting': '待機中',
                     'requested': '待機中', 'pending': '待機中'}
CONCLUSION_LABELS = {'success': '成功', 'failure': '失敗', 'skipped': '実行せず（条件外）', 'neutral': '中立',
                     'stale': '古いため打ち切り', 'cancelled': '中止', 'timed_out': '時間切れ',
                     'action_required': '操作待ち', 'startup_failure': '起動失敗'}
# A run started by GitHub itself for a dependency update (Dependabot), not by a push of the project.
DYNAMIC_EVENT = 'dynamic'
ITEM_KEY = re.compile(r'(issue|pr):(\d+)\Z')
DATE = re.compile(r'(\d{4}-\d{2}-\d{2})T')
TITLE_CHARS = 60


def item_label(key):
    """issue:163 -> Issue #163, pr:17 -> PR #17. Keys come from validated snapshots; anything else is escaped."""
    match = ITEM_KEY.fullmatch(key)
    if not match:
        return safe_text(key)
    return f'{"Issue" if match.group(1) == "issue" else "PR"} #{match.group(2)}'


def item_text(key, titles):
    """The number and, when known, the title (remote text, so escaped)."""
    title = titles.get(key)
    if not (isinstance(title, str) and title):
        return item_label(key)
    # A long title would bury the reason; the number leads to the whole title.
    return item_label(key) + ' ' + safe_text(title if len(title) <= TITLE_CHARS else title[:TITLE_CHARS] + '…')


def day(value):
    """The date part of a GitHub time, or the escaped value when it is not one."""
    match = DATE.match(value) if isinstance(value, str) else None
    return match.group(1) if match else safe_text(value)


def word(labels, value):
    """A Japanese word for a known value; an unknown value (new on GitHub) is shown escaped as it is."""
    return labels.get(value) or safe_text(value if value is not None else '-')


def run(args, cwd=None, timeout=300, env=None):
    """Never raises: a timeout or a missing command is a failed result, so the report is still written."""
    try:
        proc = subprocess.run(args, cwd=cwd or ROOT, capture_output=True, text=True, timeout=timeout, env=env)
    except subprocess.TimeoutExpired as error:
        # Keep what the process wrote before it was stopped: it is what explains a hang.
        def text(value):
            return value.decode('utf-8', 'replace') if isinstance(value, bytes) else (value or '')
        return -1, text(error.stdout), text(error.stderr) + f'\ntimeout after {timeout}s'
    except OSError as error:
        return -1, '', type(error).__name__
    return proc.returncode, proc.stdout, proc.stderr


def commit():
    """The commit of the code that runs the check (shown in the report)."""
    code, out, _ = run(['git', 'rev-parse', 'HEAD'], timeout=30)
    return out.strip() if code == 0 and re.fullmatch(r'[0-9a-f]{40}', out.strip()) else '不明'


def update_checkout():
    """Move the dedicated checkout to origin/main. Returns an error text or None."""
    if not (ROOT / MARKER).is_file():
        return f'{MARKER} がない。点検専用の checkout だけを更新する'
    code, out, _ = run(['git', 'symbolic-ref', '-q', 'HEAD'])
    if code not in (0, 1):  # 1 is a detached HEAD; anything else is not a usable git checkout
        return 'git の checkout として読めない（git がない、または repository ではない）'
    if code == 0:
        return f'checkout がブランチ {out.strip()} にある。detached の点検用 checkout だけを更新する'
    # Ignored files (runs/) are not listed; any other untracked or changed file stops the update.
    code, out, _ = run(['git', 'status', '--porcelain', '--untracked-files=normal'])
    if code != 0 or out.strip():
        return 'checkout に変更か未追跡のファイルがある、または git status に失敗した'
    # An explicit refspec: a clone whose remote.origin.fetch does not cover main still gets origin/main updated.
    code, _, _ = run(['git', 'fetch', '--quiet', 'origin', '+refs/heads/main:refs/remotes/origin/main'])
    if code != 0:
        return 'git fetch に失敗した'
    # A commit that is not on main would be left behind by the checkout below.
    code, _, _ = run(['git', 'merge-base', '--is-ancestor', 'HEAD', 'origin/main'])
    if code == 1:
        return 'checkout に origin/main にないコミットがある'
    if code != 0:
        return 'origin/main と比べられない（git merge-base に失敗した）'
    code, _, _ = run(['git', 'checkout', '--quiet', '--detach', 'origin/main'])
    if code != 0:
        return 'git checkout に失敗した'
    return None


def slug(repo):
    return repo.replace('/', '--')


def previous_run(directory, summaries=None):
    """Newest periodic run of this repository that loads (manifest, hashes, schema), was complete and, when
    summaries is given, whose report was written: changes of a run nobody saw must not become the baseline."""
    names = sorted((p for p in (directory.iterdir() if directory.is_dir() else [])
                    if RUN_NAME.fullmatch(p.name) and not p.is_symlink()), key=lambda p: p.name, reverse=True)
    for path in names:
        if summaries is not None and not (summaries / f'{path.name[len("periodic-"):]}.md').is_file():
            continue
        try:
            snapshot = load_run(path)
        except Exception:  # noqa: BLE001 - an unloadable run is skipped, never trusted
            continue
        # An empty (private) or partial run would show every item as ADDED next time.
        if snapshot['coverage']['status'] == 'COMPLETE':
            return path, snapshot
    return None, None


def stale_open(snapshot, now, days=STALE_DAYS):
    rows = []
    for key, item in sorted(snapshot['items'].items()):
        if item['state'] != 'OPEN':
            continue
        updated = item['raw']['detail'].get('updated_at')
        try:
            when = datetime.fromisoformat(updated.replace('Z', '+00:00'))
        except (AttributeError, ValueError):
            when = None
        if when is None or when.tzinfo is None:
            rows.append((key, item['title'], '不明'))
            continue
        if now - when >= timedelta(days=days):
            rows.append((key, item['title'], updated))
    return rows


def warnings_for(coverage, seconds, limits):
    warnings = []
    if seconds is not None and seconds >= limits.seconds * WARN_RATIO:
        warnings.append(f'取得時間 {seconds:.0f}秒が上限{limits.seconds}秒の8割以上')
    if coverage.get('calls', 0) >= limits.calls * WARN_RATIO:
        warnings.append(f'API呼出 {coverage["calls"]}回が上限{limits.calls}回の8割以上')
    return warnings


def analyse(snapshot, plan, changes, seconds, now, limits, has_previous=False, calls=None, collect_seconds=None):
    """Pure summary of one repository's check. seconds / calls: the whole check (collection, format, CI), shown
    in the report. The 80% warnings compare the collection alone (its calls, collect_seconds) with its limits."""
    coverage = dict(snapshot['coverage'])
    warnings = warnings_for(coverage, seconds if collect_seconds is None else collect_seconds, limits)
    if calls is not None:
        coverage['calls'] = calls
    candidates = plan['candidates'] if plan else {}
    by_kind = {}
    for key, c in sorted(candidates.items()):
        by_kind.setdefault(c['kind'], []).append((key, c['label']))
    moved = [(x['target'], x['status']) for x in changes if x['status'] in ('ADDED', 'CHANGED', 'UNAVAILABLE')]
    result = {'status': coverage['status'], 'items': len(snapshot['items']), 'calls': coverage.get('calls'),
              'seconds': seconds, 'moved': moved, 'first': not has_previous,
              'acceptance': by_kind.get('acceptance', []), 'completion': by_kind.get('completion', []),
              'open': [(k, c['kind']) for k, c in sorted(candidates.items()) if c['kind'] != 'none'],
              'stale': stale_open(snapshot, now), 'warnings': warnings}
    # Titles of the Issues/PRs the report names, so a reader sees what each number is (#225).
    named = ({k for k, _ in result['acceptance']} | {k for k, _ in result['completion']}
             | {k for k, _, _ in result['stale']} | {k for k, _ in result['open']} | {k for k, _ in moved})
    result['titles'] = {k: snapshot['items'][k].get('title') for k in sorted(named) if k in snapshot['items']}
    return result


def ci_problems(ci):
    """Workflows whose last finished run on the default branch did not succeed."""
    return [r['last_completed'] for r in ci or []
            if r.get('last_completed') and r['last_completed']['conclusion'] is not None
            and r['last_completed']['conclusion'] not in OK_CONCLUSIONS]


def collector_for(target):
    """One Collector per repository, with that repository's limits. Tests replace this."""
    return Collector(target['repo'], limits=Limits(**target['limits']), required_checks=target['required_checks'])


def check_repository(target, runs, stamp, now):
    """Everything for one repository. Never raises: a failure becomes a stop reason in the result."""
    repo = target['repo']
    result = {'repo': repo, 'stop': None, 'skipped': None, 'format': None, 'format_source': None, 'analysis': None,
              'ci': None, 'ci_error': None, 'settings': None, 'previous': None, 'run': None, 'limits': target['limits']}
    directory = runs / slug(repo)
    out = directory / f'periodic-{stamp}'
    if out.exists():
        result['stop'] = f'{out.name} が既にある。前の結果を今回の結果として読まない'
        return result
    snapshot = None
    try:
        previous_path, previous = previous_run(directory, runs / 'periodic-summaries')
        result['previous'] = previous_path.name if previous_path else None
        collector = collector_for(target)
        started = time.monotonic()
        snapshot = collector.collect()
        collect_seconds = time.monotonic() - started
        status = snapshot['coverage']['status']
        result['settings'] = snapshot['settings']
        documents = {'snapshot.json': snapshot}
        if status == 'SKIPPED':
            result['skipped'] = snapshot['coverage']['skipped']
            documents['report.md'] = markdown(snapshot, diff(snapshot))
            if result['skipped'] != 'private':
                # 404 with the owner's gh: most likely a misspelled entry in the config.
                result['stop'] = SKIP_REASONS[result['skipped']]
        elif status != 'COMPLETE':
            # A partial snapshot is saved for inspection, but not compared or planned.
            documents['report.md'] = markdown(snapshot, [])
            result['stop'] = '取得が不完全（' + safe_text(snapshot['coverage']['errors']) + '）。再試行はしない'
        else:
            branch = snapshot['settings']['default_branch']
            # The format check and the CI read have their own small budget, so a collection that used its
            # limits to the end still gets them.
            after = Collector(repo, collector.transport, AFTER_LIMITS)
            if target['format'] == 'auto':
                try:
                    result['format'], result['format_source'] = after.repository_format(branch), 'repository'
                except (Invalid, KeyError, TypeError, ValueError, AttributeError):
                    # The collection is complete and kept; without the format it is read the simple way.
                    result['format'], result['format_source'] = 'simple', FORMAT_FALLBACK
            else:
                result['format'], result['format_source'] = target['format'], 'config'
            # Simple: the Issue form is not judged, so no work guide is made.
            # The CI is read before planning, so a slow plan does not use up the small budget.
            try:
                result['ci'] = after.branch_ci(branch)
            except (Invalid, KeyError, TypeError, ValueError, AttributeError):
                result['ci_error'] = '既定ブランチの workflow run を読めない（権限・上限・通信を確認）'
            plan = build_plan(snapshot) if result['format'] == 'full' else None
            changes = diff(snapshot, previous)
            seconds = time.monotonic() - started
            result['analysis'] = analyse(snapshot, plan, changes, seconds, now, collector.limits, previous is not None,
                                         collector.calls, collect_seconds)
            result['analysis']['after_calls'] = after.calls
            if result['ci_error']:
                result['analysis']['warnings'].append('既定ブランチのCIを確認できていない')
            if result['format_source'] == FORMAT_FALLBACK:
                result['analysis']['warnings'].append('形式を判定できず、作業案内（親の検収待ち・完了範囲確認）を作っていない'
                                                      '（上限・権限・通信を確認）')
            note = None if plan else '簡易版（Issueの書式を判定しない）'
            documents.update({'diff.json': changes,
                              'report.md': markdown(snapshot, changes, plan, None, note, plan is not None)})
            if plan is not None:
                documents['plan.json'] = plan
        save_run(out, documents)
        result['run'] = out.name
    except Exception as error:  # noqa: BLE001 - one repository never stops the others; raw text may hold remote data
        # Only the exception type is kept: its message may carry remote text or auth diagnostics.
        unexpected = f'この repository の点検中に予期しないエラー（{type(error).__name__}）。ほかの repository は続けた'
        result['stop'] = f'{result["stop"]}。{unexpected}' if result['stop'] else unexpected
        # A collection that finished is still kept, so the time and calls it took are not lost.
        if result['run'] is None and snapshot is not None:
            # Kept for inspection under its own name (not a baseline: its changes were not reported).
            kept = out.with_name(out.name + '-snapshot')
            try:
                save_run(kept, {'snapshot.json': snapshot})
                result['run'] = kept.name
            except Exception:  # noqa: BLE001
                pass
    return result


def attention(result):
    """Things to look at. A CI that could not be read is one (its warning is in the analysis)."""
    a = result['analysis']
    count = len(ci_problems(result['ci']))
    if a:
        # One Issue that is both a candidate and stale is one thing to look at.
        keys = {k for k, _ in a['acceptance']} | {k for k, _ in a['completion']} | {k for k, _, _ in a['stale']}
        count += len(keys) + len(a['warnings'])
    return count


def attention_lines(result):
    """The things to look at, one line each (attention() counts the same things). An Issue that is both a
    candidate and stale is one line with both reasons."""
    a, lines = result['analysis'], []
    if a:
        titles, reasons = a.get('titles', {}), {}
        for key, _ in a['acceptance']:
            reasons.setdefault(key, []).append('親の検収待ち（人が最終検収する）')
        for key, _ in a['completion']:
            reasons.setdefault(key, []).append('完了範囲の確認（関連PRはマージ済み。Closeは人が判断）')
        for key, _, when in a['stale']:
            reasons.setdefault(key, []).append(
                f'{STALE_DAYS}日以上動いていない（最終更新 {"不明" if when == "不明" else day(when)}）')
        lines += [f'{item_text(key, titles)}: {"、".join(r)}' for key, r in reasons.items()]
        lines += [f'警告: {w}' for w in a['warnings']]
    for r in ci_problems(result['ci']):
        line = f'警告: 既定ブランチの {safe_text(r["name"])} が{word(CONCLUSION_LABELS, r["conclusion"])}（{str(r["head_sha"])[:7]}）'
        if r.get('event') == DYNAMIC_EVENT:
            line += '。GitHub が自動で動かした実行（依存関係の自動更新など）'
        lines.append(line)
    return lines


def default_settings(result):
    s = result['settings']
    return bool(s) and s['checks_source'] == 'default' and s['review_source'] == 'default'


def names(repos):
    return '、'.join(repos)


def notices(results):
    """Notes made by fixed rules from what was read (no model): things that change how to read the report."""
    lines = []
    checked = [r for r in results if r['analysis']]
    stopped = [r['repo'] for r in results if r['stop']]
    if stopped:
        lines.append(f'点検が止まったリポジトリがある: {names(stopped)}。各節の「停止」を確認する')
    private = [r['repo'] for r in results if r['skipped'] == 'private']
    if private:
        lines.append(f'非公開のため読んでいない: {names(private)}。公開に切り替えると次回から点検する')
    first = [r['repo'] for r in checked if r['analysis']['first']]
    if first:
        lines.append(f'前回の記録がないため、前回からの変化は次回から出る: '
                     + ('点検した全リポジトリ' if len(first) == len(checked) else names(first)))
    simple_default = [r['repo'] for r in results if default_settings(r) and r['format'] == 'simple']
    if simple_default:
        lines.append(f'.github/pr-gate-review がない: {names(simple_default)}。必須チェックと正式レビューは'
                     '簡易版では使わないので、結果に影響しない')
    full_default = [r['repo'] for r in results if default_settings(r) and r['format'] == 'full']
    if full_default:
        lines.append(f'.github/pr-gate-review がない完全版: {names(full_default)}。作業案内は既定値の必須チェック'
                     'と正式レビューで読んでいる。実際の CI の名前と違うと、PR の判定がずれることがある')
    no_runs = [r['repo'] for r in checked if r['ci'] == [] and not r['ci_error']]
    if no_runs:
        lines.append(f'既定ブランチに CI の実行記録がない: {names(no_runs)}。CI がないか、最近動いていないか、'
                     '新しい実行がすべて PR のもの')
    for r in results:
        dynamic = [run for run in ci_problems(r['ci']) if run.get('event') == DYNAMIC_EVENT]
        if dynamic:
            lines.append(f'{r["repo"]} の CI の失敗 {len(dynamic)}件は、GitHub が自動で動かした実行（依存関係の自動更新など）'
                         'で、push で動く通常の CI とは別')
    for r in checked:
        stale = r['analysis']['stale']
        # Only real dates: an escaped odd value would sort before them and be shown as the oldest.
        dates = sorted(m.group(1) for _, _, when in stale if isinstance(when, str) and (m := DATE.match(when)))
        if len(stale) >= 3:
            lines.append(f'{r["repo"]} は、{STALE_DAYS}日以上動いていない OPEN が{len(stale)}件ある'
                         + (f'（いちばん古い最終更新 {dates[0]}）' if dates else '') + '。続けるか閉じるかをまとめて決めるとよい')
    return lines or ['なし']


def summary_lines(results):
    """Every repository's things to look at, gathered at the top of the report."""
    lines = []
    for r in results:
        found = attention_lines(r)
        if r['stop'] or found:
            # A nested list, not a heading: "## <repo>" is the repository's own section below. The count is the
            # one in the table (a stop is shown, not counted).
            lines.append(f'- {r["repo"]}（{"停止。" if r["stop"] else ""}要対応 {len(found)}件）')
            lines += ([f'  - 停止: {r["stop"]}'] if r['stop'] else []) + [f'  - {x}' for x in found]
    return (lines or ['- なし']) + ['']


def state_label(result):
    if result['skipped'] == 'private':
        return '対象外（非公開）'
    if result['stop']:
        return '停止'
    return '完了'


def render_repository(result):
    repo, a = result['repo'], result['analysis']
    lines = [f'## {repo}', '']
    if result['skipped']:
        lines.append(f'- {SKIP_REASONS[result["skipped"]]}。Issue/PRは読んでいない。')
        if result['skipped'] != 'private':
            lines.append('- 設定ファイルの名前が正しいか確認する（利用者の gh なら非公開のリポジトリも見える）。')
        return lines + ['']
    if result['stop']:
        lines += [f'- 停止: {result["stop"]}']
    settings = result['settings']
    if settings:
        # Unused only when the simple format was decided; a stopped check does not know the format yet.
        lines.append(f'- {settings_text(settings, result["format"] != "simple")}')
    if not a:
        return lines + ['']
    limits = Limits(**result['limits'])
    source = FORMAT_SOURCE_LABELS.get(result['format_source'], result['format_source'])
    titles = a.get('titles', {})
    lines += [f'- 形式: {"完全版（作業案内あり）" if result["format"] == "full" else "簡易版"}（{source}）',
              f'- 取得: {word(COVERAGE_LABELS, a["status"])} / {a["items"]}件 / API呼出 {a["calls"]}回'
              f'（上限 {limits.calls}回）＋形式の判定とCIで{a.get("after_calls", 0)}回（別枠） / 全体 {a["seconds"]:.0f}秒'
              f'（取得の上限 {limits.seconds}秒）',
              f'- 前回の記録: {result["previous"] or "なし（初回）"} / 今回の記録: {result["run"]}', '',
              '### 前回からの変化', '']
    if a['first']:
        lines.append('- 前回の記録がないため、変化は次回から')
    elif a['moved']:
        lines += [f'- {item_text(key, titles)}: {word(CHANGE_LABELS, status)}' for key, status in a['moved']]
    else:
        lines.append('- 変化なし（取得した範囲で）')
    lines += ['', '### 要対応の候補', '']
    lines += [f'- {x}' for x in attention_lines(result)] or ['- なし']
    if result['format'] == 'full':
        lines += ['', '### 案内の対象（未完了のIssue/PR）', '']
        lines += [f'- {item_text(key, titles)}: {KINDS[kind][0] if kind in KINDS else safe_text(kind)}'
                  for key, kind in a['open']] or ['- なし']
    lines += ['', '### 既定ブランチのCI', '']
    if result['ci_error']:
        lines.append(f'- 取得できない: {result["ci_error"]}')
    elif not result['ci']:
        lines.append('- 実行記録がない')
    else:
        for r in result['ci']:
            state = (word(CONCLUSION_LABELS, r['conclusion']) if r['status'] == 'completed'
                     else word(RUN_STATUS_LABELS, r['status']))
            line = f'- {safe_text(r["name"])}: {state}（{str(r["head_sha"])[:7]}）'
            done = r.get('last_completed')
            if done and done['created_at'] != r['created_at']:
                line += f' / 最後に終わった実行: {word(CONCLUSION_LABELS, done["conclusion"])}（{str(done["head_sha"])[:7]}）'
            lines.append(line)
    return lines + ['']


def runs_size(runs):
    total = 0
    for path in runs.rglob('*'):
        if path.is_file() and not path.is_symlink():
            total += path.stat().st_size
    return total


def render(stamp, results, size, stop=None, update_error=None, commit=None, updated_from=None):
    lines = [f'# 定期点検 {stamp}（UTC）', '',
             '設定ファイル（config/github-work-guide.json）の全リポジトリを読み、報告するだけ（#220）。'
             'GitHubへの書き込み・削除・モデルの使用はしていない。'
             '「要対応のまとめ」と「気づいた点」も、読んだデータから決まった規則で作っている。', '']
    if commit:
        lines += [f'点検したコード: {commit}' + (f'（{updated_from} から更新した）' if updated_from else ''), '']
    if stop:
        lines += ['## 停止', '', f'- {stop}', '']
    if update_error:
        lines += ['## checkout の更新', '', f'- 更新しなかった: {update_error}。今の版で点検した', '']
    if results:
        lines += ['## 一覧', '', '| リポジトリ | 状態 | 形式 | 要対応 | 既定ブランチのCI |', '| --- | --- | --- | --- | --- |']
        for r in results:
            fmt = {'full': '完全版', 'simple': '簡易版'}.get(r['format'], '-')
            problems = ci_problems(r['ci'])
            ci = ('取得できない' if r['ci_error'] else '-' if r['ci'] is None else '実行記録なし' if not r['ci'] else
                  f'失敗 {len(problems)}件' if problems else '問題なし')
            lines.append(f'| {r["repo"]} | {state_label(r)} | {fmt} | {attention(r) if r["analysis"] else "-"} | {ci} |')
        lines += ['', '## 要対応のまとめ', ''] + summary_lines(results)
        lines += ['## 気づいた点', ''] + [f'- {x}' for x in notices(results)] + ['']
        for r in results:
            lines += render_repository(r)
    lines += ['## 記録（runs/）の容量', '', f'- {size / 1_000_000:.1f} MB（自動で削除しない）', '']
    return '\n'.join(lines) + '\n'


# The browser page made from the report (#229). The report's remote text is already escaped by safe_text, so
# only < and > are escaped here (an entity such as &lt; stays as it is); no tag can come from the report.
PAGE_STYLE = """
:root { color-scheme: light dark; --fg: #1f2328; --bg: #ffffff; --muted: #59636e; --line: #d1d9e0; --head: #f6f8fa; }
@media (prefers-color-scheme: dark) { :root { --fg: #e6edf3; --bg: #0d1117; --muted: #9198a1; --line: #3d444d; --head: #151b23; } }
body { margin: 0 auto; max-width: 980px; padding: 24px 16px 48px; background: var(--bg); color: var(--fg);
       font: 15px/1.7 -apple-system, BlinkMacSystemFont, "Hiragino Sans", "Hiragino Kaku Gothic ProN", sans-serif; }
h1 { font-size: 1.6em; border-bottom: 1px solid var(--line); padding-bottom: .3em; }
h2 { font-size: 1.3em; margin-top: 2em; border-bottom: 1px solid var(--line); padding-bottom: .2em; }
h3 { font-size: 1.05em; margin-top: 1.5em; }
p { color: var(--muted); }
ul { padding-left: 1.5em; } li { margin: .2em 0; }
.table { overflow-x: auto; }
table { border-collapse: collapse; } th, td { border: 1px solid var(--line); padding: 6px 12px; text-align: left; }
th { background: var(--head); }
"""
TABLE_RULE = re.compile(r'\|(\s*-+\s*\|)+\Z')
LIST_ITEM = re.compile(r'( *)- (.*)\Z')


def inline(text):
    return text.replace('<', '&lt;').replace('>', '&gt;')


def to_html(report):
    """The report's own Markdown (headings, paragraphs, tables, lists two levels deep) as one page."""
    body, title, depth, rows = [], '定期点検', 0, []

    def close_lists():
        nonlocal depth
        body.extend(['</li></ul>'] * depth)
        depth = 0

    def close_table():
        if rows:
            head, *rest = rows
            body.append('<div class="table"><table><thead><tr>' + ''.join(f'<th>{c}</th>' for c in head) + '</tr></thead><tbody>'
                        + ''.join('<tr>' + ''.join(f'<td>{c}</td>' for c in r) + '</tr>' for r in rest) + '</tbody></table></div>')
            rows.clear()

    for line in report.splitlines():
        item = LIST_ITEM.match(line)
        if line.startswith('|'):
            close_lists()
            if not TABLE_RULE.match(line.strip()):
                rows.append([inline(c.strip()) for c in line.strip().strip('|').split('|')])
            continue
        close_table()
        if item:
            level = min(len(item.group(1)) // 2, 1) + 1
            text = inline(item.group(2))
            if depth < level:
                # A nested item with no item above it still opens (an empty) outer item, so every </li> has one.
                body.append('<ul><li>' * (level - depth - 1) + f'<ul><li>{text}')
                depth = level
            else:
                body.extend(['</li></ul>'] * (depth - level))
                depth = level
                body.append(f'</li><li>{text}')
            continue
        close_lists()
        heading = re.match(r'(#{1,3}) (.*)\Z', line)
        if heading:
            n = len(heading.group(1))
            if n == 1:
                title = heading.group(2)
            body.append(f'<h{n}>{inline(heading.group(2))}</h{n}>')
        elif line.strip():
            body.append(f'<p>{inline(line)}</p>')
    close_lists()
    close_table()
    # No script and nothing loaded from outside: the page only shows the report.
    return ('<!doctype html>\n<html lang="ja"><head><meta charset="utf-8">'
            '<meta http-equiv="Content-Security-Policy" content="default-src \'none\'; style-src \'unsafe-inline\'">'
            '<meta name="viewport" content="width=device-width, initial-scale=1">'
            f'<title>{inline(title)}</title><style>{PAGE_STYLE}</style></head>\n<body>\n'
            + '\n'.join(body) + '\n</body></html>\n')


def write_html(report):
    """<report>.html next to the report. Never raises: the Markdown report is what counts. Returns the page or None."""
    try:
        page = report.with_suffix('.html')
        page.write_text(to_html(report.read_text(encoding='utf-8')), encoding='utf-8')
        return page
    except (OSError, UnicodeError, ValueError):
        return None


# Seconds the "open the report" window waits for a click before it closes itself.
DIALOG_SECONDS = 24 * 3600
OPEN_BUTTON = '報告書を開く'
# The tests replace it with a name that does not exist, so they never show anything on the Mac (#231).
OSASCRIPT = 'osascript'


def notify(text, report=None):
    if not shutil.which(OSASCRIPT):
        return
    # The text and the path go in as arguments, never into the script source.
    run([OSASCRIPT, '-e', 'on run argv', '-e', 'display notification (item 1 of argv) with title "GitHub 定期点検"',
         '-e', 'end run', '--', text], timeout=30)
    if report is None:
        return
    # A window with a button that opens the report (#227): a click on a notification from osascript cannot.
    # It is started on its own and not waited for, so a check never hangs (or hits the --update child's time
    # limit) while nobody is at the Mac; it closes itself after DIALOG_SECONDS.
    script = ['on run argv',
              f'set answer to display dialog (item 1 of argv) with title "GitHub 定期点検" buttons {{"閉じる", "{OPEN_BUTTON}"}} '
              f'default button "{OPEN_BUTTON}" giving up after {DIALOG_SECONDS}',
              f'if button returned of answer is "{OPEN_BUTTON}" then do shell script "open " & quoted form of (item 2 of argv)',
              'end run']
    args = [OSASCRIPT] + [x for line in script for x in ('-e', line)] + ['--', text, str(report)]
    try:
        subprocess.Popen(args, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)
    except OSError:
        pass  # the banner above was shown; the report is still written and its path printed


def main(argv=None):
    # No abbreviations: options are spelled out, so a typo is an error rather than another option.
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0], allow_abbrev=False)
    parser.add_argument('--update', action='store_true', help='move this detached check checkout to origin/main first')
    parser.add_argument('--notify', action='store_true', help='show a macOS notification with the result')
    parser.add_argument('--config', type=Path, default=CONFIG, help='target repositories')
    parser.add_argument('--runs', type=Path, default=ROOT / 'runs', help='runs directory (default: runs/ of this checkout)')
    # Given only by the process that updated the checkout, to the process it starts (shown in the report).
    parser.add_argument('--updated-from', help=argparse.SUPPRESS)
    parser.add_argument('--stamp', help=argparse.SUPPRESS)  # the updating parent's report name, for its child
    args = parser.parse_args(argv)
    if args.updated_from is not None and not re.fullmatch(r'[0-9a-f]{40}|unknown', args.updated_from):
        print('invalid --updated-from', file=sys.stderr)
        return 2
    if args.stamp is not None and not STAMP.fullmatch(args.stamp):
        print('invalid --stamp', file=sys.stderr)
        return 2
    # The updated child runs with cwd=ROOT, so every path it gets is absolute.
    args.runs, args.config = args.runs.resolve(), args.config.resolve()
    runs = args.runs
    if runs.name != 'runs':
        print('--runs must be a directory named runs', file=sys.stderr)
        return 2
    # UTC: a local stamp could repeat or go backwards when daylight saving time ends.
    stamp = args.stamp or datetime.now(timezone.utc).strftime('%Y%m%d-%H%M')
    summaries = runs / 'periodic-summaries'
    summaries.mkdir(parents=True, exist_ok=True)
    summary_path = summaries / f'{stamp}.md'
    if summary_path.exists():
        print(f'summary already exists: {summary_path}', file=sys.stderr)
        return 2
    stop = config = None
    try:
        config = load_config(args.config)
    except (Invalid, OSError, KeyError, TypeError, ValueError):
        stop = '設定ファイルを読めない（config/github-work-guide.json を確認）'
    # An update problem is reported, but the repositories are still checked with the current code.
    old = commit() if args.update else None
    update_error = update_checkout() if args.update else None
    # Nothing new on main: this process already runs the current code, so no child is needed. When the
    # commit cannot be read, a child is started anyway (it may be new code).
    new = commit() if args.update and not update_error else None
    if args.update and not update_error and (new != old or new == '不明'):
        # The modules loaded above are last week's: the check runs in a new process on the updated checkout.
        # It is a child, not an exec, so a new version that fails to start still leaves a report behind.
        # The child writes the report under this process's name (--stamp), so a check started by someone
        # else at the same time is never mistaken for it.
        child = [sys.executable, '-I', '-B', str(ROOT / 'scripts/periodic_check.py'), '--config', str(args.config),
                 '--runs', str(runs), '--updated-from', old if old != '不明' else 'unknown', '--stamp', stamp]
        if args.notify:
            child.append('--notify')
        # The updated config decides how long the updated code may take (new repositories, raised limits).
        try:
            updated = load_config(args.config)
            seconds = sum(t['limits'].get('seconds', Limits().seconds) + AFTER_LIMITS.seconds
                          for t in updated['repositories'].values())
        except (Invalid, OSError, KeyError, TypeError, ValueError):
            seconds = 6 * 3600  # this (old) code cannot read the new config; the child still has its own limits
        code, out, err = run(child, timeout=seconds + CHILD_MARGIN_SECONDS)
        # 1 is also what an uncaught exception exits with: a traceback means the child did not finish cleanly.
        if code in (0, 1) and summary_path.exists() and 'Traceback (most recent call last)' not in err:
            print(out, end='')  # the child's summary=<path>
            return code
        # Kept for diagnosis next to the report (runs/ is not tracked). It is local output of this program.
        log = summaries / f'{stamp}.child-stderr.txt'
        if not log.exists():
            log.write_text('\n'.join(err.splitlines()[-50:]) + '\n', encoding='utf-8')
        failure = (f'更新後の版（{commit()}）が正しく終わらなかった（終了コード {code}）。checkout は更新済み'
                   f'（更新前 {old}）。エラー出力は {log.name}。手で実行して確かめる')
        # Only a report naming the commit this check was updated from is the child's; a report of the same
        # minute without it was written by another check and is left alone.
        mark = f'（{old} から更新した）'
        written = (old != '不明' and summary_path.exists()
                   and mark in summary_path.read_text(encoding='utf-8', errors='replace'))
        if written:
            # The child wrote its report and then failed (killed by the time limit, a crash): say so in it.
            with summary_path.open('a', encoding='utf-8') as stream:
                stream.write(f'\n## 停止\n\n- {failure}\n')
        else:
            # Never under <stamp>.md: that name would make the child's unreported runs next week's baseline,
            # and it may be another check's report of the same minute.
            summary_path = summaries / f'{stamp}-update-failure.md'
            with summary_path.open('x', encoding='utf-8') as stream:
                stream.write(render(stamp, [], runs_size(runs), failure))
        print(f'summary={summary_path}')
        # Made again: the stop was added to the child's report after the child made its page.
        page = write_html(summary_path)
        # A failed child may have stopped before its own notice, so this one is always sent.
        if args.notify:
            notify(f'停止: 更新後の版が正しく終わらなかった。{summary_path.name}', page or summary_path)
        return 1
    results = []
    if not stop:
        now = datetime.now(timezone.utc)
        for target in config['repositories'].values():
            results.append(check_repository(target, runs, stamp, now))
    updated_from = {'unknown': '不明'}.get(args.updated_from, args.updated_from)
    stopped = [r['repo'] for r in results if r['stop']]
    text = render(stamp, results, runs_size(runs), stop, update_error, commit(), updated_from)
    try:
        with summary_path.open('x', encoding='utf-8') as stream:
            stream.write(text)
    except FileExistsError:
        # Another check wrote this minute's report meanwhile. Keep both; this week's runs are then not a
        # baseline (their <stamp>.md is the other check's), which is the safe side.
        summary_path = summaries / f'{stamp}-conflict.md'
        with summary_path.open('x', encoding='utf-8') as stream:
            stream.write(text)
        stopped.append('report name')
    print(f'summary={summary_path}')
    page = write_html(summary_path)
    if args.notify:
        count = sum(attention(r) for r in results)
        notify(f'停止: {stop}' if stop else
               ('checkout を更新できない。' if update_error else '') +
               f'{len(results)}件を点検。停止 {len(stopped)}件、要対応の候補 {count}件。{summary_path.name}', page or summary_path)
    return 1 if stop or stopped or update_error else 0


CRASHED = 3  # an uncaught exception, told apart from 1 (a repository stopped)


def entry():
    try:
        return main()
    except Exception:  # noqa: BLE001 - the traceback goes to stderr; the exit code says it was a crash
        import traceback
        traceback.print_exc()
        return CRASHED


if __name__ == '__main__':
    sys.exit(entry())
