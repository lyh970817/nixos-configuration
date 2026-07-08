local function executable(name)
  return vim.fn.executable(name) == 1
end

local function harper_handler(err, result, ctx, config)
  if result and result.diagnostics then
    for _, diagnostic in ipairs(result.diagnostics) do
      diagnostic.severity = vim.diagnostic.severity.HINT
    end
  end
  return vim.lsp.diagnostic.on_publish_diagnostics(err, result, ctx, config)
end

return {
  {
    "stevearc/conform.nvim",
    event = { "BufWritePre" },
    cmd = { "ConformInfo" },
    opts = {
      formatters_by_ft = {
        typst = { "typstyle" },
      },
      format_on_save = function(bufnr)
        if vim.bo[bufnr].filetype == "typst" then
          return { timeout_ms = 1500, lsp_format = "fallback" }
        end
      end,
    },
    config = function(_, opts)
      require("conform").setup(opts)
    end,
  },

  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = {
      "saghen/blink.cmp",
      "b0o/SchemaStore.nvim",
    },
    config = function()
      local icons = require("config.icons")
      vim.diagnostic.config({
        virtual_text = false,
        underline = true,
        update_in_insert = false,
        severity_sort = true,
        signs = {
          text = {
            [vim.diagnostic.severity.ERROR] = icons.diagnostics.Error,
            [vim.diagnostic.severity.WARN] = icons.diagnostics.Warn,
            [vim.diagnostic.severity.HINT] = icons.diagnostics.Hint,
            [vim.diagnostic.severity.INFO] = icons.diagnostics.Info,
          },
        },
      })

      local capabilities = require("blink.cmp").get_lsp_capabilities()
      capabilities.workspace = capabilities.workspace or {}
      capabilities.workspace.fileOperations = {
        didRename = true,
        willRename = true,
      }

      local lspconfig = require("lspconfig")
      local root = require("config.root")

      local function setup(server, opts)
        opts = opts or {}
        opts.capabilities = vim.tbl_deep_extend("force", capabilities, opts.capabilities or {})
        lspconfig[server].setup(opts)
      end

      if executable("tinymist") then
        setup("tinymist")
      end

      if executable("R") then
        setup("r_language_server", {
          cmd = {
            "env",
            "R_PROFILE_USER=/dev/null",
            "R",
            "--no-echo",
            "--no-restore",
            "-e",
            "languageserver::run()",
          },
          filetypes = { "r", "rmd", "quarto" },
          root_dir = function(fname)
            return vim.fs.root(fname, {
              "renv.lock",
              ".Rprofile",
              "DESCRIPTION",
              "NAMESPACE",
              ".Rbuildignore",
              ".here",
              ".git",
            }) or vim.fs.dirname(fname)
          end,
        })
      end

      if executable("nil") then
        setup("nil_ls", {
          settings = {
            ["nil"] = {
              formatting = {
                command = { "nixfmt" },
              },
            },
          },
        })
      end

      if executable("vscode-json-language-server") then
        setup("jsonls", {
          settings = {
            json = {
              schemas = require("schemastore").json.schemas(),
              validate = { enable = true },
            },
          },
        })
      end

      if executable("marksman") then
        setup("marksman")
      end

      if executable("lua-language-server") then
        setup("lua_ls", {
          settings = {
            Lua = {
              workspace = { checkThirdParty = false },
              completion = { callSnippet = "Replace" },
              diagnostics = { globals = { "vim" } },
            },
          },
        })
      end

      if executable("harper-ls") then
        setup("harper_ls", {
          filetypes = { "typst", "markdown", "text", "gitcommit" },
          handlers = {
            ["textDocument/publishDiagnostics"] = harper_handler,
          },
        })
      end

      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(event)
          local map = function(mode, lhs, rhs, desc)
            vim.keymap.set(mode, lhs, rhs, { buffer = event.buf, desc = desc, silent = true })
          end

          map("n", "gd", function() require("snacks").picker.lsp_definitions() end, "Goto Definition")
          map("n", "gr", function() require("snacks").picker.lsp_references() end, "References")
          map("n", "gI", function() require("snacks").picker.lsp_implementations() end, "Goto Implementation")
          map("n", "gy", function() require("snacks").picker.lsp_type_definitions() end, "Goto Type Definition")
          map("n", "gD", vim.lsp.buf.declaration, "Goto Declaration")
          map("n", "K", vim.lsp.buf.hover, "Hover")
          map("n", "gK", vim.lsp.buf.signature_help, "Signature Help")
          map("i", "<C-k>", vim.lsp.buf.signature_help, "Signature Help")
          map({ "n", "x" }, "<leader>ca", vim.lsp.buf.code_action, "Code Action")
          map("n", "<leader>cr", vim.lsp.buf.rename, "Rename")
          map("n", "<leader>ss", function() require("snacks").picker.lsp_symbols() end, "LSP Symbols")
          map("n", "<leader>sS", function()
            require("snacks").picker.lsp_workspace_symbols()
          end, "LSP Workspace Symbols")

          if vim.lsp.inlay_hint then
            pcall(vim.lsp.inlay_hint.enable, true, { bufnr = event.buf })
          end
        end,
      })

      vim.keymap.set("n", "<leader>sd", function()
        require("snacks").picker.diagnostics()
      end, { desc = "Diagnostics" })
      vim.keymap.set("n", "<leader>sD", function()
        require("snacks").picker.diagnostics_buffer()
      end, { desc = "Buffer Diagnostics" })
      vim.keymap.set("n", "<leader>cl", function()
        vim.cmd.LspInfo()
      end, { desc = "LSP Info" })

      vim.api.nvim_create_user_command("Root", function()
        vim.notify(root.get(0))
      end, {})
    end,
  },
}
