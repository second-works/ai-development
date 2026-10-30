"""#219: one harness for many repositories. Config allowlist, per-repository settings, review kinds,
private repositories and repository-independent guidance. No network: synthetic transports only."""
import base64
import copy
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from support import PREFIX, REPO, ROOT, SETTINGS, seal  # noqa: F401
from github_work_guide import core
from github_work_guide.collector import Collector, GhReadOnly, Limits, connection_query, rest_request
from github_work_guide.config import CONFIG, entry, load_config
from github_work_guide.core import Invalid, build_plan, diff, digest, markdown, recheck, save_run, load_run, validate
from test_github_work_guide import SHA, Fake, item, snapshot
from test_github_work_guide_real import load_rows, snapshot as real_snapshot

CLI = ROOT / 'scripts/report_github_work_guide.py'
OTHER = 'second-works/other-repo'


def write_config(directory, value):
    path = Path(directory) / 'config.json'
    path.write_text(json.dumps(value), encoding='utf-8')
    return path


def base_config(**extra):
    return {'version': 1, 'owner': 'second-works', 'repositories': [{'name': 'ai-development'}], **extra}


class ConfigTests(unittest.TestCase):
    def test_checked_in_config_lists_only_second_works(self):
        config = load_config(CONFIG)
        self.assertTrue(config['repositories'])
        self.assertIn('second-works/ai-development', config['repositories'])
        self.assertTrue(all(r.startswith('second-works/') for r in config['repositories']))

    def test_unknown_keys_other_owner_and_bad_names_are_refused(self):
        bad = [base_config(extra=1), dict(base_config(), owner='someone-else'), dict(base_config(), version=2),
               dict(base_config(), repositories=[]), dict(base_config(), repositories=[{'name': 'x', 'unknown': 1}]),
               dict(base_config(), repositories=[{'name': 'other/x'}]), dict(base_config(), repositories=[{'name': '../x'}]),
               dict(base_config(), repositories=[{'name': 'a'}, {'name': 'a'}]),
               dict(base_config(), repositories=[{'name': 'a', 'required_checks': []}]),
               dict(base_config(), repositories=[{'name': 'a', 'limits': {'seconds': 0}}]),
               dict(base_config(), limits={'unknown': 1})]
        with tempfile.TemporaryDirectory() as tmp:
            for value in bad:
                with self.subTest(value=value), self.assertRaises(Invalid):
                    load_config(write_config(tmp, value))

    def test_limits_and_required_checks_per_repository(self):
        value = base_config(limits={'seconds': 100, 'calls': 300},
                            repositories=[{'name': 'a', 'limits': {'calls': 50}}, {'name': 'b', 'required_checks': ['ci']}])
        with tempfile.TemporaryDirectory() as tmp:
            config = load_config(write_config(tmp, value))
        self.assertEqual(entry(config, 'second-works/a')['limits'], {'seconds': 100, 'calls': 50})
        self.assertEqual(entry(config, 'second-works/b')['required_checks'], ['ci'])
        self.assertIsNone(entry(config, 'second-works/a')['required_checks'])
        with self.assertRaises(Invalid):
            entry(config, 'second-works/c')


class CliAllowlistTests(unittest.TestCase):
    def run_cli(self, *args):
        return subprocess.run([sys.executable, '-I', '-B', str(CLI), *args], capture_output=True, text=True, timeout=60,
                              env={'PATH': '/nonexistent'})  # no gh: any GitHub call would fail loudly

    def test_collect_needs_a_configured_repository(self):
        with tempfile.TemporaryDirectory() as tmp:
            config = write_config(tmp, base_config())
            out = Path(tmp).resolve() / 'runs' / 'x'
            for args in ((), ('--repo', 'second-works/not-listed'), ('--repo', 'other-owner/ai-development')):
                proc = self.run_cli('collect', '--config', str(config), '--out', str(out), *args)
                self.assertEqual(proc.returncode, 2, args)
                self.assertIn('BLOCKED', proc.stderr)
                self.assertFalse(out.exists())

    def test_recheck_refuses_a_run_of_an_unlisted_repository(self):
        snap = snapshot(item(7))
        with tempfile.TemporaryDirectory() as tmp:
            config = write_config(tmp, base_config())  # REPO (the fixture origin) is not listed here
            run, out = Path(tmp).resolve() / 'runs' / 'a', Path(tmp).resolve() / 'runs' / 'b'
            save_run(run, {'snapshot.json': snap, 'plan.json': build_plan(snap)})
            proc = self.run_cli('recheck', '--config', str(config), '--run', str(run), '--target', 'issue:7', '--out', str(out))
            self.assertEqual(proc.returncode, 2)
            self.assertFalse(out.exists())


