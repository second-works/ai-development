"""#220: scripts/periodic_check.py, the weekly check of every configured repository.
No network and no model: synthetic transports, temporary runs/ and a temporary git repository."""
from datetime import datetime, timezone
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from support import REPO, ROOT  # noqa: F401
from github_work_guide.collector import Collector, Limits
from github_work_guide.core import build_plan, load_run, save_run  # noqa: F401
from support import seal
from test_github_work_guide import SHA, Fake, item as gw_item, snapshot as gw_snapshot
from test_multi_repo import OTHER, OtherFake

spec = importlib.util.spec_from_file_location('periodic_check', ROOT / 'scripts/periodic_check.py')
pc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pc)

NOW = datetime(2026, 10, 30, tzinfo=timezone.utc)
PRIVATE = 'second-works/private-repo'
LIMITS = Limits()


def item(n, state='OPEN', updated='2026-10-29T00:00:00Z', title=None):
    return {'kind': 'issue', 'number': n, 'state': state, 'title': title or f'Issue {n}',
            'raw': {'detail': {'updated_at': updated}}}


def snapshot(items, calls=120, status='COMPLETE'):
    return {'items': {f'issue:{i["number"]}': i for i in items}, 'coverage': {'status': status, 'calls': calls}}


def plan(kinds):
    return {'candidates': {k: {'kind': v, 'label': v} for k, v in kinds.items()}}


class AnalyseTests(unittest.TestCase):
    def test_kinds_changes_and_stale(self):
        snap = snapshot([item(1), item(2, updated='2026-10-01T00:00:00Z'), item(3, state='CLOSED', updated='2026-01-01T00:00:00Z')])
        result = pc.analyse(snap, plan({'issue:1': 'acceptance', 'issue:2': 'completion', 'issue:3': 'none'}),
                            [{'target': 'issue:1', 'status': 'CHANGED'}, {'target': 'issue:2', 'status': 'UNCHANGED'}],
                            60.0, NOW, LIMITS, True)
        self.assertEqual(result['acceptance'], [('issue:1', 'acceptance')])
        self.assertEqual(result['completion'], [('issue:2', 'completion')])
        self.assertEqual([k for k, _, _ in result['stale']], ['issue:2'])  # closed items are not stale
        self.assertEqual(result['moved'], [('issue:1', 'CHANGED')])
        self.assertFalse(result['first'])
        self.assertEqual(result['warnings'], [])

    def test_simple_has_no_plan_but_keeps_changes_and_stale(self):
        snap = snapshot([item(1, updated='2026-10-01T00:00:00Z')])
        result = pc.analyse(snap, None, [{'target': 'issue:1', 'status': 'ADDED'}], 5.0, NOW, LIMITS, True)
        self.assertEqual((result['acceptance'], result['completion'], result['open']), ([], [], []))
        self.assertEqual(result['moved'], [('issue:1', 'ADDED')])
        self.assertEqual(len(result['stale']), 1)

    def test_limits_warn_at_eighty_percent_of_this_repository(self):
        result = pc.analyse(snapshot([item(1)], calls=400), plan({}), [], 144.0, NOW, LIMITS)
        self.assertEqual(len(result['warnings']), 2)
        result = pc.analyse(snapshot([item(1)], calls=399), plan({}), [], 143.0, NOW, LIMITS)
        self.assertEqual(result['warnings'], [])
        big = Limits(calls=2000, seconds=900)
        self.assertEqual(pc.analyse(snapshot([item(1)], calls=400), plan({}), [], 144.0, NOW, big)['warnings'], [])

    def test_unknown_or_naive_update_time_is_reported(self):
        for updated in (None, '2026-01-01T00:00:00'):
            result = pc.analyse(snapshot([item(1, updated=updated)]), plan({}), [], 1.0, NOW, LIMITS)
            self.assertEqual(result['stale'][0][2], '不明')


