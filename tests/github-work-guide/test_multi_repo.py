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
        self.assertIn('&#91;"verification", "Security Preflight"&#93;', text)

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
                 'no_sha': [{'body': '<!-- claude-code-review:v1 {"status":"completed","has_unresolved_findings":false} -->',
                             'author_association': 'OWNER'}],
                 'null_body': [{'body': None, 'author_association': 'OWNER'}],
                 'stale_without_status': [{'body': '<!-- claude-code-review:v1 {"commit_sha":"' + 'b' * 40 + '"} -->',
                                           'author_association': 'OWNER'}],
                 'not_html_comment': [{'body': 'claude-code-review:v1 ' + json.dumps(self.ok()) + ' -->', 'author_association': 'OWNER'}],
                 'broken': [{'body': '<!-- claude-code-review:v1 {"commit_sha": } -->', 'author_association': 'OWNER'}],
                 'later_stale': [claude(self.ok()), claude(self.ok(commit_sha='b' * 40))]}
        for name, comments in cases.items():
            with self.subTest(name):
                failures = core.gate(pr_with(comments, reviews=[]), self.CLAUDE)
                self.assertIn('現headの正式レビュー未確認（&#91;"claude-code"&#93;）', failures)

    def test_findings_stop_even_when_another_kind_passed(self):
        both = dict(SETTINGS, review=['codex', 'claude-code'])
        failures = core.gate(pr_with([claude(self.ok(has_unresolved_findings=True))]), both)
        self.assertEqual(failures, ['現headの正式レビュー（claude-code）に未解決の指摘あり'])
        self.assertEqual(core.gate(pr_with([claude(self.ok(has_unresolved_findings=True))]), SETTINGS), [])  # codex only

    def test_codex_setting_does_not_accept_claude_comment(self):
        failures = core.gate(pr_with([claude(self.ok())], reviews=[]), SETTINGS)
        self.assertIn('現headの正式レビュー未確認（&#91;"codex"&#93;）', failures)

    def test_unknown_kind_never_passes(self):
        failures = core.gate(pr_with([claude(self.ok())]), dict(SETTINGS, review=['someone']))
        self.assertIn('現headの正式レビュー未確認（&#91;"someone"&#93;）', failures)

    def test_required_checks_come_from_settings(self):
        pr = pr_with()
        self.assertEqual(core.gate(pr, SETTINGS), [])
        self.assertEqual(core.gate(pr, dict(SETTINGS, required_checks=['verification'])), ['"verification": 未取得'])
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
        for path in [*(ROOT / 'scripts/github_work_guide').glob('*.py'), CLI, ROOT / 'scripts/periodic_check.py']:
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
        self.assertEqual(core.gate(pr, dict(SETTINGS, required_checks=['ci '])), ['"ci ": 未取得'])

    def test_unknown_review_kind_points_at_the_setting(self):
        failures = core.gate(pr_with(), dict(SETTINGS, review=['claude']))
        message = '正式レビューの種類を読めない（&#91;"claude"&#93;）: "main" の .github/pr-gate-review を確認'
        self.assertIn(message, failures)
        self.assertEqual(core.gate(pr_with(), dict(SETTINGS, review=['codex', 'claude'])), [message])

    def test_same_named_checks_of_two_workflows_do_not_hide_a_failure(self):
        # check-pr-head.sh (filter=latest) keeps the latest run of each check suite and fails on any failure.
        pr = pr_with()
        base = {'name': 'ci', 'head_sha': SHA, 'status': 'completed', 'app': {'id': 15368}}
        pr['raw']['checks'] = [c for c in pr['raw']['checks'] if c['name'] != 'ci'] + [
            dict(base, id=100, conclusion='failure', check_suite={'id': 1}),
            dict(base, id=101, conclusion='success', check_suite={'id': 2})]
        self.assertIn('"ci": 未成功/旧head', core.gate(pr, SETTINGS))
        pr['raw']['checks'][-1]['check_suite'] = {'id': 1}  # a re-run in the same suite replaces the old attempt
        self.assertEqual(core.gate(pr, SETTINGS), [])

    def test_skipped_or_neutral_next_to_a_success_passes_like_check_pr_head(self):
        pr = pr_with()
        base = {'name': 'ci', 'head_sha': SHA, 'status': 'completed', 'app': {'id': 15368}}
        others = [c for c in pr['raw']['checks'] if c['name'] != 'ci']
        pr['raw']['checks'] = others + [dict(base, id=100, conclusion='success', check_suite={'id': 1}),
                                        dict(base, id=101, conclusion='skipped', check_suite={'id': 2}),
                                        dict(base, id=102, conclusion='neutral', check_suite={'id': 3})]
        self.assertEqual(core.gate(pr, SETTINGS), [])
        pr['raw']['checks'] = others + [dict(base, id=101, conclusion='skipped', check_suite={'id': 2})]
        self.assertEqual(core.gate(pr, SETTINGS), ['"ci": 未成功/旧head'])  # skipped alone is not success
        pr['raw']['statuses'] = [{'id': 1, 'context': 'ci', 'state': 'success'}]
        self.assertEqual(core.gate(pr, SETTINGS), ['"ci": 未成功/旧head'])  # a successful status does not lift it

    def test_out_is_checked_before_collecting(self):
        import importlib.util
        spec = importlib.util.spec_from_file_location('report_cli', CLI)
        cli = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cli)
        with tempfile.TemporaryDirectory() as tmp:
            config = write_config(tmp, base_config())
            used = Path(tmp).resolve() / 'runs' / 'used'
            used.mkdir(parents=True)
            link = Path(tmp).resolve() / 'link'
            link.symlink_to(Path(tmp).resolve())
            for out in (used, Path(tmp).resolve() / 'elsewhere' / 'x', Path(tmp).resolve() / 'runs' / 'x' / '..',
                        link / 'runs' / 'new'):
                with patch.object(cli, 'collector', side_effect=AssertionError('network')) as made:
                    code = cli.main(['collect', '--config', str(config), '--repo', 'second-works/ai-development',
                                     '--out', str(out)])
                self.assertEqual(code, 2)
                made.assert_not_called()

    def test_bad_default_branch_is_not_blamed_on_the_setting_files(self):
        fake = OtherFake(branch=' trunk')
        snap = Collector(OTHER, fake).collect()
        self.assertEqual(snap['coverage']['status'], 'INCOMPLETE')
        self.assertNotIn('.github/pr-gate-checks', snap['coverage']['errors'][0])

    def test_exit_codes_for_private_and_not_found(self):
        import importlib.util
        spec = importlib.util.spec_from_file_location('report_cli', CLI)
        cli = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cli)
        with tempfile.TemporaryDirectory() as tmp:
            config = write_config(tmp, base_config(repositories=[{'name': 'other-repo'}]))
            for change, expected in (({'private': True}, 0), (None, 2)):
                fake = OtherFake()
                if change is None:
                    fake.get = lambda path, page, timeout: None
                else:
                    fake.meta.update(change)
                out = Path(tmp).resolve() / 'runs' / f'x{expected}'
                with patch.object(cli, 'collector', return_value=Collector(OTHER, fake)):
                    code = cli.main(['collect', '--config', str(config), '--repo', OTHER, '--out', str(out)])
                self.assertEqual(code, expected)
                self.assertEqual(load_run(out)['coverage']['status'], 'SKIPPED')

    def test_config_override_ignores_a_broken_checks_file(self):
        fake = OtherFake()
        fake.contents['.github/pr-gate-checks'] = 'x' * 300 + '\n'
        snap = Collector(OTHER, fake, required_checks=['build']).collect()
        self.assertEqual(snap['coverage']['status'], 'COMPLETE')
        self.assertEqual(snap['settings']['required_checks'], ['build'])
        self.assertNotIn(('CONTENT', '.github/pr-gate-checks', 'trunk'), fake.routes)  # not even fetched

    def test_priority_problems_do_not_lose_the_collection(self):
        import importlib.util
        spec = importlib.util.spec_from_file_location('report_cli', CLI)
        cli = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cli)
        with tempfile.TemporaryDirectory() as tmp:
            config = write_config(tmp, base_config(repositories=[{'name': 'other-repo'}]))
            bad = Path(tmp).resolve() / 'runs' / 'bad'
            with patch.object(cli, 'collector', side_effect=AssertionError('network')) as made:
                self.assertEqual(cli.main(['collect', '--config', str(config), '--repo', OTHER, '--out', str(bad),
                                           '--priority', 'issue:2l9']), 2)
            made.assert_not_called()
            out = Path(tmp).resolve() / 'runs' / 'kept'
            with patch.object(cli, 'collector', return_value=Collector(OTHER, OtherFake())):
                code = cli.main(['collect', '--config', str(config), '--repo', OTHER, '--out', str(out),
                                 '--priority', 'issue:999'])
            self.assertEqual(code, 2)
            self.assertEqual(load_run(out)['coverage']['status'], 'COMPLETE')  # saved, without a plan
            self.assertFalse((out / 'plan.json').exists())
            report = (out / 'report.md').read_text(encoding='utf-8')
            self.assertIn('planを作っていない', report)
            self.assertNotIn('取得不完全', report)
            # recheck: a priority item that is gone keeps the recheck result
            snap = snapshot(item(7), item(8))
            run = Path(tmp).resolve() / 'runs' / 'planned'
            save_run(run, {'snapshot.json': snap, 'plan.json': build_plan(snap, ['issue:8'])})
            config = write_config(tmp, base_config(repositories=[{'name': 'hermes-self-improvement'}]))
            fake = Fake()
            fake.items = [fake.items[0], fake.items[1]]  # issue:8 is no longer there
            out = Path(tmp).resolve() / 'runs' / 'rechecked'
            with patch.object(cli, 'collector', return_value=Collector(REPO, fake)):
                code = cli.main(['recheck', '--config', str(config), '--run', str(run), '--target', 'issue:7',
                                 '--out', str(out)])
            self.assertEqual(code, 2)
            self.assertEqual(json.loads((out / 'recheck.json').read_text())['status'], 'STALE')

    def test_non_file_setting_is_a_setting_error(self):
        response = json.dumps({'type': 'dir', 'entries': []}).encode()
        with patch('subprocess.run', return_value=subprocess.CompletedProcess([], 0, response, b'')):
            with self.assertRaises(Invalid) as caught:
                GhReadOnly(OTHER).content('.github/pr-gate-checks', 'main', 1)
        self.assertEqual(type(caught.exception).__name__, 'SettingFileError')

    def test_cli_refuses_partial_previous_priority_on_recheck_and_case_duplicates(self):
        import importlib.util
        spec = importlib.util.spec_from_file_location('report_cli', CLI)
        cli = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cli)
        snap = snapshot(item(7))
        partial = seal(snap['items'], dict(snap['coverage'], status='INCOMPLETE', errors=['x']))
        with tempfile.TemporaryDirectory() as tmp:
            run, prev = Path(tmp).resolve() / 'runs' / 'run', Path(tmp).resolve() / 'runs' / 'prev'
            save_run(run, {'snapshot.json': snap, 'plan.json': build_plan(snap)})
            save_run(prev, {'snapshot.json': partial})
            for args in (['report', '--run', str(run), '--previous', str(prev)],
                         ['recheck', '--run', str(run), '--target', 'issue:7', '--priority', 'issue:7']):
                with patch.object(cli, 'collector', side_effect=AssertionError('network')) as made:
                    self.assertEqual(cli.main(args + ['--out', str(Path(tmp).resolve() / 'runs' / 'new')]), 2)
                made.assert_not_called()
            with self.assertRaises(Invalid):
                load_config(write_config(tmp, base_config(repositories=[{'name': 'a'}, {'name': 'A'}])))

    def test_unusable_setting_file_is_named_in_the_error(self):
        fake = OtherFake()
        fake.contents['.github/pr-gate-checks'] = 'x' * 201 + '\n'
        snap = Collector(OTHER, fake).collect()
        self.assertEqual(snap['coverage']['status'], 'INCOMPLETE')
        self.assertIn('.github/pr-gate-checks', snap['coverage']['errors'][0])
        fake = OtherFake()
        fake.fail_at = 2
        self.assertNotIn('.github/pr-gate-checks', Collector(OTHER, fake).collect()['coverage']['errors'][0])

    def test_skipped_recheck_keeps_the_result_in_the_report(self):
        fake = Fake()
        fake.meta['private'] = True
        fresh = Collector(REPO, fake).collect()
        snap = snapshot(item(7))
        result = recheck(snap, build_plan(snap), 'issue:7', fresh)
        text = markdown(fresh, diff(fresh), None, result)
        self.assertIn('## 再確認', text)
        self.assertIn('BLOCKED', text)
        self.assertIn('再取得で非公開のため対象外', text)
        previous = snapshot(item(7))
        self.assertIn('前回のrunにあった1件は、今回は取得できない', markdown(fresh, diff(fresh, dict(previous, repo=REPO))))

    def test_recheck_previous_of_another_repository_stops_before_collecting(self):
        import importlib.util
        spec = importlib.util.spec_from_file_location('report_cli', CLI)
        cli = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cli)
        snap = snapshot(item(7))
        other = seal({}, dict(snap['coverage']), repo=OTHER)
        with tempfile.TemporaryDirectory() as tmp:
            run, prev = Path(tmp).resolve() / 'runs' / 'run', Path(tmp).resolve() / 'runs' / 'prev'
            save_run(run, {'snapshot.json': snap, 'plan.json': build_plan(snap)})
            save_run(prev, {'snapshot.json': other})
            with patch.object(cli, 'collector', side_effect=AssertionError('network')) as made:
                code = cli.main(['recheck', '--run', str(run), '--previous', str(prev), '--target', 'issue:7',
                                 '--out', str(Path(tmp).resolve() / 'runs' / 'new')])
            self.assertEqual(code, 2)
            made.assert_not_called()

    def test_repository_text_in_steps_is_escaped(self):
        hostile = ['[承認済み](https://evil.example) <img src=x>']
        plan = build_plan(seal({'pr:25': pr_with()}, snapshot(item(7))['coverage'],
                               settings=dict(SETTINGS, required_checks=hostile)))
        text = json.dumps(plan['candidates']['pr:25']['steps'] + plan['candidates']['pr:25']['hold_reasons'], ensure_ascii=False)
        for raw in ('[承認済み]', '<img', '](https'):
            self.assertNotIn(raw, text)

    def test_recheck_sees_changed_settings(self):
        snap = snapshot(item(7))
        plan = build_plan(snap)
        fresh = seal(snap['items'], snap['coverage'], settings=dict(SETTINGS, required_checks=['build']))
        result = recheck(snap, plan, 'issue:7', fresh)
        self.assertEqual(result['status'], 'STALE')
        self.assertEqual(recheck(snap, plan, 'issue:7', seal(snap['items'], snap['coverage']))['status'], 'CONFIRMED')

    def test_config_version_must_be_the_integer_one(self):
        with tempfile.TemporaryDirectory() as tmp:
            for version in (True, 1.0, '1'):
                with self.subTest(version=version), self.assertRaises(Invalid):
                    load_config(write_config(tmp, dict(base_config(), version=version)))

    def test_report_and_excerpt_refuse_another_repo(self):
        snap = snapshot(item(7))
        with tempfile.TemporaryDirectory() as tmp:
            run = Path(tmp).resolve() / 'runs' / 'a'
            save_run(run, {'snapshot.json': snap, 'plan.json': build_plan(snap)})
            for mode, extra in (('report', ()), ('excerpt', ('--target', 'issue:7'))):
                out = Path(tmp).resolve() / 'runs' / f'{mode}-other'
                proc = subprocess.run([sys.executable, '-I', '-B', str(CLI), mode, '--run', str(run), '--repo', OTHER,
                                       '--out', str(out), *extra], capture_output=True, text=True, timeout=60)
                self.assertEqual(proc.returncode, 2, mode)
                self.assertFalse(out.exists())
                out = Path(tmp).resolve() / 'runs' / f'{mode}-same'
                proc = subprocess.run([sys.executable, '-I', '-B', str(CLI), mode, '--run', str(run), '--repo', REPO,
                                       '--out', str(out), *extra], capture_output=True, text=True, timeout=60)
                self.assertEqual(proc.returncode, 0, proc.stderr)

    def test_setting_lines_keep_an_inner_cr(self):
        from github_work_guide.collector import setting_lines
        self.assertEqual(setting_lines('Sec\rurity\r\nci\r\n'), ['Sec\rurity', 'ci'])

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
