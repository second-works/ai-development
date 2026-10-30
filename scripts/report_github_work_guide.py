#!/usr/bin/env python3
"""Manual collect/report/recheck/excerpt; deliberately no write or execution subcommand.

collect needs --repo, which must be listed in config/github-work-guide.json. recheck reads the
repository of the saved run, which must also be listed. report and excerpt use saved runs only.
"""
import argparse
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from github_work_guide.collector import Collector, Limits  # noqa: E402
from github_work_guide.config import CONFIG, entry, load_config  # noqa: E402
from github_work_guide.core import (OLD_PLAN, Invalid, build_plan, check_output, diff, excerpt, load_run, markdown,  # noqa: E402
                                   read_json, recheck, require, save_run, validate_plan)


def collector(config_path, repo):
    """The only way this CLI reaches GitHub: an allowlisted repository with its configured limits."""
    target = entry(load_config(config_path), repo)
    return Collector(target['repo'], limits=Limits(**target['limits']), required_checks=target['required_checks'])


PRIORITY_ID = re.compile(r'(?:issue|pr):[1-9][0-9]{0,8}\Z')


def planned(snapshot, priority):
    """(plan, problem). A priority ID that is not in this snapshot leaves the plan out but keeps the run."""
    if snapshot['coverage']['status'] != 'COMPLETE':
        return None, None
    missing = [key for key in priority if key not in snapshot['items']]
    if missing:
        return None, 'priority not fetched: ' + ', '.join(missing)
    return build_plan(snapshot, priority), None


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('collect', 'report', 'recheck', 'excerpt'))
    parser.add_argument('--repo', help='owner/name listed in the config (collect; recheck checks it against the run)')
    parser.add_argument('--config', type=Path, default=CONFIG, help='target repositories (default: config/github-work-guide.json)')
    parser.add_argument('--run', type=Path, help='explicit saved planning run')
    parser.add_argument('--previous', type=Path, help='explicit previous run')
    parser.add_argument('--target', help='candidate ID, e.g. issue:26')
    parser.add_argument('--priority', nargs='*', default=[], help='human supplied IDs; dependencies take precedence')
    parser.add_argument('--out', type=Path, required=True, help='new runs/<name> directory')
    args = parser.parse_args(argv)
    try:
        require(args.mode != 'collect' or args.repo is not None, '--repo required')
        require(args.mode == 'collect' or args.run is not None, '--run required')
        require(args.mode not in ('recheck', 'excerpt') or args.target is not None, '--target required')
        # Every saved input is loaded once, and all of them must be of one repository before any network read.
        saved = load_run(args.run) if args.mode != 'collect' else None
        repo = args.repo if saved is None else saved['repo']
        # A saved run names its repository; a different --repo is a mistake, not a filter.
        require(args.repo is None or args.repo == repo, 'run is for another repository')
        previous = load_run(args.previous) if args.previous else None
        require(previous is None or previous['repo'] == repo, '--previous is a run of another repository')
        # An empty or partial baseline would show every item as ADDED.
        require(previous is None or previous['coverage']['status'] == 'COMPLETE', '--previous is not a complete run')
        # recheck keeps the saved plan's priority; a new one would be silently ignored.
        require(args.mode != 'recheck' or not args.priority, 'recheck does not take --priority')
        if args.mode == 'excerpt':
            # Saved-run read only: verified manifest/hash, complete acquisition and a matching saved plan.
            require(args.previous is None and not args.priority, 'excerpt does not take --previous/--priority')
            snapshot = saved
            require('plan.json' in read_json(args.run / 'manifest.json')['files'], 'saved plan required')
            text = excerpt(snapshot, read_json(args.run / 'plan.json'), args.target, args.run.name)
            save_run(args.out, {'excerpt.md': text})
            print(f'excerpt={len(text)} chars target={args.target} out={args.out}')
            return 0
        # The output and the priority format are checked before any network read, so neither loses a collection.
        check_output(args.out, new=True)
        require(all(isinstance(x, str) and PRIORITY_ID.fullmatch(x) for x in args.priority)
                and len(set(args.priority)) == len(args.priority), 'invalid priority')
        result, problem = None, None
        if args.mode == 'collect':
            snapshot = collector(args.config, repo).collect()
            plan, problem = planned(snapshot, args.priority)
        else:
            snapshot = saved
            if args.mode == 'recheck':
                require('plan.json' in read_json(args.run / 'manifest.json')['files'], 'saved plan required')
                plan = read_json(args.run / 'plan.json')
                validate_plan(snapshot, plan)
                require(args.target in plan['candidates'], 'unknown candidate')
                fresh = collector(args.config, snapshot['repo']).collect()
                result = recheck(snapshot, plan, args.target, fresh)
                snapshot = fresh
                # A priority item that has gone (transferred, deleted) must not hide the recheck result.
                plan, problem = planned(fresh, plan['priority'])
            else:
                plan, problem = planned(snapshot, args.priority)
        changes = diff(snapshot, previous)
        documents = {'snapshot.json': snapshot, 'diff.json': changes,
                     'report.md': markdown(snapshot, changes, plan, result, problem)}
        if plan is not None:
            documents['plan.json'] = plan
        if result is not None:
            documents['recheck.json'] = result
        save_run(args.out, documents)
        skipped = f' skipped={snapshot["coverage"]["skipped"]}' if snapshot['coverage']['status'] == 'SKIPPED' else ''
        print(f'repo={snapshot["repo"]} coverage={snapshot["coverage"]["status"]}{skipped} items={len(snapshot["items"])} out={args.out}')
        if result:
            print(f'dry_run={result["status"]}')
        if problem:
            print(f'BLOCKED: {problem}（planは作っていない。取得結果とreport.mdは保存した）', file=sys.stderr)
            return 2
        # A private repository is reported, not failed. A 404 is not: with the owner's gh, a listed repository
        # that cannot be seen at all is most likely a misspelled entry in the config.
        reported = snapshot['coverage']['status'] == 'COMPLETE' or snapshot['coverage'].get('skipped') == 'private'
        return 0 if reported and (not result or result['status'] == 'CONFIRMED') else 2
    except (Invalid, OSError, KeyError, TypeError, AttributeError, ValueError) as error:
        # Only fixed messages are printed; raw errors may carry remote text or auth diagnostics.
        if isinstance(error, Invalid) and str(error) == OLD_PLAN:
            print(f'BLOCKED: {OLD_PLAN}', file=sys.stderr)
            return 2
        print('BLOCKED: 入力/取得/保存を検証できません。原本と新規出力先を確認してください。', file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
