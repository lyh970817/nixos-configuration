-- Markdown rendering stack (issue #11, phase 5). render-markdown.nvim owns
-- Markdown structure; Snacks.image draws ordinary images/PDFs
-- (plugins/snacks.lua). Mathematics stays raw TeX.
--
-- Markview rendered .qmd/.Rmd too; those filetypes are intentionally left
-- raw here until tested (issue #11), rather than adding brittle injections.

return {
  {
    "MeanderingProgrammer/render-markdown.nvim",
    -- Vendored: upstream pin 4663eb3 plus its open PR #617 (max_table_width
    -- cell wrapping), rebased and applied as a Nix patch -- see
    -- home/programs/dotfiles.nix, which symlinks the patched source here.
    -- Drop the dir override (and the Nix block) when upstream merges #617.
    dir = vim.fn.stdpath("config") .. "/vendor/render-markdown.nvim",
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
      heading = {
        -- No circled level digits (the default 󰲡..󰲫 icons render as ①②③
        -- glyphs here) before heading text; headings keep their styled
        -- text with the raw `##` marker visible -- heading.lua only
        -- conceals the marker when an icon replaces it, so disabling
        -- icons brings the marker back by design.
        icons = {},
        -- No background pills/bands behind headings: the defaults link
        -- H1Bg..H6Bg to DiffText/DiffAdd/... which all carry a filled
        -- background in the phosphor scheme. Headings keep their
        -- foreground emphasis on the plain terminal background.
        backgrounds = {},
        -- A lone `=` (or `-`) line inside a `$$ ... $$` block makes
        -- tree-sitter parse the preceding equation lines as a setext
        -- heading, which painted a full-width H1 band plus the H1 icon
        -- (the stray circled ①) across rendered equations. Setext headings
        -- are unused in these documents, so drop their rendering entirely
        -- rather than special-casing math blocks.
        setext = false,
      },
      -- Same background objection for fenced code blocks (default links
      -- RenderMarkdownCode to ColorColumn). Language icon and border stay.
      code = { disable_background = true },
      -- PR #617 (vendored above): tables wider than the window wrap their
      -- cells onto virtual lines instead of shattering when 'wrap' is on
      -- (READ mode); inert under nowrap. Full window width -- the wrapped
      -- table replaces horizontal overflow, so it may use every column.
      pipe_table = { max_table_width = 1.0 },
      -- No LaTeX converter is installed; math stays raw TeX.
      latex = { enabled = false },
    },
  },
}
