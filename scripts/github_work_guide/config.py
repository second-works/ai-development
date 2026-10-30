"""Target repositories for the work guide: config/github-work-guide.json (the only allowlist)."""
from pathlib import Path

from .collector import Limits
from .core import Invalid, names, read_json, repo_name, require

ROOT = Path(__file__).resolve().parents[2]
CONFIG = ROOT / 'config/github-work-guide.json'
OWNER = 'second-works'
LIMIT_KEYS = ('pages', 'items', 'calls', 'seconds')
TOP_KEYS = {'version', 'owner', 'limits', 'repositories'}
ENTRY_KEYS = {'name', 'required_checks', 'limits', 'format'}
FORMATS = ('auto', 'full', 'simple')


def limits_value(value):
    """Only the keys are checked here; Limits checks each value and its maximum."""
    require(isinstance(value, dict) and set(value) <= set(LIMIT_KEYS), 'limits keys')
    return value


def load_config(path=CONFIG):
    """Returns {'owner', 'limits', 'repositories': {full_name: entry}}. Unknown keys are refused."""
    value = read_json(path)
    require(isinstance(value, dict) and set(value) <= TOP_KEYS and {'version', 'owner', 'repositories'} <= set(value),
            'config keys')
    require(type(value['version']) is int and value['version'] == 1, 'config version')
    # One organisation: the config cannot widen the reads to another owner.
    require(value['owner'] == OWNER, 'config owner')
    defaults = limits_value(value.get('limits', {}))
    Limits(**defaults)
    rows = value['repositories']
    require(isinstance(rows, list) and rows, 'config repositories')
    repositories, seen = {}, set()
    for row in rows:
        require(isinstance(row, dict) and set(row) <= ENTRY_KEYS and 'name' in row, 'repository entry keys')
        full = repo_name(f'{OWNER}/{row["name"]}') if isinstance(row['name'], str) and '/' not in row['name'] else None
        # GitHub names ignore case, so two spellings of one repository are one entry.
        require(full is not None and full.lower() not in seen, 'repository entry name')
        seen.add(full.lower())
        limits = {**defaults, **limits_value(row.get('limits', {}))}
        Limits(**limits)  # over the maximum: refused here, not at the first collect
        # format: how the weekly check reads this repository. auto decides from the default branch (#220).
        require(row.get('format', 'auto') in FORMATS, 'repository format')
        entry = {'repo': full, 'limits': limits, 'format': row.get('format', 'auto'),
                 'required_checks': names(row['required_checks']) if 'required_checks' in row else None}
        repositories[full] = entry
    return {'owner': OWNER, 'limits': defaults, 'repositories': repositories}


def entry(config, repo):
    require(repo in config['repositories'], 'repository not allowlisted')
    return config['repositories'][repo]


__all__ = ['CONFIG', 'Invalid', 'entry', 'load_config']
