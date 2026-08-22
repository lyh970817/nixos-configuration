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
          conceal = function(_, type)
            return type == "math"
          end,
        },
        -- Inline mathematics only: `$...$` spans become images rendered by
        -- tectonic (home/programs/kitty.nix) and fitted to the line height.
        -- Display mathematics stays with render-latex.nvim
        -- (plugins/markdown.lua); the images query override in `config`
        -- below keeps this split exclusive. Fenced ```math blocks also land
        -- here (render-latex ignores them).
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
      -- Snacks ships queries/latex/images.scm matching inline_formula,
      -- displayed_equation and math_environment in every injected latex tree
      -- (`$...$` and `$$...$$` in Markdown both inject latex). Display math
      -- belongs to render-latex.nvim (plugins/markdown.lua), so override the
      -- query to inline formulas only. A file in our config's queries/ dir
      -- cannot do this: the plugin's non-`;; extends` file later on the
      -- runtimepath would win.
      vim.treesitter.query.set(
        "latex",
        "images",
        [[
          (inline_formula
            (#set! image.ext "math.tex"))
            @image.content @image
        ]]
      )
      -- Snacks' latex transform wraps every snippet in display-style
      -- `\[...\]`, which gives inline sums/integrals full-height limits and
      -- pushes the image below the line. Force text style for inline
      -- formulas so they keep fitting the line height; fenced ```math blocks
      -- (the only other math.tex source) are left display-style.
      local doc = require("snacks.image.doc")
      local latex_transform = doc.transforms.latex
      doc.transforms.latex = function(img, ctx)
        latex_transform(img, ctx)
        local node = ctx.content and ctx.content.node
        if img.content and node and node:type() == "inline_formula" then
          img.content = img.content:gsub("\\%[", "\\[\\textstyle ", 1)
        end
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
          type = "math",
          ext = "math.tex",
          content = tex,
        }
        -- The plugin's own transform strips `\(`/`\)`-style delimiters and
        -- wraps the formula in the tectonic template; then the same
        -- \textstyle fix as for inline_formula nodes above.
        latex_transform(img, { buf = buf, lang = "latex" })
        img.content = img.content:gsub("\\%[", "\\[\\textstyle ", 1)
        local root = require("snacks").image.config.cache
        vim.fn.mkdir(root, "p")
        img.src = root .. "/" .. vim.fn.sha256(img.content):sub(1, 8) .. "-content.math.tex"
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
