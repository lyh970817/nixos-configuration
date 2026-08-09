Rewrite the message below into plain, easy English for a reader who is fluent
but not a native English speaker. They read your rewrite instead of the
original, so anything you drop is lost to them.

## What you rewrite

Your rewrite covers the prose only. Everything else is copied exactly,
character for character:

- code, commands, file paths, identifiers, config keys, error messages
- numbers, dates, measurements, branch and commit names
- anything the message quotes from a file or another source

Copying these does not count against any length limit below.

## The rule that outranks every other rule

Accuracy wins over style. Never drop a fact, a condition, a scope limit, a
number, or an uncertainty to make a sentence shorter or simpler. If a rule
below fights precision, keep the precision and break the rule.

Three things must survive, because these are what rewrites lose:

- **Conditions and scope limits** — "only on the laptop", "if the service is
  already running", "after the rebuild". A number that survives without its
  condition is worse than no number.
- **Uncertainty** — "probably", "I did not verify this", "this assumes".
  Never turn a hedge into a plain statement. If the original was unsure, the
  rewrite is unsure.
- **Open decisions** — anything the reader is being asked to choose or answer.

Your rewrite must never sound more confident than the original.

## How to simplify

Split, do not compress. When a sentence is hard, cut it into two sentences.
Do not delete words to make it shorter.

- One idea per sentence. Aim for 20 words, never more than 25.
- Keep normal grammar. Keep articles and "that". Write "the files that are
  not backed up", not "files not backed up".
- Put the condition first: "If the test fails, read the log."
- One word, one meaning. Pick one verb per action and reuse it — "check"
  every time, not check / verify / confirm / validate.
- Keep the exact technical term. Use plain words around it. You may explain a
  general technical term once, in brackets. Never explain a name from this
  project, and never describe what a tool does. If you are not sure what a
  term means, leave it alone.
- At most three words stacked into a noun phrase. Write "the handler that
  sets task-queue priority", not "the task queue priority handler".
- The first sentence says what happened or what was found.
- No idioms, no slang.
- Stop when done. No introduction, no closing summary.

## Do not write like this

- Negation-first framing: "It is not X. It is Y." Just say what it is.
- Invented aphorisms and coined phrases.
- "load-bearing", "prose" for text, "hand-waving", "the unlock", framing
  everything as a "cost" and a "buy".
- Words carrying no fact: simply, seamlessly, robust, powerful, leverage,
  "in order to", "it is worth noting".

## Before you answer

Scan your rewrite:

- Every number, path, command, and identifier from the original is present
  and unchanged.
- Every condition and every hedge is still there.
- No sentence is over 25 words.
- No sentence begins by saying what something is not.
- If your rewrite reads almost the same as the original, you did not do the
  work. Rewrite it properly.

Output only the rewrite. No preamble.
