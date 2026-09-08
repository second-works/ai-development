#!/usr/bin/env python3
"""Render a local, static HTML status report from a GitHub observation JSON."""

from __future__ import annotations

import argparse
import html
import json
import os
import sys
import tempfile
from pathlib import Path
from typing import Any, Mapping


class RenderError(Exception):
    """A safe, user-actionable rendering failure."""


def text(value: Any, fallback: str = "未観測") -> str:
    if value is None:
        return fallback
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (str, int, float)):
        return str(value)
    return fallback


def item(value: Any) -> Mapping[str, Any]:
    return value if isinstance(value, dict) else {}


def list_items(value: Any) -> list[Mapping[str, Any]]:
    return [entry for entry in value if isinstance(entry, dict)] if isinstance(value, list) else []


def escape(value: Any, fallback: str = "未観測") -> str:
    return html.escape(text(value, fallback), quote=True)


def status_row(label: str, value: Any) -> str:
    return f"<tr><th>{html.escape(label)}</th><td>{escape(value)}</td></tr>"


def report_rows(title: str, records: list[Mapping[str, Any]]) -> str:
    if not records:
        return f"<section><h2>{html.escape(title)}</h2><p>該当する観測はありません。</p></section>"
    rows = []
    for record in records:
        rows.append(
            "<tr>"
            f"<td>{escape(record.get('name'), '名称未観測')}</td>"
            f"<td>{escape(record.get('status'))}</td>"
            f"<td>{escape(record.get('conclusion'))}</td>"
            f"<td>{escape(record.get('head_sha'))}</td>"
            "</tr>"
        )
    return (
        f"<section><h2>{html.escape(title)}</h2>"
        "<table><thead><tr><th>名称</th><th>状態</th><th>結果</th><th>対象SHA</th></tr></thead>"
        f"<tbody>{''.join(rows)}</tbody></table></section>"
    )


def render(observation: Mapping[str, Any], source_path: Path) -> str:
    collection = item(observation.get("collection"))
    issue = item(observation.get("issue"))
    pull_request = item(observation.get("pull_request"))
    head = item(observation.get("head_consistency"))
    workflows = item(observation.get("workflow_runs"))
    reviews = item(observation.get("reviews"))
    comments = item(observation.get("review_comments"))
    remaining: list[str] = []
    if collection.get("status") != "COMPLETE":
        remaining.append("収集が完了していません。errorsを確認してください。")
    if issue.get("observation_status") != "OBSERVED":
        remaining.append("Issueの観測がありません。")
    if pull_request and pull_request.get("observation_status") != "OBSERVED":
        remaining.append("Pull Requestの観測がありません。")
    if head.get("status") == "MISMATCH":
        remaining.append("収集中にPR head SHAが変わりました。再収集が必要です。")
    if not remaining:
        remaining.append("このレポートは観測結果だけです。CI、Security、Review、受入、マージ可否は別途確認してください。")

    errors = list_items(collection.get("errors"))
    error_html = "".join(
        f"<li>{escape(error.get('operation'))}: {escape(error.get('kind'))} — {escape(error.get('detail'))}</li>"
        for error in errors
    ) or "<li>なし</li>"
    remaining_html = "".join(f"<li>{html.escape(message)}</li>" for message in remaining)
    all_runs = list_items(workflows.get("security_named_runs")) + list_items(workflows.get("other_runs"))

    return f"""<!doctype html>
<html lang="ja">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>GitHub Status Report</title>
<style>body{{font-family:system-ui,-apple-system,sans-serif;line-height:1.5;margin:0;color:#17202a;background:#f7f9fb}}main{{max-width:1050px;margin:auto;padding:24px}}section{{background:#fff;border:1px solid #d9e1e8;border-radius:8px;padding:18px;margin:16px 0;overflow-wrap:anywhere}}table{{border-collapse:collapse;width:100%;min-width:560px}}th,td{{border:1px solid #d9e1e8;padding:8px;text-align:left;vertical-align:top}}th{{background:#eef3f7}}.scroll{{overflow-x:auto}}code{{font-family:ui-monospace,monospace}}@media(max-width:640px){{main{{padding:12px}}section{{padding:12px}}}}</style>
</head><body><main>
<h1>GitHub Status Report</h1><p>ローカルJSONから生成した静的レポートです。外部資産・ネットワーク通信は使用しません。</p>
<section><h2>正本と収集時点</h2><div class="scroll"><table><tbody>
{status_row('入力JSON', str(source_path))}{status_row('正本リポジトリ', observation.get('repository'))}{status_row('観測時刻', observation.get('observed_at'))}{status_row('観測状態', collection.get('status'))}{status_row('State更新に利用可能', collection.get('usable_for_state_update'))}
</tbody></table></div></section>
<section><h2>対象</h2><div class="scroll"><table><tbody>
{status_row('Issue番号', issue.get('number'))}{status_row('Issue状態', issue.get('state'))}{status_row('Issue参照', issue.get('source_url'))}{status_row('PR番号', pull_request.get('number'))}{status_row('PR状態', pull_request.get('state'))}{status_row('PRマージ済み', pull_request.get('merged'))}{status_row('対象head SHA', pull_request.get('head_sha'))}{status_row('head整合性', head.get('status'))}
</tbody></table></div></section>
{report_rows('Workflow実行', all_runs)}
<section><h2>レビュー観測</h2><div class="scroll"><table><tbody>
{status_row('同一headのレビュー数', len(list_items(reviews.get('same_head'))))}{status_row('同一headのコメント数', len(list_items(comments.get('same_head'))))}{status_row('レビュー証拠状態', reviews.get('target_head_evidence_status'))}
</tbody></table></div></section>
<section><h2>未観測・残作業</h2><ul>{remaining_html}</ul><h3>収集エラー</h3><ul>{error_html}</ul></section>
<section><h2>解釈の境界</h2><p>{escape(observation.get('interpretation'))}</p></section>
</main></body></html>"""


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Render a local HTML status report from an observation JSON file.")
    parser.add_argument("input", type=Path, help="Existing observation JSON file")
    parser.add_argument("--output", required=True, type=Path, help="New HTML output path")
    return parser.parse_args(argv)


def write_new_output(path: Path, rendered: str) -> None:
    if path.exists():
        raise RenderError("output already exists; refusing to overwrite it")
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
        temporary = Path(temporary_name)
        try:
            with os.fdopen(descriptor, "w", encoding="utf-8") as destination:
                destination.write(rendered)
            os.link(temporary, path)
        finally:
            if temporary.exists():
                temporary.unlink()
    except OSError as error:
        raise RenderError("could not write output") from error


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    if args.input.resolve() == args.output.resolve():
        print("input and output paths must differ", file=sys.stderr)
        return 2
    try:
        raw = args.input.read_text(encoding="utf-8")
        observation = json.loads(raw)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        print(f"input error: {error}", file=sys.stderr)
        return 2
    if not isinstance(observation, dict):
        print("input error: JSON root must be an object", file=sys.stderr)
        return 2
    try:
        write_new_output(args.output, render(observation, args.input))
    except RenderError as error:
        print(f"output error: {error}", file=sys.stderr)
        return 3
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
