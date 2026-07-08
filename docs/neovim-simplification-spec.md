# Neovim Simplification Decision Spec

## Goal

Neovim should stop being a general coding cockpit and become a focused
viewer/review surface with occasional edits, daily Typst/math authoring, and
semantic navigation for languages used in current work.

The migration preserves useful capabilities from the current LazyVim setup but
removes LazyVim as the distribution layer. Plugin behavior should be explicit in
this repo, and external tools should be owned by Nix rather than Mason.

## Keep

- Daily Typst authoring: `tinymist`, `typst-preview.nvim`, `typstyle`
  format-on-save, `LuaSnip`, and `typstar`.
- Automatic completion with writing-oriented sources: LSP, buffer text, paths,
  and snippets.
- Semantic navigation for current languages: Typst, R, Nix, JSON, Markdown, and
  Lua configuration files.
- Current language/read support that matters: JSON schemas, DOT/Graphviz syntax,
  R language server, Nextflow filetype mapping via Groovy treesitter, Markdown
  basics, and Nix LSP.
- Spell and grammar/style assistance for writing formats. Grammar/style
  diagnostics are suggestive only.
- Snacks picker and explorer. Explorer should be used for read-only navigation;
  file operations should not be exposed in the intended key surface.
- Flash navigation, mapped to `S`.
- `mini-surround` on `gs`, `mini.ai`, `mini.pairs`, and commenting support.
- TODO/comment highlighting as a review aid, with a small picker binding.
- Lightweight Git context through `gitsigns.nvim`.
- Current comfort UI where explicitly requested: bufferline, lualine with similar
  visible information, Noice, and which-key.
- Current window-management helpers, including split/window/tab mappings,
  maximize/zoom, and Zen mode.
- Theme behavior: system light/dark detection, `bow-wob` for light mode,
  `matrix` for dark mode, and live switching.
- Window, tab, and buffer navigation capabilities currently used from LazyVim.
- `lazy-lock.json` plugin pinning.

## Remove

- LazyVim itself and LazyVim extras.
- Copilot and Claude Code integrations inside Neovim.
- Mason and Mason LSP/tool installation.
- Dashboard/start screen, session persistence, embedded terminal integration,
  Trouble, project.nvim, and broad Git/GitHub workflow pickers.
- Automatic format-on-save for non-Typst files. Nix formatting remains handled
  by repo hooks or explicit commands.

## Key Decisions

- Preserve capabilities, not the LazyVim implementation.
- Keep lowercase `s` as native Vim substitute.
- Map Flash jump to `S`.
- Keep `gs` for surround operations.
- Keep diagnostics quiet: no virtual text by default, signs and underlines
  enabled, floats/pickers on demand.
- Keep grammar/style suggestions low-priority and easy to toggle with
  diagnostics.
- Let Nix install external tools such as `nil`, `harper-ls`, `marksman`,
  `lua-language-server`, and JSON language server binaries.

## Verification Targets

- Neovim starts without importing LazyVim.
- `:Lazy` shows no LazyVim, Mason, Copilot, Claude Code, Trouble, dashboard, or
  session plugin.
- Typst files get snippets, completion, preview, `tinymist`, and format-on-save.
- Markdown and Typst get spell and grammar/style suggestions.
- Nix, R, JSON, Markdown, Typst, and Lua LSP clients attach when their binaries
  are available.
- `s` performs native substitute, `S` starts Flash, and `gs` triggers surround.
- Snacks picker/explorer, bufferline, lualine, Noice, gitsigns, which-key, and
  the light/dark theme behavior work.
