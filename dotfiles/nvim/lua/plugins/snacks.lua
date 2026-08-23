return {
  {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    opts = {
      bigfile = { enabled = true },
      bufdelete = { enabled = true },
      explorer = {
        enabled = true,
        replace_netrw = true,
        trash = false,
      },
      image = {
        enabled = true,
        -- Ordinary Markdown images and PDF previews, inline via the Kitty
        -- graphics protocol with a float fallback elsewhere.
        doc = {
          enabled = true,
          inline = true,
          float = true,
          max_width = 80,
          max_height = 40,
          -- Conservative start for ordinary images: keep the raw image-link
          -- syntax visible until edits/undo/scrolling are proven to leave no
          -- stale placements. Math expressions do conceal their source (the
          -- image replaces the `$...$` span; the cursor line reveals it).
          -- "imath" is this config's inline-math variant of the stock
          -- "math" type (see `config` below).
          conceal = function(_, type)
            return type == "math" or type == "imath"
          end,
        },
        -- Inline mathematics only: `$...$` spans become images rendered by
        -- tectonic (home/programs/kitty.nix) at one shared scale anchored
        -- to the terminal font (see `config` below). Display mathematics
        -- stays with render-latex.nvim (plugins/markdown.lua); the images
        -- query override in `config` below keeps this split exclusive.
        -- Fenced ```math blocks also land here (render-latex ignores them).
        math = { enabled = true },
      },
      input = { enabled = true },
      notifier = { enabled = true },
      picker = {
        enabled = true,
        sources = {
          explorer = {
            win = {
              list = {
                keys = {
                  ["a"] = false,
                  ["d"] = false,
                  ["r"] = false,
                  ["c"] = false,
                  ["m"] = false,
                  ["p"] = false,
                  ["<c-t>"] = false,
                },
              },
            },
          },
        },
      },
      quickfile = { enabled = true },
      scope = { enabled = true },
      -- Smooth scrolling (Option A of the scroll flag in plugins/scroll.lua).
      -- NOTE: scroll.lua cannot toggle this table for you -- it is a separate
      -- plugin spec (folke/snacks.nvim is already required here). If you flip
      -- the SCROLL_BACKEND flag in plugins/scroll.lua to "neoscroll", you MUST
      -- also flip `enabled` below to `false` (and vice versa) to keep the two
      -- backends from fighting over <C-f>/<C-b>/<C-d>/<C-u>/zz/zt/zb/gg/G.
      scroll = {
        enabled = true,
        -- Full-page feel: duration scales with the distance scrolled (step
        -- ms per line, capped by total), eased in/out.
        -- snacks/scroll.lua:28-38 (defaults) confirms these are the only
        -- two sub-tables read by the module: `animate` and `animate_repeat`.
        animate = {
          duration = { step = 15, total = 250 },
          easing = "inOutQuad",
        },
        -- Faster/snappier animation when repeating scroll before the previous
        -- one settles (e.g. holding <C-d>), so rapid presses don't feel laggy.
        animate_repeat = {
          delay = 100,
          duration = { step = 5, total = 100 },
          easing = "linear",
        },
        -- Preserve Snacks' global/buffer opt-outs and skip terminals and big files.
        filter = function(buf)
          return vim.g.snacks_scroll ~= false
            and vim.b[buf].snacks_scroll ~= false
            and vim.bo[buf].buftype ~= "terminal"
            and vim.bo[buf].filetype ~= "bigfile"
        end,
      },
      words = { enabled = true },
      zen = { enabled = true },
    },
    keys = {
      {
        "<leader><space>",
        function()
          require("snacks").picker.files({ cwd = require("config.root").get(0) })
        end,
        desc = "Find Files",
      },
      { "<leader>,", function() require("snacks").picker.buffers() end, desc = "Buffers" },
      {
        "<leader>/",
        function()
          require("snacks").picker.grep({ cwd = require("config.root").get(0) })
        end,
        desc = "Grep",
      },
      { "<leader>:", function() require("snacks").picker.command_history() end, desc = "Command History" },
      {
        "<leader>e",
        function()
          require("snacks").explorer({ cwd = require("config.root").get(0) })
        end,
        desc = "Explorer",
      },
      { "<leader>E", function() require("snacks").explorer() end, desc = "Explorer (cwd)" },
      { "<leader>fb", function() require("snacks").picker.buffers() end, desc = "Buffers" },
      {
        "<leader>ff",
        function()
          require("snacks").picker.files({ cwd = require("config.root").get(0) })
        end,
        desc = "Find Files",
      },
      { "<leader>fF", function() require("snacks").picker.files() end, desc = "Find Files (cwd)" },
      { "<leader>fr", function() require("snacks").picker.recent() end, desc = "Recent" },
      { "<leader>sb", function() require("snacks").picker.lines() end, desc = "Buffer Lines" },
      { "<leader>sB", function() require("snacks").picker.grep_buffers() end, desc = "Grep Open Buffers" },
      {
        "<leader>sg",
        function()
          require("snacks").picker.grep({ cwd = require("config.root").get(0) })
        end,
        desc = "Grep",
      },
      { "<leader>sG", function() require("snacks").picker.grep() end, desc = "Grep (cwd)" },
      {
        "<leader>sw",
        function()
          require("snacks").picker.grep_word({ cwd = require("config.root").get(0) })
        end,
        desc = "Word or Selection",
        mode = { "n", "x" },
      },
      { "<leader>s/", function() require("snacks").picker.search_history() end, desc = "Search History" },
      { "<leader>sR", function() require("snacks").picker.resume() end, desc = "Resume Picker" },
      { "<leader>wm", function() require("snacks").toggle.zoom():toggle() end, desc = "Maximize Window" },
      { "<leader>uZ", function() require("snacks").toggle.zoom():toggle() end, desc = "Maximize Window" },
      { "<leader>uz", function() require("snacks").zen() end, desc = "Zen Mode" },
      {
        "<leader>us",
        function()
          require("snacks").toggle.option("spell", { name = "Spelling" }):toggle()
        end,
        desc = "Toggle Spelling",
      },
      {
        "<leader>uw",
        function()
          require("snacks").toggle.option("wrap", { name = "Wrap" }):toggle()
        end,
        desc = "Toggle Wrap",
      },
      {
        "<leader>ud",
        function()
          require("snacks").toggle.diagnostics():toggle()
        end,
        desc = "Toggle Diagnostics",
      },
      {
        "<leader>ul",
        function()
          require("snacks").toggle.line_number():toggle()
        end,
        desc = "Toggle Line Numbers",
      },
      {
        "<leader>uL",
        function()
          require("snacks").toggle.option("relativenumber", { name = "Relative Number" }):toggle()
        end,
        desc = "Toggle Relative Numbers",
      },
      {
        "<leader>uc",
        function()
          require("snacks").toggle.option("conceallevel", { off = 0, on = 2, name = "Conceal Level" }):toggle()
        end,
        desc = "Toggle Conceal",
      },
      {
        "<leader>ub",
        function()
          require("snacks").toggle.option("background", {
            off = "light",
            on = "dark",
            name = "Dark Background",
          }):toggle()
        end,
        desc = "Toggle Background",
      },
    },
    config = function(_, opts)
      require("snacks").setup(opts)

      -- ===== One shared scale for all math images =====
      -- Stock Snacks normalizes every formula to its own cell box: magick
      -- renders at a fixed 192 DPI and `-trim`s to the ink, the placement
      -- grid is the ceil of that arbitrary pixel size, and kitty scales
      -- the image to fill the grid. A lone `\(m\)` (ink = x-height) is
      -- blown up to a full text row, while `\(h^S_{pm}\)` -- two cells
      -- tall -- is squeezed into one by placement.state()'s inline branch:
      -- per-formula font sizes, some huge, some tiny. Instead, anchor
      -- everything to the terminal font: render at a density where one
      -- math em equals one cell height, and place pixel-for-pixel.
      local image_cfg = require("snacks").image.config
      -- \Large in the snacks 12pt standalone template is 17.28pt.
      local MATH_EM_PT = 17.28
      -- Legibility bump: one math em spans 1.12 terminal cells instead of
      -- exactly one. The strut below shrinks by the same factor so the
      -- shared line box still maps to one cell; ink taller than that box
      -- (full-height parens and up) is capped back by placement as before.
      local MATH_EM_CELLS = 1.12
      local cell_w, cell_h
      -- Derive the render metrics from the terminal cell size, refreshed on
      -- VimResized. A pty without pixel geometry -- ws_xpixel/ws_ypixel 0,
      -- which every herdr pane reports until its attached client knows the
      -- host cell size (kitty_graphics off, or pre-reattach) -- slips
      -- through snacks' size() guard as cell_width/cell_height 0. Clamping
      -- that to 1 once baked `-density 5` renders: 1px-tall formula strips
      -- that kitty scaled into dark smudges. Treat it as unknown and use
      -- snacks' own 9x18 fallback instead; the VimResized refresh lets a
      -- long-lived nvim pick up the real geometry when the pane gains it
      -- (herdr re-resizes its pty on client attach and layout changes).
      local function refresh_math_metrics()
        local term = require("snacks.image.terminal").size()
        local cw = math.floor(term.cell_width + 0.5)
        local ch = math.floor(term.cell_height + 0.5)
        if cw < 2 or ch < 4 then
          cw, ch = 9, 18
        end
        if cw == cell_w and ch == cell_h then
          return
        end
        cell_w, cell_h = cw, ch
        local density = math.floor(72 * cell_h * MATH_EM_CELLS / MATH_EM_PT + 0.5)
        -- Grow renders shorter than a cell to exactly one cell (transparent,
        -- ink centered): kitty scales an image to fit its cell box in BOTH
        -- directions, so without the padding a short image would be scaled
        -- up until its height fills the row. With it, height binds at 1.0
        -- and the image passes through 1:1. Taller images are left alone.
        local pad_extent = ("%%[fx:w]x%%[fx:h<%d?%d:h]"):format(cell_h, cell_h)
        -- "math": fenced ```math and .tex display snippets.
        image_cfg.convert.magick.math = {
          "-density", density, "{src}[{page}]", "-trim",
          "-background", "none", "-gravity", "center", "-extent", pad_extent,
        }
        -- "imath": inline LaTeX formulas (query + bracket scan below). No
        -- `-trim`: the rule strut added by the transform keeps the compiled
        -- page at the shared line box (1/MATH_EM_CELLS em = one cell),
        -- placing every formula's baseline at 0.75 of the cell -- a bare `m`
        -- stays x-height-sized on the common baseline instead of filling the
        -- row.
        image_cfg.convert.magick.imath = {
          "-density", density, "{src}[{page}]",
          "-background", "none", "-gravity", "center", "-extent", pad_extent,
        }
        -- Same templates as stock, with the render density baked into a
        -- comment so the content hash -- and thus the render cache -- turns
        -- over when a font, cell-size, or anchor (MATH_EM_CELLS) change
        -- alters the density.
        image_cfg.math.latex.tpl = ([[
\documentclass[preview,border=0pt,varwidth,12pt]{standalone}
\usepackage{${packages}}
%% density=%ddpi
\begin{document}
${header}
{ \${font_size} \selectfont
  \color[HTML]{${color}}
${content}}
\end{document}]]):format(density)
      end
      refresh_math_metrics()
      -- Scheduled so snacks' own VimResized autocmd (registered first, at
      -- module load) has cleared its cached size() before we re-read it.
      vim.api.nvim_create_autocmd("VimResized", {
        group = vim.api.nvim_create_augroup("config.snacks.math_metrics", { clear = true }),
        callback = function()
          vim.schedule(refresh_math_metrics)
        end,
      })
      image_cfg.icons.imath = image_cfg.icons.math

      -- Snacks ships queries/latex/images.scm matching inline_formula,
      -- displayed_equation and math_environment in every injected latex tree
      -- (`$...$` and `$$...$$` in Markdown both inject latex). Display math
      -- belongs to render-latex.nvim (plugins/markdown.lua), so override the
      -- query to inline formulas only, typed "imath" to select the
      -- inline-math convert args above. A file in our config's queries/ dir
      -- cannot do this: the plugin's non-`;; extends` file later on the
      -- runtimepath would win.
      vim.treesitter.query.set(
        "latex",
        "images",
        [[
          (inline_formula
            (#set! image.ext "imath.tex"))
            @image.content @image
        ]]
      )
      -- Snacks' latex transform wraps every snippet in display-style
      -- `\[...\]`, which gives inline sums/integrals full-height limits and
      -- pushes the image below the line. Rewrite inline formulas to a text
      -- style `\(...\)` box (natural width, no display skips -- the page
      -- box is croppable without `-trim`) carrying a zero-width rule strut
      -- for the common baseline; fenced ```math blocks (the only other
      -- markdown math.tex source) are left display-style.
      local doc = require("snacks.image.doc")
      local latex_transform = doc.transforms.latex
      -- The strut spans the shared line box: 1/MATH_EM_CELLS em total
      -- (baseline at 0.75 of it, like `\vphantom{(}`) is exactly one cell
      -- at the density above. Keeping the box at one cell is what lets the
      -- em grow past the cell: a plain 1em strut would overflow the row
      -- and the placement cap would scale every formula straight back down.
      local strut = ("\\rule[-%.5fem]{0pt}{%.5fem}")
        :format(0.25 / MATH_EM_CELLS, 1 / MATH_EM_CELLS)
      local function inline_box(content)
        content = content:gsub("\\%[", "\\(\\textstyle" .. strut .. " ", 1)
        return (content:gsub("\\%]", "\\)", 1))
      end
      -- The stock transform only acts on ext == "math.tex", so present
      -- that ext to it for our renamed "imath.tex" matches.
      local function imath_transform(img, ctx)
        local ext = img.ext
        img.ext = ext == "imath.tex" and "math.tex" or ext
        latex_transform(img, ctx)
        img.ext = ext
      end
      doc.transforms.latex = function(img, ctx)
        imath_transform(img, ctx)
        local node = ctx.content and ctx.content.node
        if img.content and node and node:type() == "inline_formula" then
          img.content = inline_box(img.content)
        end
      end

      -- Place math images on the pixel grid instead of letting stock
      -- sizing normalize them. util.fit() ceil-rounds the image into
      -- cells and state() squeezes anything <= 2 rows into one mangled
      -- row; both make kitty rescale each formula by its own factor.
      -- rows/cols here come straight from the image's pixel size (with
      -- 10% slack so a rounding pixel does not claim an extra row), which
      -- the convert `-extent` pad makes an exact fit for one-cell images:
      -- kitty places them at scale 1. The only remaining scaling is the
      -- inline cap: a formula taller than its text line keeps one row and
      -- is fitted uniformly (kitty preserves aspect ratio), a gentle
      -- shrink for tall formulas that never grows short ones. cell_w and
      -- cell_h are the refresh_math_metrics() upvalues above, so placement
      -- follows the same VimResized refresh as the render density.
      local Placement = require("snacks.image.placement")
      local placement_state = Placement.state
      function Placement:state()
        local st = placement_state(self)
        local t = self.opts.type
        if (t ~= "math" and t ~= "imath") or not (self.img and self.img.file) then
          return st
        end
        local ok, dim = pcall(require("snacks.image.util").dim, self.img.file)
        if not ok or dim.width <= 0 or dim.height <= 0 then
          return st
        end
        local rows = math.max(1, math.ceil(dim.height / cell_h - 0.1))
        local cols = math.max(1, math.ceil(dim.width / cell_w))
        local range = self.opts.range
        if rows > 1 and range and range[1] == range[3] then
          local line = vim.api.nvim_buf_get_lines(self.buf, range[1] - 1, range[1], false)[1] or ""
          local inline = line:sub(1, range[2]):find("%S") ~= nil
            or line:sub(range[4] + 1):find("%S") ~= nil
          if inline then
            cols = math.max(1, math.ceil(dim.width * cell_h / dim.height / cell_w))
            rows = 1
          end
        end
        st.loc.width = math.min(cols, self.opts.max_width or 80)
        st.loc.height = rows
        return st
      end

      -- `\(...\)` inline math. markdown_inline's grammar lexes the
      -- delimiters as two unrelated backslash_escape tokens (verified with
      -- the tree: no node spans the formula), so no latex injection exists
      -- and no tree-sitter query can ever capture the span. Instead,
      -- doc.find() is wrapped to append synthetic matches from a plain
      -- line scan: Snacks placements consume only plain fields
      -- (id/pos/range/src/type/lang), never TSNodes, so the synthetic
      -- items flow through inline placement, conceal and hover unchanged.
      -- Display `\[...\]` needs none of this: render-latex.nvim detects it
      -- natively (render_latex/detect.lua bracket_equations line scan).

      --- Odd number of backslashes immediately before byte i.
      local function escaped(line, i)
        local n, j = 0, i - 1
        while j >= 1 and line:sub(j, j) == "\\" do
          n, j = n + 1, j - 1
        end
        return n % 2 == 1
      end

      --- Build one synthetic snacks.image.match for `\(tex\)` on a line,
      --- replicating doc._img's content-to-cache-file step. Rows are
      --- 1-based, s/e are 1-based inclusive byte positions of `\(`/`\)`.
      local function bracket_match(buf, row, s, e, tex)
        local img = {
          id = ("bracket_math:%d:%d"):format(row, s),
          pos = { row, s - 1 },
          range = { row, s - 1, row, e },
          lang = "latex",
          type = "imath",
          ext = "imath.tex",
          content = tex,
        }
        -- The plugin's own transform strips `\(`/`\)`-style delimiters and
        -- wraps the formula in the tectonic template; then the same
        -- inline-box rewrite as for inline_formula nodes above.
        imath_transform(img, { buf = buf, lang = "latex" })
        img.content = inline_box(img.content)
        local root = require("snacks").image.config.cache
        vim.fn.mkdir(root, "p")
        img.src = root .. "/" .. vim.fn.sha256(img.content):sub(1, 8) .. "-content.imath.tex"
        if vim.fn.filereadable(img.src) == 0 then
          local fd = assert(io.open(img.src, "w"), "failed to open " .. img.src)
          fd:write(img.content)
          fd:close()
        end
        return img
      end

      --- Scan rows [from, to] (1-based, nil = whole buffer) for single-line
      --- `\(...\)` spans outside fenced code blocks and inline code spans
      --- (backtick-parity heuristic), mirroring what the tree-sitter query
      --- yields for `$...$` inline formulas.
      local function bracket_inline_matches(buf, from, to)
        if vim.bo[buf].filetype ~= "markdown" then
          return {}
        end
        if not require("snacks").image.config.math.enabled then
          return {}
        end
        local ret = {}
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        -- Fence state must be tracked from the top of the buffer even when
        -- only a window range is requested.
        local fenced, fence = {}, nil
        for row, line in ipairs(lines) do
          local marker = line:match("^%s*(```+)") or line:match("^%s*(~~~+)")
          if fence == nil and marker then
            fence, fenced[row] = marker:sub(1, 1), true
          elseif fence ~= nil then
            fenced[row] = true
            if marker and marker:sub(1, 1) == fence then
              fence = nil
            end
          end
        end
        for row = math.max(from or 1, 1), math.min(to or #lines, #lines) do
          local line = lines[row]
          if not fenced[row] then
            local col = 1
            while true do
              local s, e, tex = line:find("\\%((..-)\\%)", col)
              if not s then
                break
              end
              local _, ticks = line:sub(1, s - 1):gsub("`", "")
              if not escaped(line, s) and ticks % 2 == 0 and not tex:find("%$") then
                ret[#ret + 1] = bracket_match(buf, row, s, e, tex)
              end
              col = e + 1
            end
          end
        end
        return ret
      end

      local find = doc.find
      doc.find = function(buf, cb, opts)
        find(buf, function(imgs)
          local ok, extra = pcall(bracket_inline_matches, buf, opts and opts.from, opts and opts.to)
          if ok then
            vim.list_extend(imgs, extra)
          end
          cb(imgs)
        end, opts)
      end
    end,
  },
}
