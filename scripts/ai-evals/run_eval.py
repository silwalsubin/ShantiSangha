#!/usr/bin/env python3
"""
Chart-chat eval harness.

Mirrors skill-creator's workspace + benchmark layout so its eval-viewer
(`generate_review.py`) can render the qualitative outputs and benchmark
side-by-side. But evals run against the real production model (GPT-4o
via OpenAI API), not a Claude Code subagent — so what we measure reflects
what production users actually get.

For each eval in evals/evals.json, the harness:

  1. Builds the system prompt via prompts/for_chart.py (mirrors C# ForChart)
  2. Runs the prompt against GPT-4o N times (default 3) for variance
  3. For each run, the judge (Claude Sonnet 4.6) marks each `expectation`
     as pass/fail with evidence
  4. Writes:
       workspace/<iteration>/
         eval-<name>/
           eval_metadata.json
           with_skill/run-<k>/
             outputs/response.md
             transcript.md
             grading.json
             timing.json
         benchmark.json

Then run skill-creator's viewer:

  python ~/.claude/skills/skill-creator/eval-viewer/generate_review.py \\
    workspace/<iteration> \\
    --skill-name chart-reader \\
    --benchmark workspace/<iteration>/benchmark.json

Usage:
  OPENAI_API_KEY=... ANTHROPIC_API_KEY=... python run_eval.py
  python run_eval.py --iteration baseline --runs 3 --temperature 0.7
  python run_eval.py --eval marriage_grounded --runs 1 --temperature 0
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import statistics
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import yaml
from openai import AsyncOpenAI
from rich.console import Console
from rich.table import Table

ROOT = Path(__file__).parent
sys.path.insert(0, str(ROOT))

from prompts.for_chart import build_for_chart  # noqa: E402
from prompts.judge import JUDGE_SYSTEM, build_judge_user_message  # noqa: E402

RESPONSE_MODEL = "gpt-4o"
# gpt-4o-mini for the judge: much higher TPM ceiling than gpt-4o on tier-1
# orgs, ~10x cheaper, and the judging task is structured pass/fail against a
# rubric — it doesn't need gpt-4o's full reasoning. The tradeoff is slightly
# noisier scoring; small enough for v0.
JUDGE_MODEL = "gpt-4o-mini"

# Cap concurrent in-flight calls. Two rounds of gpt-4o response (~3K tokens
# each) won't exceed the 30K-TPM ceiling, and the judge model has its own
# (much higher) limit so it isn't the bottleneck.
MAX_CONCURRENT_CALLS = 2
MAX_RETRIES = 6

console = Console()


# --- I/O helpers ---


def load_chart(name: str) -> dict:
    path = ROOT / "fixtures" / f"{name}.yaml"
    with path.open() as f:
        return yaml.safe_load(f)


def load_evals() -> dict:
    with (ROOT / "evals" / "evals.json").open() as f:
        return json.load(f)


def write_json(path: Path, data: dict | list) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w") as f:
        json.dump(data, f, indent=2)


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w") as f:
        f.write(text)


# --- Model calls ---


async def generate_response(
    client: AsyncOpenAI,
    system_prompt: str,
    user_query: str,
    temperature: float,
) -> tuple[str, int, float]:
    """Returns (text, total_tokens, duration_ms)."""
    start = time.monotonic()
    resp = await client.chat.completions.create(
        model=RESPONSE_MODEL,
        temperature=temperature,
        messages=[
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_query},
        ],
    )
    duration_ms = (time.monotonic() - start) * 1000
    text = resp.choices[0].message.content or ""
    total_tokens = resp.usage.total_tokens if resp.usage else 0
    return text, total_tokens, duration_ms


async def judge_response(
    client: AsyncOpenAI,
    system_prompt: str,
    user_query: str,
    model_response: str,
    expectations: list[str],
) -> list[dict]:
    """
    Asks GPT-4o to grade each expectation as pass/fail with evidence.
    response_format=json_object guarantees the model returns parseable JSON.
    Returns list of {text, passed, evidence} dicts (skill-creator schema).
    """
    user_msg = build_judge_user_message(
        system_prompt, user_query, model_response, expectations
    )
    resp = await client.chat.completions.create(
        model=JUDGE_MODEL,
        temperature=0,
        response_format={"type": "json_object"},
        messages=[
            {"role": "system", "content": JUDGE_SYSTEM},
            {"role": "user", "content": user_msg},
        ],
    )
    text = (resp.choices[0].message.content or "").strip()
    parsed = json.loads(text)
    return parsed["expectations"]


# --- Run mechanics ---


async def run_single(
    eval_def: dict,
    run_number: int,
    iteration_dir: Path,
    openai_client: AsyncOpenAI,
    temperature: float,
    semaphore: asyncio.Semaphore,
) -> dict:
    """Runs one (eval, config=with_skill, run_number) and writes its files.

    Returns the run record for benchmark.json.
    """
    chart = load_chart(eval_def["chart"])
    display_name = chart.get("display_name")
    passages = eval_def.get("passages") or []
    expectations = eval_def["expectations"]

    system_prompt = build_for_chart(
        display_name=display_name,
        chart=chart,
        passages=passages,
        reading=None,
    )

    async with semaphore:
        response, total_tokens, duration_ms = await generate_response(
            openai_client, system_prompt, eval_def["prompt"], temperature
        )

    async with semaphore:
        graded = await judge_response(
            openai_client, system_prompt, eval_def["prompt"], response, expectations
        )

    passed = sum(1 for g in graded if g.get("passed"))
    total = len(graded)
    pass_rate = passed / total if total else 0.0

    run_dir = iteration_dir / f"eval-{eval_def['eval_name']}" / "with_skill" / f"run-{run_number}"
    run_dir.mkdir(parents=True, exist_ok=True)

    write_text(run_dir / "outputs" / "response.md", response)
    write_text(
        run_dir / "transcript.md",
        f"# {eval_def['eval_name']} — run {run_number}\n\n"
        f"## System prompt\n\n```\n{system_prompt}\n```\n\n"
        f"## User\n\n{eval_def['prompt']}\n\n"
        f"## Assistant\n\n{response}\n",
    )
    write_json(
        run_dir / "grading.json",
        {
            "expectations": graded,
            "summary": {
                "passed": passed,
                "failed": total - passed,
                "total": total,
                "pass_rate": round(pass_rate, 3),
            },
            "timing": {"total_duration_seconds": round(duration_ms / 1000, 2)},
        },
    )
    write_json(
        run_dir / "timing.json",
        {
            "total_tokens": total_tokens,
            "duration_ms": int(duration_ms),
            "total_duration_seconds": round(duration_ms / 1000, 2),
        },
    )

    return {
        "eval_id": eval_def["id"],
        "eval_name": eval_def["eval_name"],
        "configuration": "with_skill",
        "run_number": run_number,
        "result": {
            "pass_rate": round(pass_rate, 3),
            "passed": passed,
            "failed": total - passed,
            "total": total,
            "time_seconds": round(duration_ms / 1000, 2),
            "tokens": total_tokens,
            "tool_calls": 0,
            "errors": 0,
        },
        "expectations": graded,
        "notes": [],
    }


# --- Benchmark aggregation ---


def aggregate_runs(runs: list[dict]) -> dict:
    """Group runs by configuration and compute mean/stddev for benchmark.json."""
    by_config: dict[str, list[dict]] = {}
    for r in runs:
        by_config.setdefault(r["configuration"], []).append(r)

    summary: dict[str, dict] = {}
    for config, items in by_config.items():
        pass_rates = [i["result"]["pass_rate"] for i in items]
        times = [i["result"]["time_seconds"] for i in items]
        tokens = [i["result"]["tokens"] for i in items]
        summary[config] = {
            "pass_rate": stats(pass_rates),
            "time_seconds": stats(times),
            "tokens": stats(tokens),
        }
    return summary


def stats(values: list[float]) -> dict:
    if not values:
        return {"mean": 0, "stddev": 0, "min": 0, "max": 0}
    return {
        "mean": round(statistics.mean(values), 3),
        "stddev": round(statistics.stdev(values), 3) if len(values) > 1 else 0.0,
        "min": round(min(values), 3),
        "max": round(max(values), 3),
    }


def write_benchmark(
    iteration_dir: Path,
    runs: list[dict],
    eval_names: list[str],
    runs_per_config: int,
) -> Path:
    benchmark = {
        "metadata": {
            "skill_name": "chart-reader",
            "skill_path": str(ROOT),
            "executor_model": RESPONSE_MODEL,
            "analyzer_model": JUDGE_MODEL,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "evals_run": eval_names,
            "runs_per_configuration": runs_per_config,
        },
        "runs": runs,
        "run_summary": aggregate_runs(runs),
        "notes": [],
    }
    path = iteration_dir / "benchmark.json"
    write_json(path, benchmark)
    return path


# --- Eval metadata files (sibling to with_skill/) ---


def write_eval_metadata(iteration_dir: Path, eval_def: dict) -> None:
    path = iteration_dir / f"eval-{eval_def['eval_name']}" / "eval_metadata.json"
    write_json(
        path,
        {
            "eval_id": eval_def["id"],
            "eval_name": eval_def["eval_name"],
            "prompt": eval_def["prompt"],
            "expected_output": eval_def.get("expected_output", ""),
            "expectations": eval_def["expectations"],
        },
    )


# --- Display ---


def render_summary(runs: list[dict], eval_names: list[str]) -> None:
    table = Table(title="Per-eval pass rate (mean across runs)", show_lines=False)
    table.add_column("eval", style="cyan", no_wrap=True)
    table.add_column("pass rate", justify="right")
    table.add_column("runs", justify="right")
    table.add_column("avg time (s)", justify="right")
    table.add_column("avg tokens", justify="right")

    by_eval: dict[str, list[dict]] = {}
    for r in runs:
        by_eval.setdefault(r["eval_name"], []).append(r)

    for name in eval_names:
        items = by_eval.get(name, [])
        if not items:
            continue
        pass_rates = [i["result"]["pass_rate"] for i in items]
        times = [i["result"]["time_seconds"] for i in items]
        tokens = [i["result"]["tokens"] for i in items]
        mean_pr = statistics.mean(pass_rates)
        color = "green" if mean_pr >= 0.8 else ("yellow" if mean_pr >= 0.5 else "red")
        table.add_row(
            name,
            f"[{color}]{mean_pr:.0%}[/{color}]",
            str(len(items)),
            f"{statistics.mean(times):.1f}",
            f"{int(statistics.mean(tokens))}",
        )

    console.print(table)


# --- Entry point ---


async def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--iteration",
        default="iteration-1",
        help="Iteration directory under workspace/ (e.g., 'baseline', 'iteration-2')",
    )
    parser.add_argument("--eval", help="Run only the eval with this eval_name")
    parser.add_argument("--runs", type=int, default=3, help="Runs per eval (variance)")
    parser.add_argument(
        "--temperature",
        type=float,
        default=0.7,
        help="Response temperature (production-realistic ~0.7; use 0 for reproducibility)",
    )
    args = parser.parse_args()

    if not os.getenv("OPENAI_API_KEY"):
        console.print("[red]OPENAI_API_KEY not set[/red]")
        return 2

    spec = load_evals()
    evals = spec["evals"]
    if args.eval:
        evals = [e for e in evals if e["eval_name"] == args.eval]
        if not evals:
            console.print(f"[red]No eval with name {args.eval}[/red]")
            return 2

    iteration_dir = ROOT / "workspace" / args.iteration
    iteration_dir.mkdir(parents=True, exist_ok=True)

    for ev in evals:
        write_eval_metadata(iteration_dir, ev)

    openai_client = AsyncOpenAI(max_retries=MAX_RETRIES)
    semaphore = asyncio.Semaphore(MAX_CONCURRENT_CALLS)

    console.print(
        f"Iteration [bold]{args.iteration}[/bold] — "
        f"{len(evals)} eval(s) × {args.runs} run(s) "
        f"against [cyan]{RESPONSE_MODEL}[/cyan] "
        f"(judge: [magenta]{JUDGE_MODEL}[/magenta], temp={args.temperature}, "
        f"max_concurrent={MAX_CONCURRENT_CALLS})"
    )

    tasks = []
    for ev in evals:
        for run_number in range(1, args.runs + 1):
            tasks.append(
                run_single(
                    ev,
                    run_number,
                    iteration_dir,
                    openai_client,
                    args.temperature,
                    semaphore,
                )
            )

    runs = await asyncio.gather(*tasks)
    runs.sort(key=lambda r: (r["eval_id"], r["run_number"]))

    eval_names = [e["eval_name"] for e in evals]
    benchmark_path = write_benchmark(iteration_dir, runs, eval_names, args.runs)

    render_summary(runs, eval_names)

    skill_creator_viewer = (
        Path.home() / ".claude/skills/skill-creator/eval-viewer/generate_review.py"
    )
    console.print(f"\n[bold]Benchmark[/bold]: {benchmark_path}")
    console.print(f"[bold]Workspace[/bold]: {iteration_dir}")
    if skill_creator_viewer.exists():
        console.print(
            "\n[bold]Open the viewer:[/bold]\n"
            f"  python {skill_creator_viewer} {iteration_dir} \\\n"
            f"    --skill-name chart-reader \\\n"
            f"    --benchmark {benchmark_path}"
        )
    else:
        console.print(
            "\n[yellow]skill-creator's eval-viewer not found at "
            f"{skill_creator_viewer}. JSON outputs are still in {iteration_dir}.[/yellow]"
        )

    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
