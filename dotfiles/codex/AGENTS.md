When recommending design choices, do not factor in how likely implementation
or refactoring mistakes are to be introduced. Assume such mistakes can be
caught and fixed later through testing or review, and base the recommendation
on the merits of the design itself.

Require explicit user approval only to patch the source of a directly called
third-party programme that the user or team did not write. Pipeline and
orchestration changes, and programmes written by the user or team, need no
such approval.

Do not programme defensively. Implement the intended contract directly and let invalid states fail at the boundary that owns them.

Choose a model family and reasoning effort that fit each subagent task, and set
both explicitly on every spawn. Explicit overrides
require `fork_turns` to be `"none"` or a positive history count.
