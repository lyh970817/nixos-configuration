-- Markdown rendering stack (issue #11, phase 5). Ownership is exclusive:
-- render-markdown.nvim owns Markdown structure (LaTeX disabled below),
-- render-latex.nvim owns all mathematics, and Snacks.image owns ordinary
-- images/PDFs (plugins/snacks.lua disables its math path).
--
-- Markview rendered .qmd/.Rmd too; those filetypes are intentionally left
-- raw here until tested (issue #11), rather than adding brittle injections.
return {
  {
    "MeanderingProgrammer/render-markdown.nvim",
    ft = { "markdown" },
    dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-mini/mini.icons" },
    opts = {
      -- Markview's hybrid preview, reproduced: keep the buffer rendered in
      -- normal/command/insert mode while anti-conceal reveals raw source on
      -- the cursor line, so the active line is edited as plain text.
      render_modes = { "n", "c", "i" },
      anti_conceal = {
        enabled = true,
        above = 0,
        below = 0,
      },
      -- render-latex.nvim owns all mathematics.
      latex = { enabled = false },
    },
  },

  {
    "techwizrd/render-latex.nvim",
    ft = { "markdown" },
    -- Early release: pin the Lua code and the prebuilt Rust worker to the
    -- same tested tag (v0.1.0-rc4, latest release as of 2026-08). The worker
    -- downloads on first load; validate with :RenderLatex doctor and
    -- :checkhealth render_latex on each host.
    version = "v0.1.0-rc4",
    opts = {
      -- Default render_modes = { "n", "i" } keeps equations rendered while
      -- editing (the live-preview behaviour; rc4 has no `live_preview` key).
      install = { version = "v0.1.0-rc4" },
      render = {
        -- Match buffer text colour/size; display math becomes transparent
        -- PNGs, inline math stays a conceal fallback (no image flicker).
        preset = "match_text",
        inline = "conceal",
        inline_symbols = true,
      },
    },
  },
}
