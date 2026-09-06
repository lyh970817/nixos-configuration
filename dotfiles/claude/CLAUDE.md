Use subagents when you think delegation helps.

Use your own judgement to carefully choose a model family that matches the
difficulty of the task.

Reasoning effort is chosen independently of model, via the named subagents
`effort-low` through `effort-max`.

If subagent or workflow tasks start failing because the current model family is
rate-limited, switch those agents to another suitable family (e.g. Opus) and
continue, telling me — do not let agents fail repeatedly on a rate-limited
model.


