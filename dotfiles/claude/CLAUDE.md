Use subagents when you think delegation helps.

Set `model` explicitly on every Agent call and every workflow `agent()` — never
omit it. Omission is not neutral: it silently falls back to a default without a
decision being made. Choose the model family for each task purely on your own
judgment of the task's difficulty. Matching runs in both directions: the
strongest family on a routine task is as much a mismatch as a weak family on a
hard one, so the session's own model is one option among all of them — chosen
deliberately when the task warrants it, never kept by inheritance.

Reasoning effort is chosen independently of model, via the named subagents
`effort-low` through `effort-max`; any effort can pair with any family, and
both choices are yours to make freely per task. The `model: opus` in their
frontmatter is only a safety net for a forgotten parameter — an explicit
`model` on the call always overrides it — not a recommendation.

If subagent or workflow tasks start failing because the current model family is
rate-limited, switch those agents to another suitable family (e.g. Opus) and
continue, telling me — do not let agents fail repeatedly on a rate-limited
model.


