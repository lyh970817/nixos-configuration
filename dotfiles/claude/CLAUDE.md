Use subagents when you think delegation helps.

Set `model` and `effort` explicitly on every Agent call and every workflow
`agent()` — never omit either. Omission is not neutral: it silently falls back
to a default without a decision being made. Choose both purely on your own
judgment of the task, independently of each other: any effort can pair with any
model family. Matching runs in both directions: the strongest family or highest
effort on a routine task is as much a mismatch as a weak one on a hard task, so
the session's own model and effort are options among all of them — chosen
deliberately when the task warrants it, never kept by inheritance.

If subagent or workflow tasks start failing because the current model family is
rate-limited, switch those agents to another suitable family (e.g. Opus) and
continue, telling me — do not let agents fail repeatedly on a rate-limited
model.


