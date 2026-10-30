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
not found, or an error) or --update could not update the checkout (see the report), 2 for usage errors.
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
from github_work_guide.core import (SKIP_REASONS, Invalid, build_plan, diff, load_run, markdown,  # noqa: E402
                                    safe_text, save_run)

# Present only in the dedicated check checkout (runs/ is not tracked). --update refuses without it.
MARKER = 'runs/.periodic-check-checkout'
# Time for the updated child beyond the sum of the repositories' own time limits.
CHILD_MARGIN_SECONDS = 1800
# -snapshot: the collection alone, kept when writing the full run failed part way.
RUN_NAME = re.compile(r'periodic-\d{8}-\d{4}(?:-snapshot)?\Z')
STAMP = re.compile(r'\d{8}-\d{4}\Z')
WARN_RATIO = 0.8
STALE_DAYS = 14
# Cancelled runs are left out of last_completed in branch_ci, so they never hide or raise a failure.
OK_CONCLUSIONS = ('success', 'skipped', 'neutral', 'stale')  # stale: GitHub retired an old run, no code failed
FORMAT_FALLBACK = '判定できないため簡易版'
# Budget for the format check (up to 2 calls) and the CI read (1 call) after the collection.
AFTER_LIMITS = Limits(calls=5, seconds=120)


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


def previous_run(directory):
    """Newest periodic run of this repository that loads (manifest, hashes, schema) and was complete."""
    names = sorted((p for p in (directory.iterdir() if directory.is_dir() else [])
                    if RUN_NAME.fullmatch(p.name) and not p.is_symlink()), key=lambda p: p.name, reverse=True)
    for path in names:
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
    return {'status': coverage['status'], 'items': len(snapshot['items']), 'calls': coverage.get('calls'),
            'seconds': seconds, 'moved': moved, 'first': not has_previous,
            'acceptance': by_kind.get('acceptance', []), 'completion': by_kind.get('completion', []),
            'open': [(k, c['kind']) for k, c in sorted(candidates.items()) if c['kind'] != 'none'],
            'stale': stale_open(snapshot, now), 'warnings': warnings}


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
        previous_path, previous = previous_run(directory)
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
            plan = build_plan(snapshot) if result['format'] == 'full' else None
            changes = diff(snapshot, previous)
            try:
                result['ci'] = after.branch_ci(branch)
            except (Invalid, KeyError, TypeError, ValueError, AttributeError):
                result['ci_error'] = '既定ブランチの workflow run を読めない（権限・上限・通信を確認）'
            seconds = time.monotonic() - started
            result['analysis'] = analyse(snapshot, plan, changes, seconds, now, collector.limits, previous is not None,
                                         collector.calls + after.calls, collect_seconds)
            if result['ci_error']:
                result['analysis']['warnings'].append('既定ブランチのCIを確認できていない')
            if result['format_source'] == FORMAT_FALLBACK:
                result['analysis']['warnings'].append('形式を判定できず、作業案内（親の検収待ち・完了範囲確認）を作っていない'
                                                      '（上限・権限・通信を確認）')
            note = None if plan else '簡易版（Issueの書式を判定しない）'
            documents.update({'diff.json': changes, 'report.md': markdown(snapshot, changes, plan, None, note)})
            if plan is not None:
                documents['plan.json'] = plan
        save_run(out, documents)
        result['run'] = out.name
    except Exception as error:  # noqa: BLE001 - one repository never stops the others; raw text may hold remote data
        # Only the exception type is kept: its message may carry remote text or auth diagnostics.
        result['stop'] = result['stop'] or (f'この repository の点検中に予期しないエラー（{type(error).__name__}）。'
                                            'ほかの repository は続けた')
        # A collection that finished is still kept, so the time and calls it took are not lost.
        if result['run'] is None and snapshot is not None:
            # A run directory left half written cannot be reused: keep the snapshot next to it.
            target = out if not out.exists() else out.with_name(out.name + '-snapshot')
            try:
                save_run(target, {'snapshot.json': snapshot})
                result['run'] = target.name
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
        lines.append(f'- 既定ブランチ: {safe_text(settings["default_branch"])} / 必須check（{settings["checks_source"]}）: '
                     f'{safe_text(settings["required_checks"])} / 正式レビュー（{settings["review_source"]}）: '
                     f'{safe_text(settings["review"])}')
    if not a:
        return lines + ['']
    limits = Limits(**result['limits'])
    lines += [f'- 形式: {"完全版（作業案内あり）" if result["format"] == "full" else "簡易版"}（{result["format_source"]}）',
              f'- 取得: {a["status"]} / {a["items"]}件 / API呼出 {a["calls"]}回 / {a["seconds"]:.0f}秒'
              f'（上限 {limits.seconds}秒・{limits.calls}回）',
              f'- 前回のrun: {result["previous"] or "なし（初回）"} / 今回のrun: {result["run"]}', '',
              '### 前回からの変化', '']
    if a['first']:
        lines.append('- 前回のrunがないため、差分は次回から')
    elif a['moved']:
        lines += [f'- {key}: {status}' for key, status in a['moved']]
    else:
        lines.append('- 変化なし（取得範囲内）')
    lines += ['', '### 要対応の候補', '']
    lines += [f'- 親の検収待ち: {key}（人の最終検収）' for key, _ in a['acceptance']]
    lines += [f'- 完了範囲確認: {key}（関連PRはMerge済み。Closeは人が判断）' for key, _ in a['completion']]
    lines += [f'- {STALE_DAYS}日以上動いていないOPEN: {key}（最終更新 {safe_text(when)}）' for key, _, when in a['stale']]
    lines += [f'- 警告: {w}' for w in a['warnings']]
    lines += [f'- 警告: 既定ブランチの {safe_text(r["name"])} が {safe_text(r["conclusion"])}（{str(r["head_sha"])[:7]}）'
              for r in ci_problems(result['ci'])]
    if not attention(result):
        lines.append('- なし')
    if result['format'] == 'full':
        lines += ['', '### 案内の対象（OPEN）', '']
        lines += [f'- {key}: {kind}' for key, kind in a['open']] or ['- なし']
    lines += ['', '### 既定ブランチのCI', '']
    if result['ci_error']:
        lines.append(f'- 取得できない: {result["ci_error"]}')
    elif not result['ci']:
        lines.append('- workflow run がない')
    else:
        for r in result['ci']:
            line = f'- {safe_text(r["name"])}: {r["status"]}/{safe_text(r["conclusion"] or "-")} ({str(r["head_sha"])[:7]})'
            done = r.get('last_completed')
            if done and done['created_at'] != r['created_at']:
                line += f' / 最後に終わったrun: {safe_text(done["conclusion"])} ({str(done["head_sha"])[:7]})'
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
             'GitHubへの書き込み・削除・モデルの使用はしていない。', '']
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
            ci = ('取得できない' if r['ci_error'] else '-' if r['ci'] is None else 'runなし' if not r['ci'] else
                  f'失敗 {len(problems)}件' if problems else '問題なし')
            lines.append(f'| {r["repo"]} | {state_label(r)} | {fmt} | {attention(r) if r["analysis"] else "-"} | {ci} |')
        lines.append('')
        for r in results:
            lines += render_repository(r)
    lines += ['## runs/ の容量', '', f'- {size / 1_000_000:.1f} MB（自動で削除しない）', '']
    return '\n'.join(lines) + '\n'


