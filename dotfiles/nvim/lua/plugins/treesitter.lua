return {
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    init = function()
      -- nvim-treesitter's master branch is frozen at Neovim 0.11 and registers
      -- its query predicates/directives with `all = false`, a compatibility
      -- mode Neovim 0.12 removed: handlers now always receive
      -- `table<integer, TSNode[]>`. Restore the old single-node contract for
      -- exactly those handlers, or every query using one of them (markdown
      -- fenced-code injections, bash heredocs, groovy/r indents) throws
      -- "attempt to call method 'range' (a nil value)".
      local tsq = require("vim.treesitter.query")
      local function unwrap(match)
        local out = {}
        for id, nodes in pairs(match) do
          out[id] = type(nodes) == "table" and nodes[#nodes] or nodes
        end
        return out
      end
      local function compat(add)
        return function(name, handler, o)
          if type(o) == "table" and o.all == false then
            local inner = handler
            handler = function(m, pattern, source, pred, metadata)
              return inner(unwrap(m), pattern, source, pred, metadata)
            end
          end
          return add(name, handler, o)
        end
      end
      tsq.add_predicate = compat(tsq.add_predicate)
      tsq.add_directive = compat(tsq.add_directive)
    end,
    event = { "BufReadPost", "BufNewFile" },
    opts = {
      ensure_installed = {
        "bash",
        "dot",
        "gitcommit",
        "groovy",
        "json",
        "jsonc",
        "lua",
        "luadoc",
        "markdown",
        "markdown_inline",
        "nix",
        "python",
        "r",
        "rnoweb",
        "toml",
        "typst",
        "vim",
        "vimdoc",
        "yaml",
      },
      highlight = { enable = true },
      indent = { enable = true },
    },
    config = function(_, opts)
      require("nvim-treesitter.configs").setup(opts)
      vim.treesitter.language.register("groovy", "nextflow")
    end,
  },
}
