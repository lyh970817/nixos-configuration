---
name: kcl-fetch
description: Retrieve one paywalled paper through King's College London's institutional access. Use only after `scansci-oa` has failed, and only for a paper the user actually asked for. Also covers what to do when the gate refuses, and when to send the user to the library instead.
---

# kcl-fetch — the last rung of the paper ladder

## Where this sits

1. `scansci-oa` — free and shadow sources. **Always try this first.** Costs nothing,
   names nobody.
2. `annas-books` — books only, spends a paid quota.
3. `kcl-fetch` — **this**. The only route to paywalled work published after the shadow
   libraries froze in 2021.

Rung 3 is different in kind, not degree. Every request carries King's College London's
name and comes from KCL's IP range. The cost of misuse is not a failed download: a
publisher block lands on the whole institution, and an EZproxy `UsageLimit` trip has to
be cleared by a library administrator. You are spending someone else's reputation.

So: never reach for this speculatively, never to "check if it's available", and never
for a paper the user did not name. If you are unsure whether the user wants this paper
specifically, ask before fetching rather than after.

## Using it

```sh
kcl-fetch get <DOI> [-o DIR]   # one article
kcl-fetch login                # one-time manual SSO, opens a visible window
kcl-fetch status               # budget, blocks, recent attempts
```

**There is no batch mode and you must not build one.** Do not loop `kcl-fetch get` over
a list of DOIs, do not run it from a shell `for`, and do not run several in parallel.
Bulk retrieval is the exact signature that gets institutions blocked, and it is why the
gate exists. The gate will stop you, but arriving at a refusal is already the wrong
shape of request.

MFA (Microsoft Entra / Authenticator) is enforced. **Never ask the user for their KCL
password, never type into the login window, never attempt to script sign-in.** If a
session is needed, tell the user to run `kcl-fetch login` and complete it themselves.

## When it refuses

The gate refuses before any browser exists. Read which refusal you got — they mean
different things and only one of them is "try again later".

| Refusal | What it means | What to do |
| --- | --- | --- |
| **budget** | The rolling 3-hour or daily allowance is spent. | Stop fetching. Fall back to `scansci-oa`, or tell the user roughly when the window frees up (the message says). Do not retry in a loop. |
| **enumeration** | Three DOIs from one journal issue, or a walk of consecutive DOI suffixes. | Stop entirely. Do not work around it by spacing requests out or reordering them — the pattern is the problem, not the timing. Tell the user what was detected. |
| **concurrency** | Another `kcl-fetch` is running. | Wait for it. Never run two. |
| **blocked** | A publisher returned 403 and that host is latched off permanently. | **Do not retry, ever, and do not suggest a retry.** Tell the user to contact the KCL library with the publisher host and the time. Only an administrator clears this. |
| login required | The session expired or was never established. | Tell the user to run `kcl-fetch login`. Do not attempt it yourself. |
| no full text / no route | KCL does not hold it, or neither access route served it. | Fall back to `scansci-oa` for a preprint, or suggest inter-library loan. |

A refusal is a correct outcome, not an obstacle. If you find yourself looking for a way
around one, the answer is to stop and tell the user.

## Reporting back

When a fetch succeeds, say which access route served it (OpenAthens or EZproxy) and where
the file landed. A `.provenance.json` sits next to every PDF with the DOI, the final
publisher URL, size, page count and checksum — cite from that rather than guessing.

When it fails, say which rung failed and what the user's remaining options are. "I
couldn't get it" is not enough; "`scansci-oa` found no copy and KCL's route hit a login
wall — run `kcl-fetch login` and I'll retry" is.

## Configuration

`~/.config/kcl-fetch/config.json` can only make the limits **stricter**. Any value that
would raise a cap or shorten a wait is rejected at startup. If a user asks you to raise
a limit, the answer is no and the reason is above — do not edit the defaults in
`pkgs/kcl-fetch/kcl_fetch_lib/limits.py` to get around the config check.
