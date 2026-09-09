When recommending design choices, do not factor in how likely implementation
or refactoring mistakes are to be introduced. Assume such mistakes can be
caught and fixed later through testing or review, and base the recommendation
on the merits of the design itself.

For browser tasks, read ~/.config/agent-browser-selection.md before selecting a browser.

Require explicit user approval only to patch the source of a directly called
third-party programme that the user or team did not write. Pipeline and
orchestration changes, and programmes written by the user or team, need no
such approval.

Do not programme defensively. Implement the intended contract directly and let invalid states fail at the boundary that owns them.

For every delegated task, including nested delegation, choose the most
economical model and reasoning effort sufficient for the scoped outcome.
State the choice and a brief task-specific reason in the spawning brief.

Choose the model and effort before choosing how much history to pass.
Use `fork_turns: "all"` only when the task independently warrants the
parent's model and effort. Otherwise, supply the necessary context with
`fork_turns: "none"` or a positive history count, and set both `model`
and `reasoning_effort` explicitly.
