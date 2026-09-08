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

Choose the model family and reasoning effort deliberately for each subagent
task. Set both explicitly when using a model or effort different from the
parent's. A full-history fork (`fork_turns: "all"`) is allowed when deliberately
choosing to inherit the parent's model and effort; omit the overrides in that
case because the spawning tool does not accept them with `"all"`.
