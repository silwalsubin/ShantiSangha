# Chart-Chat Eval Harness

A regression harness for the chart-chat system prompt. Lets you change the
prompt and measure whether the chart-reading conversation got better, worse,
or the same — instead of guessing.

This harness mirrors the workflow from `skill-creator` (test cases →
expectations → benchmark → human review viewer), but **runs against
production GPT-4o** rather than a Claude Code subagent. The output files
are written in `skill-creator`'s schema so its `eval-viewer` works on them
directly.

## Why this exists

The chart chat answers were drifting hedgy and generic. Two failure modes:

1. **Hedgy** — uses "may" / "could" even when the chart facts are clear
2. **Generic** — answers could apply to anyone, doesn't reference the user's
   actual placements

Both trace back to the same root cause: contradictions in the system prompt
("state it as a fact" vs. "use tendency language"). To fix without breaking
other things, we need a baseline + scoring.

## What it does

For each eval in `evals/evals.json`:

1. Builds the same `ForChart` system prompt the backend builds, using
   fixture chart data + the eval's retrieved passages.
2. Calls **GPT-4o** with the user query (matches production).
3. Sends (system prompt, query, response, expectations) to **Claude
   Sonnet 4.6 as judge** with a strict rubric.
4. Judge returns pass/fail + evidence per expectation.
5. Runs N times for variance; aggregates mean/stddev.
6. Writes a workspace tree and `benchmark.json` matching skill-creator's
   schema so the existing eval-viewer renders both qualitative outputs and
   quantitative benchmark.

## Setup

```bash
cd scripts/ai-evals
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
export OPENAI_API_KEY=sk-...
export ANTHROPIC_API_KEY=sk-ant-...
```

## Run a baseline

```bash
python run_eval.py --iteration baseline --runs 3
```

That writes `workspace/baseline/` with:

```
workspace/baseline/
├── benchmark.json
└── eval-marriage_grounded/
    ├── eval_metadata.json
    └── with_skill/
        ├── run-1/
        │   ├── outputs/response.md
        │   ├── transcript.md
        │   ├── grading.json
        │   └── timing.json
        ├── run-2/...
        └── run-3/...
```

Then open the skill-creator viewer (the runner prints the exact command):

```bash
python ~/.claude/skills/skill-creator/eval-viewer/generate_review.py \
  workspace/baseline \
  --skill-name chart-reader \
  --benchmark workspace/baseline/benchmark.json
```

The viewer has two tabs: **Outputs** (click through each test case, leave
feedback that auto-saves) and **Benchmark** (per-eval pass-rate / time / token
table with mean ± stddev).

## Iterate on the prompt

The Python port of `SystemPrompt.ForChart` lives at `prompts/for_chart.py`.
**This is not the production prompt** — that lives in
[`backend/ShantiSangha.Chat/AI/SystemPrompt.cs`](../../backend/ShantiSangha.Chat/AI/SystemPrompt.cs).
The Python copy mirrors it.

Workflow:

1. Run `python run_eval.py --iteration baseline` to lock in your starting
   point.
2. Edit `prompts/for_chart.py`.
3. Run `python run_eval.py --iteration iteration-2`.
4. Open the viewer with `--previous-workspace workspace/baseline`. The
   viewer renders side-by-side diffs of each output and the benchmark
   delta.
5. Once a change wins on the eval, **port the same change verbatim back
   to `SystemPrompt.cs`**. The Python and C# prompts must stay locked.
6. Repeat.

## Adding test cases

Edit `evals/evals.json`. Each eval is:

```json
{
  "id": 7,
  "eval_name": "descriptive_name",
  "prompt": "What the user types",
  "expected_output": "Plain-English description of a good answer",
  "chart": "chart_a",
  "passages": [
    { "title": "...", "source": "...", "content": "..." }
  ],
  "expectations": [
    "Mentions Saturn in the 7th specifically by house",
    "Does not hedge with 'may' on chart facts",
    "Does not ask for birth details"
  ]
}
```

`expectations` is a flat list of single statements. Positive and negative
forms both work — the judge grades each as pass/fail. Keep them
**discriminating**: an expectation that always passes regardless of the
prompt isn't useful.

When you find a real bad output in production, capture it as a new eval —
paste the chart, the actual retrieved passages, the actual question. The
suite then prevents regression.

## Single-eval iteration

For tight loops on one stubborn case:

```bash
python run_eval.py --eval marriage_grounded --runs 1 --temperature 0
```

`temperature 0` makes the response near-deterministic for fast prompt
iteration. Switch back to `--temperature 0.7 --runs 3` before declaring
victory — you want variance data before you trust a number.

## Cost

Each full run with 6 evals × 3 runs ≈ Tune.30 (GPT-4o response × 18 + Claude
judge × 18). Cheap enough to run on every prompt change.
