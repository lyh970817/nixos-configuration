---
name: social-bookmarks
description: Use when reading or organizing the user's saved X/Twitter bookmarks or 小红书 (xhs) favorites — fetching them with the `twitter` or `xhs` CLIs, or sorting them into categories in a text file. Not for posting, replying, or any other social account work.
---

# Social bookmarks

## Read only

`twitter bookmarks` and `xhs favorites` are the only subcommands to run. Never
run `favorite`, `unfavorite`, `like`, `post`, `comment`, `reply`, or `delete` on
either CLI. The user curates both accounts by hand and neither an unfavorite nor
a delete has an undo.

## Fetch

```
twitter bookmarks --max 20 --json
xhs favorites --json
```

`--yaml` swaps the output format; `--help` lists the rest.

Both authenticate from stored cookies against unofficial endpoints, so request
volume is the risk that matters. Start at `--max 20` and raise it only when the
user asks for more. On a rate-limit or auth error, stop and report it rather
than retrying — retries are what escalate to an account flag.

## Organize

The deliverable is a text file, not a summary in chat. Fetch, group the entries
under categories the user named (propose categories from the fetched entries if
they did not), and write one line per entry keeping its link, so a later fetch
can be diffed against the file.

## Cookies

Cookie values live in the CLIs' own storage. Never copy one into a prompt, a
log, a commit, or the categorized file.