def notify(text):
    if shutil.which('osascript'):
        # The text goes in as an argument, never into the script source.
        run(['osascript', '-e', 'on run argv', '-e', 'display notification (item 1 of argv) with title "GitHub 定期点検"',
             '-e', 'end run', '--', text], timeout=30)


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
    # Nothing new on main: this process already runs the current code, so no child is needed.
    if args.update and not update_error and commit() != old:
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
        written = summary_path.exists()
        # 1 is also what an uncaught exception exits with: a traceback means the child did not finish cleanly.
        if code in (0, 1) and written and 'Traceback (most recent call last)' not in err:
            print(out, end='')  # the child's summary=<path>
            return code
        # Kept for diagnosis next to the report (runs/ is not tracked). It is local output of this program.
        log = summaries / f'{stamp}.child-stderr.txt'
        if not log.exists():
            log.write_text('\n'.join(err.splitlines()[-50:]) + '\n', encoding='utf-8')
        failure = (f'更新後の版（{commit()}）が正しく終わらなかった（終了コード {code}）。checkout は更新済み'
                   f'（更新前 {old}）。エラー出力は {log.name}。手で実行して確かめる')
        if written:
            # The child wrote its report and then failed (killed by the time limit, a crash): say so in it.
            with summary_path.open('a', encoding='utf-8') as stream:
                stream.write(f'\n## 停止\n\n- {failure}\n')
        else:
            with summary_path.open('x', encoding='utf-8') as stream:
                stream.write(render(stamp, [], runs_size(runs), failure))
        print(f'summary={summary_path}')
        # A child that wrote its report has already notified; one more notice only when there was none.
        if args.notify and not written:
            notify(f'停止: 更新後の版が正しく終わらなかった。{summary_path.name}')
        return 1
    results = []
    if not stop:
        now = datetime.now(timezone.utc)
        for target in config['repositories'].values():
            results.append(check_repository(target, runs, stamp, now))
    updated_from = {'unknown': '不明'}.get(args.updated_from, args.updated_from)
    text = render(stamp, results, runs_size(runs), stop, update_error, commit(), updated_from)
    with summary_path.open('x', encoding='utf-8') as stream:
        stream.write(text)
    print(f'summary={summary_path}')
    stopped = [r['repo'] for r in results if r['stop']]
    if args.notify:
        count = sum(attention(r) for r in results)
        notify(f'停止: {stop}' if stop else
               ('checkout を更新できない。' if update_error else '') +
               f'{len(results)}件を点検。停止 {len(stopped)}件、要対応の候補 {count}件。{summary_path.name}')
    return 1 if stop or stopped or update_error else 0


if __name__ == '__main__':
    sys.exit(main())
