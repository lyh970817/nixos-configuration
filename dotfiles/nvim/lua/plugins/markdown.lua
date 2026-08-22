-- Markdown rendering stack (issue #11, phase 5). Ownership is exclusive:
-- render-markdown.nvim owns Markdown structure (LaTeX disabled below),
-- render-latex.nvim owns display mathematics, Snacks.image owns inline
-- mathematics plus ordinary images/PDFs (plugins/snacks.lua).
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
      heading = {
        -- No background pills/bands behind headings: the defaults link
        -- H1Bg..H6Bg to DiffText/DiffAdd/... which all carry a filled
        -- background in the phosphor scheme. Headings keep their icon and
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
      -- render-latex.nvim and Snacks.image own all mathematics.
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
    opts = function()
      -- render-latex never measures the terminal: image.cell_*_px default to
      -- 10x20 while e.g. the desktop kitty runs 16x31 cells, so equation PNGs
      -- were stretched ~1.6x. Snacks already reads the real cell size via
      -- ioctl(TIOCGWINSZ); reuse it, keeping the defaults as fallback for
      -- headless/odd terminals.
      local cell_width, cell_height = 10, 20
      local ok, term = pcall(function()
        return require("snacks.image.terminal").size()
      end)
      if ok and term and term.cell_width > 0 and term.cell_height > 0 then
        cell_width, cell_height = term.cell_width, term.cell_height
      end

      return {
        -- Default render_modes = { "n", "i" } keeps equations rendered while
        -- editing (the live-preview behaviour; rc4 has no `live_preview` key).
        install = { version = "v0.1.0-rc4" },
        render = {
          -- Match buffer text colour/size; display math becomes transparent
          -- PNGs. Inline math is owned by Snacks.image math
          -- (plugins/snacks.lua), so the text-level conceal fallback is off.
          preset = "match_text",
          inline = false,
          -- No "Eq. N" virtual-text labels on display equations.
          equation_labels = false,
          -- The worker's device_pixel_ratio default of 1.5 supersamples the
          -- PNG, but kitty shows those pixels 1:1 (the placement grid is
          -- ceil(px/cell) cells), so 1.5 just inflated every glyph ~1.5x
          -- over the text size. 1.0 renders at display resolution: math
          -- glyphs come out at the match_text preset's 0.85 * cell height.
          scale = 1.0,
        },
        image = {
          cell_width_px = cell_width,
          cell_height_px = cell_height,
        },
      }
    end,
  },
}
