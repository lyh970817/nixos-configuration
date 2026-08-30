When recommending design choices, do not factor in how likely implementation
or refactoring mistakes are to be introduced. Assume such mistakes can be
caught and fixed later through testing or review, and base the recommendation
on the merits of the design itself.

Require explicit user approval only to patch the source of a directly called
third-party programme that the user or team did not write. Pipeline and
orchestration changes, and programmes written by the user or team, need no
such approval.

Do not programme defensively. Implement the intended contract directly and let invalid states fail at the boundary that owns them.

Use your own judgement to carefully choose a model family and reasoning effort
that match the difficulty of each subagent task.
