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
    end,
  },
}