def encoded(text):
    return {'type': 'file', 'encoding': 'base64', 'content': base64.b64encode(text.encode()).decode()}


class TransportTests(unittest.TestCase):
    def test_routes_are_bound_to_one_repository(self):
        rest_request(OTHER, f'repos/{OTHER}/issues', 1)
        for repo, path in ((OTHER, PREFIX + '/issues'), (REPO, f'repos/{OTHER}/issues'),
                           (OTHER, f'repos/{OTHER}/contents/README.md')):
            with self.assertRaises(Invalid):
                rest_request(repo, path, 1)
        for bad in ('second-works', 'a/b/c', 'second-works/..', 'second-works/x.git', '-x/y', 'x/y\n'):
            with self.assertRaises(Invalid):
                GhReadOnly(bad)

    def test_graphql_names_the_repository_by_variables_only(self):
        for kind in ('threads', 'closing'):
            query = connection_query(kind)
            self.assertNotIn('second-works', query)
            self.assertIn('repository(owner:$owner,name:$name)', query)
        with patch('subprocess.run', return_value=subprocess.CompletedProcess([], 0, b'{}', b'')) as run:
            GhReadOnly(OTHER).connection('threads', 3, None, 1)
        args = run.call_args.args[0]
        self.assertIn('owner=second-works', args)
        self.assertIn('name=other-repo', args)

    def test_content_reads_one_allowlisted_file_on_a_branch(self):
        with patch('subprocess.run', return_value=subprocess.CompletedProcess([], 0, json.dumps(encoded('ci\n')).encode(), b'')) as run:
            self.assertEqual(GhReadOnly(OTHER).content('.github/pr-gate-checks', 'trunk', 1), 'ci\n')
        self.assertEqual(run.call_args.args[0], ['gh', 'api', '--hostname', 'github.com', '--method', 'GET',
                                                 '--raw-field', 'ref=trunk', f'repos/{OTHER}/contents/.github/pr-gate-checks'])
        with self.assertRaises(Invalid):
            GhReadOnly(OTHER).content('README.md', 'main', 1)

    def test_only_not_found_is_a_result(self):
        missing = subprocess.CompletedProcess([], 1, b'', b'gh: Not Found (HTTP 404)')
        with patch('subprocess.run', return_value=missing):
            self.assertIsNone(GhReadOnly(OTHER).content('.github/pr-gate-review', 'main', 1))
            self.assertIsNone(GhReadOnly(OTHER).get(f'repos/{OTHER}', None, 1))
            with self.assertRaises(Invalid):  # a missing issue list is not "empty"
                GhReadOnly(OTHER).get(f'repos/{OTHER}/issues', 1, 1)
        with patch('subprocess.run', return_value=subprocess.CompletedProcess([], 1, b'', b'HTTP 403')):
            with self.assertRaises(Invalid):
                GhReadOnly(OTHER).content('.github/pr-gate-review', 'main', 1)


class OtherFake(Fake):
    """The synthetic API of a different repository with its own default branch and settings."""

    def __init__(self, repo=OTHER, branch='trunk'):
        super().__init__()
        self.repo, self.branch = repo, branch
        self.items = [self.renamed(x) for x in self.items]
        self.meta.update(full_name=repo, default_branch=branch)
        self.contents = {'.github/pr-gate-checks': None, '.github/pr-gate-review': 'claude-code\n'}

    def renamed(self, value):
        return json.loads(json.dumps(value).replace(REPO, self.repo))

    def get(self, path, page, timeout):
        rest_request(self.repo, path, page)
        response = super().get(path.replace(f'repos/{self.repo}', PREFIX, 1), page, timeout)
        return self.renamed(response)

    def get_unchecked(self, path):
        return path

    def content(self, path, ref, timeout):
        assert ref == self.branch
        return super().content(path, ref, timeout)


