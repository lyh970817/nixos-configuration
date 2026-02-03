return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      -- 1. Ensure the groovy parser is installed
      if type(opts.ensure_installed) == "table" then
        vim.list_extend(opts.ensure_installed, { "groovy" })
      end

      -- 2. Register 'nextflow' filetype to use the 'groovy' parser
      vim.treesitter.language.register("groovy", "nextflow")
    end,
  },
}