class PreviousRunTests(unittest.TestCase):
    def save(self, directory, name, value=None):
        value = value or gw_snapshot(gw_item(7))
        save_run(directory / name, {'snapshot.json': value})
        return directory / name

    def test_newest_complete_loadable_periodic_run(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp).resolve() / 'runs' / 'second-works--x'
            older = self.save(directory, 'periodic-20261023-0900')
            newest = self.save(directory, 'periodic-20261030-0900')
            self.save(directory, 'wg-20261101-0900')  # not a periodic run
            (directory / 'periodic-20261102-0900').mkdir()  # interrupted: no manifest
            base = gw_snapshot(gw_item(7))
            self.save(directory, 'periodic-20261103-0900', seal({}, dict(base['coverage'], status='INCOMPLETE', errors=['x'])))
            self.assertEqual(pc.previous_run(directory)[0], newest)
            snap = newest / 'snapshot.json'
            snap.write_text(snap.read_text().replace('Synthetic', 'Altered', 1))
            self.assertEqual(pc.previous_run(directory)[0], older)

    def test_no_previous(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(pc.previous_run(Path(tmp)), (None, None))
            self.assertEqual(pc.previous_run(Path(tmp) / 'missing'), (None, None))


class SimpleFake(OtherFake):
    """A repository without the lightweight template, on default branch trunk, whose CI has failed."""

    def __init__(self):
        super().__init__()
        self.present = set()
        self.workflow_runs = [
            {'name': 'CI', 'status': 'completed', 'conclusion': 'failure', 'head_sha': SHA, 'event': 'push',
             'created_at': '2026-10-29T00:00:00Z'},
            {'name': 'CI', 'status': 'completed', 'conclusion': 'success', 'head_sha': 'b' * 40, 'event': 'push',
             'created_at': '2026-10-28T00:00:00Z'}]


class PrivateFake(Fake):
    """Only the repository metadata answers: it says private, so nothing else may be read."""

    def get(self, path, page, timeout):
        assert path == f'repos/{PRIVATE}', path
        return {'full_name': PRIVATE, 'private': True, 'visibility': 'private', 'default_branch': 'main'}


def config_file(tmp, rows):
    path = Path(tmp) / 'config.json'
    path.write_text(json.dumps({'version': 1, 'owner': 'second-works', 'repositories': rows}), encoding='utf-8')
    return path


class CheckHelper:
    """The whole run over several repositories, with each repository's own synthetic GitHub."""

    def run_check(self, tmp, rows, fakes):
        runs = Path(tmp).resolve() / 'runs'
        def make(target):
            return Collector(target['repo'], fakes[target['repo']](), Limits(**target['limits']), target['required_checks'])
        with patch.object(pc, 'collector_for', make):
            code = pc.main(['--config', str(config_file(tmp, rows)), '--runs', str(runs)])
        summaries = sorted((runs / 'periodic-summaries').iterdir())
        return code, summaries[-1].read_text(encoding='utf-8'), runs


class CheckTests(CheckHelper, unittest.TestCase):
    def test_full_simple_and_private_in_one_report(self):
        rows = [{'name': 'hermes-self-improvement'}, {'name': 'other-repo'}, {'name': 'private-repo'}]
        fakes = {REPO: Fake, OTHER: SimpleFake, PRIVATE: PrivateFake}
        with tempfile.TemporaryDirectory() as tmp:
            code, text, runs = self.run_check(tmp, rows, fakes)
            self.assertEqual(code, 0)  # a private repository is not a failure
            for repo in (REPO, OTHER, PRIVATE):
                self.assertIn(f'## {repo}', text)
            self.assertIn(f'| {REPO} | 完了 | 完全版 |', text)
            self.assertIn(f'| {OTHER} | 完了 | 簡易版 |', text)
            self.assertIn(f'| {PRIVATE} | 対象外（非公開） | - |', text)
            self.assertIn('非公開のため対象外', text)
            full, simple = text.split(f'## {OTHER}')[0], text.split(f'## {OTHER}')[1].split(f'## {PRIVATE}')[0]
            self.assertIn('### 案内の対象（OPEN）', full)
            self.assertNotIn('### 案内の対象（OPEN）', simple)
            self.assertIn('簡易版（repository）', simple)
            # Only the latest run of each workflow, on the repository's own default branch.
            self.assertIn('- "CI": completed/"failure"', simple)
            self.assertIn('警告: 既定ブランチの "CI" が "failure"', simple)
            self.assertIn('既定ブランチ: "trunk"', simple)
            self.assertIn('GitHubへの書き込み・削除・モデルの使用はしていない', text)
            full_run = next((runs / 'second-works--hermes-self-improvement').iterdir())
            simple_run = next((runs / 'second-works--other-repo').iterdir())
            self.assertTrue((full_run / 'plan.json').is_file())
            self.assertFalse((simple_run / 'plan.json').exists())
            self.assertEqual(load_run(simple_run)['repo'], OTHER)
            self.assertEqual(load_run(next((runs / 'second-works--private-repo').iterdir()))['coverage']['skipped'], 'private')

    def test_second_run_compares_with_the_previous_complete_run(self):
        rows = [{'name': 'other-repo'}]
        with tempfile.TemporaryDirectory() as tmp:
            with patch.object(pc, 'datetime', wraps=datetime) as clock:
                clock.now.side_effect = lambda tz=None: datetime(2026, 10, 23, 9, 0, tzinfo=tz)
                self.assertEqual(self.run_check(tmp, rows, {OTHER: SimpleFake})[0], 0)
                clock.now.side_effect = lambda tz=None: datetime(2026, 10, 30, 9, 0, tzinfo=tz)
                code, text, _ = self.run_check(tmp, rows, {OTHER: SimpleFake})
            self.assertEqual(code, 0)
            self.assertIn('前回のrun: periodic-20261023-0900', text)
            self.assertIn('- 変化なし（取得範囲内）', text)

    def test_config_format_overrides_detection(self):
        rows = [{'name': 'other-repo', 'format': 'full'}, {'name': 'hermes-self-improvement', 'format': 'simple'}]
        with tempfile.TemporaryDirectory() as tmp:
            code, text, _ = self.run_check(tmp, rows, {OTHER: SimpleFake, REPO: Fake})
            self.assertEqual(code, 0)
            self.assertIn('完全版（作業案内あり）（config）', text.split(f'## {OTHER}')[1].split('## ')[0])
            self.assertIn('簡易版（config）', text.split(f'## {REPO}')[1])

    def test_limits_are_per_repository(self):
        rows = [{'name': 'hermes-self-improvement', 'limits': {'calls': 2}}, {'name': 'other-repo'}]
        with tempfile.TemporaryDirectory() as tmp:
            code, text, _ = self.run_check(tmp, rows, {REPO: Fake, OTHER: SimpleFake})
            self.assertEqual(code, 1)
            self.assertIn(f'| {REPO} | 停止 |', text)
            self.assertIn(f'| {OTHER} | 完了 |', text)
            self.assertIn('取得が不完全', text)

    def test_not_found_and_errors_stop_only_that_repository(self):
        class Missing(Fake):
            def get(self, path, page, timeout):
                return None
        class Broken(Fake):
            def exists(self, path, ref, timeout):
                raise RuntimeError('remote text that must not be printed')
        rows = [{'name': 'hermes-self-improvement'}, {'name': 'other-repo'}, {'name': 'private-repo'}]
        with tempfile.TemporaryDirectory() as tmp:
            code, text, _ = self.run_check(tmp, rows, {REPO: Broken, OTHER: SimpleFake, PRIVATE: Missing})
            self.assertEqual(code, 1)
            self.assertIn(f'| {REPO} | 停止 |', text)
            self.assertNotIn('remote text', text)
            self.assertIn(f'| {OTHER} | 完了 |', text)
            self.assertIn('見つからないため対象外', text)
            self.assertIn('設定ファイルの名前が正しいか確認する', text)

    def test_ci_read_failure_is_reported_not_fatal(self):
        class NoRuns(SimpleFake):
            def branch_runs(self, branch, timeout):
                return {'workflow_runs': [{'name': 'CI', 'status': 'weird'}]}
        with tempfile.TemporaryDirectory() as tmp:
            code, text, _ = self.run_check(tmp, [{'name': 'other-repo'}], {OTHER: NoRuns})
            self.assertEqual(code, 0)
            self.assertIn('取得できない: 既定ブランチの workflow run を読めない', text)

    def test_existing_summary_or_bad_config_or_runs_name(self):
        with tempfile.TemporaryDirectory() as tmp:
            runs = Path(tmp).resolve() / 'runs'
            bad = Path(tmp) / 'bad.json'
            bad.write_text('{"version": 1}', encoding='utf-8')
            self.assertEqual(pc.main(['--config', str(bad), '--runs', str(runs)]), 1)
            text = next((runs / 'periodic-summaries').iterdir()).read_text(encoding='utf-8')
            self.assertIn('設定ファイルを読めない', text)
            with patch.object(pc, 'datetime', wraps=datetime) as clock:
                clock.now.side_effect = lambda tz=None: datetime(2026, 10, 30, 9, 0, tzinfo=tz)
                pc.main(['--config', str(bad), '--runs', str(runs)])
                self.assertEqual(pc.main(['--config', str(bad), '--runs', str(runs)]), 2)
            self.assertEqual(pc.main(['--runs', str(Path(tmp) / 'elsewhere')]), 2)


class ReviewFollowUpTests(CheckHelper, unittest.TestCase):
    """Findings of the Claude Code review of PR #224."""

    def test_format_detection_failure_keeps_the_run(self):
        class NoPresence(SimpleFake):
            def exists(self, path, ref, timeout):
                raise pc.Invalid('synthetic rate limit')
        with tempfile.TemporaryDirectory() as tmp:
            code, text, runs = self.run_check(tmp, [{'name': 'other-repo'}], {OTHER: NoPresence})
            self.assertEqual(code, 0)
            self.assertIn('簡易版（判定できないため簡易版）', text)
            self.assertEqual(len(list((runs / 'second-works--other-repo').iterdir())), 1)

    def test_pull_request_runs_and_running_runs(self):
        class Runs(SimpleFake):
            def __init__(self):
                super().__init__()
                base = {'head_sha': SHA, 'event': 'push'}
                self.workflow_runs = [
                    # A fork PR from a branch named like the default branch: not the default branch's CI.
                    dict(base, name='Fork CI', workflow_id=1, status='completed', conclusion='failure', event='pull_request',
                         created_at='2026-10-29T03:00:00Z'),
                    # A run in progress does not hide the failure just before it.
                    dict(base, name='Template CI', workflow_id=2, status='in_progress', conclusion=None,
                         created_at='2026-10-29T02:00:00Z'),
                    dict(base, name='Template CI', workflow_id=2, status='completed', conclusion='failure',
                         created_at='2026-10-29T01:00:00Z'),
                    # Two workflow files with the same name are two workflows.
                    dict(base, name='CI', workflow_id=3, status='completed', conclusion='failure', created_at='2026-10-28T00:00:00Z'),
                    dict(base, name='CI', workflow_id=4, status='completed', conclusion='success', created_at='2026-10-29T00:00:00Z')]
        with tempfile.TemporaryDirectory() as tmp:
            code, text, _ = self.run_check(tmp, [{'name': 'other-repo'}], {OTHER: Runs})
            self.assertNotIn('Fork CI', text)
            self.assertIn('最後に終わったrun: "failure"', text)
            self.assertIn('警告: 既定ブランチの "Template CI" が "failure"', text)
            self.assertIn('警告: 既定ブランチの "CI" が "failure"', text)
            self.assertIn('失敗 2件', text)

    def test_calls_include_format_and_ci(self):
        with tempfile.TemporaryDirectory() as tmp:
            code, text, runs = self.run_check(tmp, [{'name': 'other-repo'}], {OTHER: SimpleFake})
            saved = load_run(next((runs / 'second-works--other-repo').iterdir()))
            # simple: 1 presence check (stops at the first missing file) + 1 CI read
            self.assertIn(f'API呼出 {saved["coverage"]["calls"] + 2}回', text)

    def test_unexpected_error_names_only_its_type(self):
        class Broken(SimpleFake):
            def branch_runs(self, branch, timeout):
                return {'workflow_runs': []}
        with tempfile.TemporaryDirectory() as tmp, patch.object(pc, 'stale_open', side_effect=KeyError('secret')):
            code, text, _ = self.run_check(tmp, [{'name': 'other-repo'}], {OTHER: Broken})
            self.assertEqual(code, 1)
            self.assertIn('予期しないエラー（KeyError）', text)
            self.assertNotIn('secret', text)

    def test_update_restarts_on_the_updated_checkout(self):
        with tempfile.TemporaryDirectory() as tmp:
            runs = Path(tmp).resolve() / 'runs'
            with patch.object(pc, 'update_checkout', return_value=None), \
                    patch.object(pc.os, 'execv', side_effect=SystemExit(0)) as execv:
                with self.assertRaises(SystemExit):
                    pc.main(['--update', '--runs', str(runs)])
            args = execv.call_args.args[1]
            self.assertNotIn('--update', args)
            self.assertEqual(args[-2:], ['--runs', str(runs)])
            self.assertTrue(args[-3].endswith('scripts/periodic_check.py'))

    def test_update_failure_still_checks_and_abbreviations_are_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            runs = Path(tmp).resolve() / 'runs'
            config = config_file(tmp, [{'name': 'other-repo'}])
            make = lambda target: Collector(target['repo'], SimpleFake(), Limits(**target['limits']))
            with patch.object(pc, 'update_checkout', return_value='git fetch に失敗した'), \
                    patch.object(pc, 'collector_for', make):
                self.assertEqual(pc.main(['--update', '--config', str(config), '--runs', str(runs)]), 1)
            text = next((runs / 'periodic-summaries').iterdir()).read_text(encoding='utf-8')
            self.assertIn('更新しなかった: git fetch に失敗した', text)
            self.assertIn(f'| {OTHER} | 完了 |', text)
            with self.assertRaises(SystemExit):
                pc.main(['--upd', '--runs', str(runs)])
            with patch.object(pc, 'update_checkout', return_value=None), \
                    patch.object(pc.os, 'execv', side_effect=OSError('moved')), patch.object(pc, 'collector_for', make), \
                    patch.object(pc, 'datetime', wraps=datetime) as clock:
                clock.now.side_effect = lambda tz=None: datetime(2026, 11, 6, 9, 0, tzinfo=tz)
                self.assertEqual(pc.main(['--update', '--config', str(config), '--runs', str(runs)]), 1)
            self.assertIn('起動し直せない（OSError）', (runs / 'periodic-summaries' / '20261106-0900.md').read_text(encoding='utf-8'))

    def test_ci_runs_of_other_repositories_cancelled_and_format_fallback_warning(self):
        class Runs(SimpleFake):
            def __init__(self):
                super().__init__()
                base = {'head_sha': SHA, 'event': 'push', 'status': 'completed'}
                self.workflow_runs = [
                    dict(base, name='Bridge', event='workflow_run', conclusion='failure', created_at='2026-10-29T03:00:00Z',
                         head_repository={'full_name': 'someone/other-repo'}),
                    dict(base, name='Template CI', conclusion='cancelled', created_at='2026-10-29T02:00:00Z',
                         head_repository={'full_name': OTHER})]
            def exists(self, path, ref, timeout):
                raise pc.Invalid('limit')
        with tempfile.TemporaryDirectory() as tmp:
            code, text, _ = self.run_check(tmp, [{'name': 'other-repo'}], {OTHER: Runs})
            self.assertNotIn('Bridge', text)
            self.assertNotIn('"Template CI" が', text)  # cancelled is not a warning
            self.assertIn('警告: 形式を判定できず', text)

    def test_simple_repository_costs_one_presence_call(self):
        fake = SimpleFake()
        Collector(OTHER, fake).repository_format('trunk')
        self.assertEqual([r for r in fake.routes if r[0] == 'EXISTS'], [('EXISTS', '.claude/skills/steward/SKILL.md', 'trunk')])

    def test_bad_head_sha_is_refused(self):
        class Bad(SimpleFake):
            def __init__(self):
                super().__init__()
                self.workflow_runs[0]['head_sha'] = 'abc\n| injected |'
        with tempfile.TemporaryDirectory() as tmp:
            code, text, _ = self.run_check(tmp, [{'name': 'other-repo'}], {OTHER: Bad})
            self.assertNotIn('injected', text)
            self.assertIn('取得できない: 既定ブランチの workflow run を読めない', text)

    def test_cancelled_run_does_not_hide_an_earlier_failure_and_no_runs(self):
        class Runs(SimpleFake):
            def __init__(self):
                super().__init__()
                base = {'head_sha': SHA, 'event': 'push', 'status': 'completed', 'name': 'CI'}
                self.workflow_runs = [dict(base, conclusion='cancelled', created_at='2026-10-29T02:00:00Z'),
                                      dict(base, conclusion='failure', created_at='2026-10-29T01:00:00Z')]
        class NoRuns(SimpleFake):
            def __init__(self):
                super().__init__()
                self.workflow_runs = []
        with tempfile.TemporaryDirectory() as tmp:
            text = self.run_check(tmp, [{'name': 'other-repo'}], {OTHER: Runs})[1]
            self.assertIn('警告: 既定ブランチの "CI" が "failure"', text)
        with tempfile.TemporaryDirectory() as tmp:
            text = self.run_check(tmp, [{'name': 'other-repo'}], {OTHER: NoRuns})[1]
            self.assertIn('| runなし |', text)

    def test_presence_needs_a_file_and_update_names_a_non_git_checkout(self):
        from github_work_guide.collector import GhReadOnly
        for body, expected in ((b'{"type": "file"}', True), (b'{"type": "dir"}', False), (b'[]', False)):
            with patch('subprocess.run', return_value=subprocess.CompletedProcess([], 0, body, b'')):
                self.assertIs(GhReadOnly(OTHER).exists('.claude/skills/steward/SKILL.md', 'main', 1), expected)
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            (work / 'runs').mkdir()
            (work / pc.MARKER).write_text('')
            with patch.object(pc, 'ROOT', work):
                self.assertIn('git の checkout として読めない', pc.update_checkout())

    def test_error_after_a_complete_collection_keeps_the_snapshot(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(pc, 'build_plan', side_effect=TypeError('x')):
            code, text, runs = self.run_check(tmp, [{'name': 'hermes-self-improvement'}], {REPO: Fake})
            self.assertEqual(code, 1)
            run = next((runs / 'second-works--hermes-self-improvement').iterdir())
            self.assertEqual(load_run(run)['coverage']['status'], 'COMPLETE')

    def test_one_issue_counts_once(self):
        a = {'acceptance': [('issue:1', 'x')], 'completion': [], 'stale': [('issue:1', 't', 'u')], 'warnings': []}
        self.assertEqual(pc.attention({'analysis': a, 'ci': []}), 1)

    def test_format_files_are_never_read_as_content(self):
        from github_work_guide.collector import GhReadOnly
        with self.assertRaises(pc.Invalid):
            GhReadOnly(OTHER).content('.claude/skills/steward/SKILL.md', 'main', 1)


class RunTests(unittest.TestCase):
    def test_timeout_and_missing_command_do_not_raise(self):
        self.assertEqual(pc.run(['sleep', '5'], timeout=1)[0], -1)
        self.assertEqual(pc.run(['no-such-command-for-periodic-check'])[0], -1)

    def test_notification_text_is_an_argument(self):
        calls = []
        with patch.object(pc, 'run', lambda args, **kw: calls.append(args) or (0, '', '')), \
                patch.object(pc.shutil, 'which', lambda name: '/usr/bin/osascript'):
            pc.notify('停止: "x" & do shell script "id"')
        args = calls[0]
        self.assertNotIn('do shell script', ' '.join(args[:args.index('--')]))
        self.assertEqual(args[-1], '停止: "x" & do shell script "id"')


class UpdateGuardTests(unittest.TestCase):
    def git(self, cwd, *args):
        return subprocess.run(['git', '-c', 'user.name=t', '-c', 'user.email=t@example.invalid', *args],
                              cwd=cwd, check=True, capture_output=True, text=True).stdout.strip()

    def checkout(self, tmp, marker=True):
        """A detached clone of a bare 'origin' with two commits on main, sitting on the first one."""
        tmp = Path(tmp)
        seed = tmp / 'seed'
        seed.mkdir()
        self.git(seed, 'init', '-q', '-b', 'main')
        (seed / '.gitignore').write_text('runs/\n')
        self.git(seed, 'add', '.gitignore')
        self.git(seed, 'commit', '-q', '-m', 'one')
        self.git(seed, 'commit', '-q', '--allow-empty', '-m', 'two')
        self.git(tmp, 'clone', '-q', '--bare', str(seed), 'origin.git')
        work = tmp / 'work'
        self.git(tmp, 'clone', '-q', str(tmp / 'origin.git'), 'work')
        self.git(work, 'checkout', '-q', '--detach', 'HEAD~1')
        if marker:
            (work / 'runs').mkdir()
            (work / pc.MARKER).write_text('')
        return work

    def update(self, work):
        with patch.object(pc, 'ROOT', work):
            return pc.update_checkout()

    def test_moves_dedicated_checkout_to_origin_main(self):
        with tempfile.TemporaryDirectory() as tmp:
            work = self.checkout(tmp)
            self.assertIsNone(self.update(work))
            self.assertEqual(self.git(work, 'rev-parse', 'HEAD'), self.git(work, 'rev-parse', 'origin/main'))

    def test_refuses_without_marker(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertIn('がない', self.update(self.checkout(tmp, marker=False)))

    def test_refuses_branch_checkout(self):
        with tempfile.TemporaryDirectory() as tmp:
            work = self.checkout(tmp)
            self.git(work, 'switch', '-q', 'main')
            self.assertIn('ブランチ', self.update(work))

    def test_refuses_changed_or_untracked_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            work = self.checkout(tmp)
            (work / 'note.txt').write_text('mine')
            self.assertIn('未追跡', self.update(work))
            before = self.git(work, 'rev-parse', 'HEAD')
            (work / 'note.txt').unlink()
            (work / '.gitignore').write_text('changed\n')
            self.assertIn('変更', self.update(work))
            self.assertEqual(self.git(work, 'rev-parse', 'HEAD'), before)

    def test_refuses_commits_not_on_main(self):
        with tempfile.TemporaryDirectory() as tmp:
            work = self.checkout(tmp)
            self.git(work, 'commit', '-q', '--allow-empty', '-m', 'local only')
            local = self.git(work, 'rev-parse', 'HEAD')
            self.assertIn('origin/main にない', self.update(work))
            self.assertEqual(self.git(work, 'rev-parse', 'HEAD'), local)


class TransportTests(unittest.TestCase):
    def test_presence_and_runs_routes_are_fixed(self):
        from github_work_guide.collector import GhReadOnly
        from github_work_guide.core import Invalid
        with patch('subprocess.run', return_value=subprocess.CompletedProcess([], 0, b'{"workflow_runs": []}', b'')) as run:
            GhReadOnly(OTHER).branch_runs('trunk', 1)
            GhReadOnly(OTHER).exists('.claude/skills/steward/SKILL.md', 'trunk', 1)
        self.assertEqual(run.call_args_list[0].args[0][-5:], ['--raw-field', 'branch=trunk', '--raw-field', 'per_page=30',
                                                             f'repos/{OTHER}/actions/runs'])
        self.assertIn(f'repos/{OTHER}/actions/runs', run.call_args_list[0].args[0])
        self.assertIn('branch=trunk', run.call_args_list[0].args[0])
        self.assertIn(f'repos/{OTHER}/contents/.claude/skills/steward/SKILL.md', run.call_args_list[1].args[0])
        for path in ('README.md', '.github/pr-gate-checks'):
            with self.assertRaises(Invalid):
                GhReadOnly(OTHER).exists(path, 'main', 1)
        missing = subprocess.CompletedProcess([], 1, b'', b'gh: Not Found (HTTP 404)')
        with patch('subprocess.run', return_value=missing):
            self.assertFalse(GhReadOnly(OTHER).exists('.agents/skills/plan-to-issues/SKILL.md', 'main', 1))


if __name__ == '__main__':
    unittest.main()