class SettingsTests(unittest.TestCase):
    def test_settings_come_from_the_default_branch(self):
        fake = OtherFake()
        snap = Collector(OTHER, fake).collect()
        self.assertEqual(snap['coverage']['status'], 'COMPLETE')
        self.assertEqual(snap['repo'], OTHER)
        self.assertEqual(snap['settings'], {'default_branch': 'trunk', 'required_checks': ['verification', 'Security Preflight'],
                                            'checks_source': 'default', 'review': ['claude-code'], 'review_source': 'repository'})
        self.assertIn(('CONTENT', '.github/pr-gate-review', 'trunk'), fake.routes)
        self.assertTrue(all(i['url'].startswith(f'https://github.com/{OTHER}/') for i in snap['items'].values()))
        text = markdown(snap, diff(snap), build_plan(snap))
        self.assertIn(f'リポジトリ: {OTHER}', text)
        self.assertIn('verification, Security Preflight', text)

    def test_config_required_checks_override_the_repository_file(self):
        fake = OtherFake()
        fake.contents['.github/pr-gate-checks'] = 'ci\n'
        settings = Collector(OTHER, fake).collect()['settings']
        self.assertEqual((settings['required_checks'], settings['checks_source']), (['ci'], 'repository'))
        settings = Collector(OTHER, OtherFake(), required_checks=['build']).collect()['settings']
        self.assertEqual((settings['required_checks'], settings['checks_source']), (['build'], 'config'))

    def test_comment_only_setting_file_falls_back_to_default(self):
        fake = OtherFake()
        fake.contents['.github/pr-gate-review'] = '# nothing yet\n\n'
        self.assertEqual(Collector(OTHER, fake).collect()['settings']['review'], ['codex'])

    def test_settings_read_failure_is_incomplete(self):
        fake = OtherFake()
        fake.fail_at = 2  # the first content read
        snap = Collector(OTHER, fake).collect()
        self.assertEqual(snap['coverage']['status'], 'INCOMPLETE')

    def test_settings_are_sealed(self):
        snap = snapshot(item(7))
        for change in ({'review': []}, {'required_checks': ['a', 'a']}, {'checks_source': 'pr'}, {'default_branch': ''},
                       {'extra': 1}):
            value = copy.deepcopy(snap)
            value['settings'] = {**value['settings'], **change}
            value['hash'] = digest({k: v for k, v in value.items() if k != 'hash'})
            with self.subTest(change=change), self.assertRaises(Invalid):
                validate(value)
        value = copy.deepcopy(snap)
        value['settings']['required_checks'] = ['other']
        with self.assertRaises(Invalid):  # hash no longer matches
            validate(value)


def pr_with(comments=(), reviews=None):
    pr = item(25, True)
    pr['raw']['comments'] = list(comments)
    pr['raw']['detail']['comments'] = len(comments)
    if reviews is not None:
        pr['raw']['reviews'] = reviews
    pr['hash'] = digest(pr['raw'])
    return pr


def claude(body_json, association='OWNER'):
    return {'body': f'レビュー結果\n<!-- claude-code-review:v1 {json.dumps(body_json)} -->', 'author_association': association}


