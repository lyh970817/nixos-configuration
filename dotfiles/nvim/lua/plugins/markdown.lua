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
          -- 0.85 * cell height made display equations read smaller than
          -- body text (fractions/limits shrink their glyphs further).
          -- text_scale multiplies the worker's font size directly
          -- (renderer.resolve_font_size), so 1.35 puts equation glyphs
          -- slightly above body-text size without the old 2.4x blowup.
          text_scale = 1.35,
        },
        image = {
          cell_width_px = cell_width,
          cell_height_px = cell_height,
        },
      }
    end,
    config = function(_, opts)
      require("render_latex").setup(opts)

      -- Snacks.image (snacks/image/image.lua) and render-latex's kitty
      -- backend (render_latex/image_backends/kitty.lua) build kitty image
      -- ids with the *same* formula: (pid-hash << 14) | counter, counter
      -- starting at 31, pid-hash = band(bxor(pid, pid>>5, pid>>10), 0x3FF).
      -- Both run in this nvim process, so they claim identical ids:
      -- Snacks's inline-math transmissions overwrite display-equation
      -- images and its deletes remove them -- display equations then leave
      -- blank reserved lines. Which equations survive depends on how many
      -- inline images Snacks has placed, so the failure looks random.
      -- Move render-latex into the adjacent (guaranteed different) hash
      -- bucket by swapping the backend's generate_id upvalue; the pinned
      -- rc4 backend calls it only from set(). If the upvalue ever
      -- disappears in an update, leave the backend untouched.
      local kb = require("render_latex.image_backends.kitty")
      local bit = require("bit")
      local pid = vim.fn.getpid()
      local snacks_hash = bit.band(bit.bxor(pid, bit.rshift(pid, 5), bit.rshift(pid, 10)), 0x3FF)
      local hash = bit.band(snacks_hash + 1, 0x3FF)
      local counter = 30
      local function disjoint_id()
        counter = counter + 1
        return bit.bor(bit.lshift(hash, 14), counter)
      end
      for i = 1, 64 do
        local name = debug.getupvalue(kb.set, i)
        if name == nil then
          break
        end
        if name == "generate_id" then
          debug.setupvalue(kb.set, i, disjoint_id)
          break
        end
      end
    end,
  },
}
