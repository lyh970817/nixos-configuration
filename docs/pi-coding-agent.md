# pi coding agent

`pi` runs GPT models from the ChatGPT/Codex subscription through pi's own
native `openai-codex` provider. It does **not** go through the local
CLIProxyAPI gateway on `127.0.0.1:8317`, and it does not use an
`OPENAI_API_KEY`. Server-side ("backend") context compaction is provided by the
`algal/pi-openai-server-compaction` extension.

Pieces:

- `pkgs/pi-coding-agent.nix` — the CLI (`buildNpmPackage`, prebuilt `dist/`).
- `pkgs/pi-openai-server-compaction.nix` — the extension, plus a vendored `ws`.
- `home/programs/pi.nix` — launcher, extension link, extension config link.
- `home/programs/mutable-configs.nix` — materializes `~/.pi/agent/settings.json`.
- `dotfiles/pi/` — the tracked baselines for both JSON files.

## One-time manual bootstrap

Everything else is declarative, but the OAuth session is not. After the first
`rebuild`, run:

```sh
pi
```

then use the `/login` slash command and complete the ChatGPT/Codex
authorization in the browser.

pi keeps its own credential file at `~/.pi/agent/auth.json` and **never** reads
`~/.codex/auth.json`, so an existing Codex CLI login does not carry over. That
file is machine-local: it is not tracked in this repo, not symlinked, and pi
rewrites it on every token refresh.

## Why the version is pinned to 0.80.9

`pkgs/pi-coding-agent.nix` pins `version = "0.80.9"` on purpose, even though
newer pi releases exist. The compaction extension declares:

```json
"peerDependencies": {
  "@earendil-works/pi-coding-agent": ">=0.80.9 <0.81.0",
  "@earendil-works/pi-ai": ">=0.80.9 <0.81.0",
  "@earendil-works/pi-agent-core": ">=0.80.9 <0.81.0"
}
```

Those peers are marked optional, so a mismatched pi will **not** error — the
extension would just silently fail to hook `session_before_compact`, and
compaction would quietly fall back to pi's client-side path. Bump both together:

1. `pkgs/pi-coding-agent.nix` — `version`, `src.hash`, and `npmDepsHash`.
2. `pkgs/pi-openai-server-compaction.nix` — `rev` and `hash`, to a revision
   whose `peerDependencies` range covers the new pi version.

## Notes on the packaging

- The npm tarball ships a prebuilt `dist/` and an `npm-shrinkwrap.json`, so
  there is no build step (`dontNpmBuild = true`).
- That shrinkwrap omits `integrity` for the three first-party
  `@earendil-works/*` entries, which makes `prefetch-npm-deps` abort. The
  `postPatch` in `pkgs/pi-coding-agent.nix` patches the published sha512
  digests back in; it runs for both the dependency fetch and the build, so
  `npmDepsHash` stays stable.
- The extension entrypoint is raw TypeScript (`src/index.ts`), loaded at
  runtime by pi's jiti loader — no compile step. That loader virtualizes only
  pi's own packages, so the extension's single runtime dependency `ws` has to
  resolve by ordinary Node resolution. It is vendored into
  `$out/node_modules/ws`.

## Extension registration is declarative

pi's package manager builds its package list exclusively from the `packages`
array in `settings.json`; it never scans directories. Any source string that
does not start with `npm:` / `git:` / `github:` / `http:` / `https:` / `ssh:`
is treated as a local path, whose install branch only does an `existsSync`.

So `dotfiles/pi/settings.json` just lists the stable path
`/home/andongni/.pi/agent/extensions/openai-server-compaction`, and
`home/programs/pi.nix` points that path at the extension's store output. No
`pi install` is ever needed, and no network access happens at activation.

## File mutability

| File | Written by pi? | How it is managed |
| --- | --- | --- |
| `~/.pi/agent/settings.json` | yes | materialized 0600 copy from `dotfiles/pi/settings.json` on every activation |
| `~/.pi/agent/auth.json` | yes | machine-local, unmanaged, never tracked |
| `~/.pi/agent/openai-server-compaction.json` | no | out-of-store symlink to `dotfiles/pi/` |
| `~/.pi/agent/extensions/openai-server-compaction` | no | symlink to the store |

Because `settings.json` is replaced on every activation, model switches made
inside pi with `/model` do not survive a `rebuild`. Change the default in
`dotfiles/pi/settings.json` (`defaultProvider` + `defaultModel`) instead.

## Model selection

The settings keys are two separate bare strings — `defaultProvider` and
`defaultModel` — not one combined `provider/model` value. The built-in
`openai-codex` catalog ids are `gpt-5.6-sol`, `gpt-5.6-terra`, `gpt-5.6-luna`,
`gpt-5.5`, `gpt-5.4`, `gpt-5.4-mini`, and `gpt-5.3-codex-spark`. The baseline
uses `gpt-5.6-terra`.

## Confirming the extension is actually live

`dotfiles/pi/openai-server-compaction.json` ships upstream's documented
defaults, which include `"notify": false`. Flip it to `true` to make the
extension announce each server-side compaction, which is the easiest way to
confirm it is loaded and hooked after a version bump.