class ReviewGateTests(unittest.TestCase):
    CLAUDE = dict(SETTINGS, review=['claude-code'])

    def ok(self, **change):
        return {'commit_sha': SHA, 'status': 'completed', 'has_unresolved_findings': False, **change}

    def test_claude_code_review_on_head_passes(self):
        self.assertEqual(core.gate(pr_with([claude(self.ok())], reviews=[]), self.CLAUDE), [])
        for association in ('MEMBER', 'COLLABORATOR'):
            self.assertEqual(core.gate(pr_with([claude(self.ok(), association)], reviews=[]), self.CLAUDE), [])

    def test_claude_code_review_that_does_not_pass(self):
        cases = {'untrusted': [claude(self.ok(), 'NONE')], 'contributor': [claude(self.ok(), 'CONTRIBUTOR')],
                 'stale': [claude(self.ok(commit_sha='b' * 40))], 'pending': [claude(self.ok(status='in_progress'))],
                 'string_bool': [claude(self.ok(has_unresolved_findings='false'))], 'missing': [],
                 'broken': [{'body': '<!-- claude-code-review:v1 {"commit_sha": } -->', 'author_association': 'OWNER'}],
                 'later_stale': [claude(self.ok()), claude(self.ok(commit_sha='b' * 40))]}
        for name, comments in cases.items():
            with self.subTest(name):
                failures = core.gate(pr_with(comments, reviews=[]), self.CLAUDE)
                self.assertIn('現headの正式レビュー未確認（claude-code）', failures)

    def test_findings_stop_even_when_another_kind_passed(self):
        both = dict(SETTINGS, review=['codex', 'claude-code'])
        failures = core.gate(pr_with([claude(self.ok(has_unresolved_findings=True))]), both)
        self.assertEqual(failures, ['現headの正式レビュー（claude-code）に未解決の指摘あり'])
        self.assertEqual(core.gate(pr_with([claude(self.ok(has_unresolved_findings=True))]), SETTINGS), [])  # codex only

    def test_codex_setting_does_not_accept_claude_comment(self):
        failures = core.gate(pr_with([claude(self.ok())], reviews=[]), SETTINGS)
        self.assertIn('現headの正式レビュー未確認（codex）', failures)

    def test_unknown_kind_never_passes(self):
        failures = core.gate(pr_with([claude(self.ok())]), dict(SETTINGS, review=['someone']))
        self.assertIn('現headの正式レビュー未確認（someone）', failures)

    def test_required_checks_come_from_settings(self):
        pr = pr_with()
        self.assertEqual(core.gate(pr, SETTINGS), [])
        self.assertEqual(core.gate(pr, dict(SETTINGS, required_checks=['verification'])), ['verification: 未取得'])
        plan = build_plan(seal({'pr:25': pr}, snapshot(item(7))['coverage'], settings=dict(SETTINGS, required_checks=['build'])))
        self.assertIn('build', plan['candidates']['pr:25']['steps'][0])


class RepositoryIndependenceTests(unittest.TestCase):
    """The same Issue/PR text in another repository gives the same guidance."""

    def moved(self, rows, repo):
        return json.loads(json.dumps(rows).replace(REPO, repo))

    def normal(self, value, repo):
        return json.loads(json.dumps(value).replace(repo, 'REPO'))

    def test_real_fixture_guidance_does_not_depend_on_the_repository_name(self):
        rows = load_rows()
        original = real_snapshot(rows)
        moved_rows = self.moved(rows, OTHER)
        items = {}
        for raw in moved_rows:
            d = raw['detail']
            kind = 'pr' if 'checks' in raw else 'issue'
            items[f'{kind}:{d["number"]}'] = {
                'kind': kind, 'number': d['number'], 'state': 'MERGED' if kind == 'pr' and d['merged'] else d['state'].upper(),
                'title': d['title'], 'body': d['body'] or '', 'url': core.source_url(OTHER, kind, d['number']),
                'raw': raw, 'hash': digest(raw)}
        moved = validate(seal(items, original['coverage'], repo=OTHER))
        a, b = build_plan(original), build_plan(moved)
        self.assertEqual(a['order'], b['order'])
        for key in a['candidates']:
            ca, cb = a['candidates'][key], b['candidates'][key]
            with self.subTest(key):
                self.assertEqual(ca['kind'], cb['kind'])
                self.assertEqual([h['code'] for h in ca['holds']], [h['code'] for h in cb['holds']])
                self.assertEqual(self.normal(ca['steps'], REPO), self.normal(cb['steps'], OTHER))
                self.assertEqual(len(ca['external']), len(cb['external']))
        # References to the old name are now another repository's: they are not read as same-repo links.
        self.assertTrue(re.search(re.escape(OTHER), json.dumps(b)))

    def test_runs_of_another_repository_are_not_compared(self):
        a = snapshot(item(7))
        b = seal({}, dict(a['coverage']), repo=OTHER)
        with self.assertRaises(Invalid):
            diff(b, a)
        plan = build_plan(a)
        with self.assertRaises(Invalid):
            recheck(a, plan, 'issue:7', b)

    def test_run_directory_per_repository(self):
        snap = snapshot(item(7))
        with tempfile.TemporaryDirectory() as tmp:
            run = Path(tmp).resolve() / 'runs' / 'second-works--hermes-self-improvement' / 'periodic-20261030-0900'
            save_run(run, {'snapshot.json': snap})
            self.assertEqual(load_run(run), snap)
            for bad in (Path(tmp).resolve() / 'other' / 'x', Path(tmp).resolve() / 'runs' / 'a' / 'b' / 'c'):
                with self.assertRaises(Invalid):
                    save_run(bad, {'snapshot.json': snap})

    def test_limits_are_per_collector(self):
        slow, normal = Collector(OTHER, OtherFake(), Limits(calls=2)), Collector(OTHER, OtherFake())
        self.assertEqual(slow.collect()['coverage']['status'], 'INCOMPLETE')
        self.assertEqual(normal.collect()['coverage']['status'], 'COMPLETE')


