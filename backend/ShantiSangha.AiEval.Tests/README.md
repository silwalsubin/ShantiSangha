# ShantiSangha.AiEval.Tests

Golden-set regression suite for ShantiSangha's AI surfaces. Every prompt
change, model switch, or retrieval tweak should pass this suite before
shipping.

## What's here today

| File | What it tests |
|---|---|
| `GoldenSets/chart_chat_topic_routing.json` | 12 representative chart-chat questions; each declares the signature families that MUST appear in the top-K after `ChartTopicRouter.Rerank` runs. |
| `ChartChatTopicRoutingTests.cs` | Deterministic test harness. Runs each case against a synthetic (planet × house) passage pool and asserts the rerank hits the expected signatures. **No DB, no LLM, CI-safe.** |
| `Agent/QuickActionSuggesterEvalTests.cs` | Behavioral eval for the assistant's quick-action chips. Asserts trivial replies yield ZERO chips (sparseness) and actionable replies yield 1–3 well-formed chips (helpfulness). **Live — hits gpt-4o-mini, gated behind `AI_EVAL_LIVE=1`.** |

Run (deterministic, CI-safe — live evals show as skipped):

```bash
cd backend
dotnet test ShantiSangha.AiEval.Tests/
```

Run the live lane (spends OpenAI tokens):

```bash
cd backend
AI_EVAL_LIVE=1 OPENAI_API_KEY=sk-... dotnet test ShantiSangha.AiEval.Tests/
```

## Adding a case

1. Open `GoldenSets/chart_chat_topic_routing.json`.
2. Write the query the way a real user asks it — casual, lowercase, maybe
   misspelled. Don't rewrite it into "proper" astrology terms.
3. Name the classical houses + planets the question touches.
4. Pick 1–3 `signature_prefix` values the rerank MUST float to the top
   (e.g. `"mars_in_h"` for any Manglik question).
5. Run the tests. If they fail, update `ChartTopicRouter.cs` keywords,
   not the expectations.

## What's NOT here yet (and the plan)

- **LLM-as-judge generation tests.** For each golden query, run the full
  chart-chat pipeline (with a real chart fixture + live retrieval) and
  have Claude Sonnet score the output against a rubric: is it grounded
  in retrieved passages, does it hedge, does it invent, does it quote
  sources it's told not to. Gate on `AI_EVAL_LIVE=1` so PR CI stays
  free of API spend.
- **Retrieval-pipeline integration tests.** Spin up pgvector via
  Testcontainers, load the corpus, and verify each golden query returns
  the expected passages end-to-end (not just the rerank step).
- **Daily reflection / portrait / chart reading golden sets.** Same
  pattern, different surfaces. Reflections want checks that data
  references actually appear; portraits want voice-consistency checks.

The point of this scaffold is to make the cheap, deterministic tests
cheap AND pass in CI today. LLM-judge tests require live API keys, so
they belong in a separate gated lane (now established by the
`AI_EVAL_LIVE=1` gate the quick-action eval uses). Build the rest next.