class NoFixedRepositoryTests(unittest.TestCase):
    def test_code_names_no_repository(self):
        for path in [*(ROOT / 'scripts/github_work_guide').glob('*.py'), CLI]:
            text = path.read_text(encoding='utf-8')
            with self.subTest(path.name):
                self.assertNotIn('hermes-self-improvement', text)
                self.assertNotRegex(text, r"repository\(owner:\"")


class ReviewFollowUpTests(unittest.TestCase):
    """Findings of the Claude Code review of PR #221."""

    def test_limits_can_be_raised_up_to_the_maximum(self):
        ok = base_config(repositories=[{'name': 'big', 'limits': {'seconds': 900, 'calls': 2000, 'items': 20000}}])
        with tempfile.TemporaryDirectory() as tmp:
            config = load_config(write_config(tmp, ok))
            self.assertEqual(Limits(**entry(config, 'second-works/big')['limits']).seconds, 900)
            for over in ({'seconds': 901}, {'calls': 2001}, {'pages': 11}, {'items': 20001}):
                with self.subTest(over=over), self.assertRaises(Invalid):
                    load_config(write_config(tmp, base_config(repositories=[{'name': 'a', 'limits': over}])))

    def test_setting_lines_match_check_pr_head(self):
        from github_work_guide.collector import setting_lines
        text = '# comment\r\n  # not a comment\nbuild \n\n   \nci\nci\n'
        self.assertEqual(setting_lines(text), ['  # not a comment', 'build ', 'ci'])
        self.assertEqual(setting_lines(' claude-code \n# codex\n', strip=True), ['claude-code'])
        fake = OtherFake()
        fake.contents['.github/pr-gate-checks'] = 'build \n'
        settings = Collector(OTHER, fake).collect()['settings']
        self.assertEqual(settings['required_checks'], ['build '])
        pr = pr_with()
        self.assertEqual(core.gate(pr, dict(SETTINGS, required_checks=['ci '])), ['ci : 未取得'])

    def test_unknown_review_kind_points_at_the_setting(self):
        failures = core.gate(pr_with(), dict(SETTINGS, review=['claude']))
        self.assertIn('正式レビューの種類を読めない（claude）: main の .github/pr-gate-review を確認', failures)
        self.assertEqual(core.gate(pr_with(), dict(SETTINGS, review=['codex', 'claude'])),
                         ['正式レビューの種類を読めない（claude）: main の .github/pr-gate-review を確認'])

    def test_same_named_checks_of_two_workflows_do_not_hide_a_failure(self):
        pr = pr_with()
        app = {'id': 15368}
        base = {'name': 'ci', 'head_sha': SHA, 'status': 'completed', 'app': app}
        pr['raw']['checks'] = [c for c in pr['raw']['checks'] if c['name'] != 'ci'] + [
            dict(base, id=100, conclusion='failure', check_suite={'id': 1}),
            dict(base, id=101, conclusion='success', check_suite={'id': 2})]
        self.assertIn('ci: 未成功/旧head', core.gate(pr, SETTINGS))
        # A re-run in the same suite replaces the old attempt.
        pr['raw']['checks'][-1]['check_suite'] = {'id': 1}
        self.assertEqual(core.gate(pr, SETTINGS), [])

    def test_previous_of_another_repository_stops_before_collecting(self):
        import importlib.util
        spec = importlib.util.spec_from_file_location('report_cli', CLI)
        cli = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cli)
        snap = snapshot(item(7))
        with tempfile.TemporaryDirectory() as tmp:
            run = Path(tmp).resolve() / 'runs' / 'previous'
            save_run(run, {'snapshot.json': snap})
            config = write_config(tmp, base_config())
            with patch.object(cli, 'collector', side_effect=AssertionError('network')) as made:
                code = cli.main(['collect', '--config', str(config), '--repo', 'second-works/ai-development',
                                 '--previous', str(run), '--out', str(Path(tmp).resolve() / 'runs' / 'new')])
            self.assertEqual(code, 2)
            made.assert_not_called()

if __name__ == '__main__':
    unittest.main()
