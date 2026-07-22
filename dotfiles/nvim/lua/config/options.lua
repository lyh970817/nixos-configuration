vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

local opt = vim.opt

opt.autowrite = true

-- Over SSH, sync yanks to the client terminal's clipboard via OSC 52.
-- osc52-copy (from tmux.nix) targets every tmux client tty explicitly,
-- since tmux/mosh drop the empty-target form. Paste queries are not
-- answerable over mosh, so paste returns the last in-instance yank;
-- pasting from the client side works via terminal (bracketed) paste.
if vim.env.SSH_CONNECTION then
  local cache = { lines = {}, regtype = "v" }
  local function copy(lines, regtype)
    cache = { lines = lines, regtype = regtype }
    if vim.env.TMUX then
      vim.system({ "osc52-copy" }, { stdin = table.concat(lines, "\n") })
    else
      require("vim.ui.clipboard.osc52").copy("+")(lines)
    end
  end
  local function paste()
    return { cache.lines, cache.regtype }
  end
  vim.g.clipboard = {
    name = "osc52-tmux",
    copy = { ["+"] = copy, ["*"] = copy },
    paste = { ["+"] = paste, ["*"] = paste },
  }
end
opt.clipboard = "unnamedplus"

opt.completeopt = "menu,menuone,noselect"
opt.conceallevel = 2
opt.confirm = true
opt.cursorline = false
opt.equalalways = false
opt.expandtab = true
opt.fillchars = {
  foldopen = "",
  foldclose = "",
  fold = " ",
  foldsep = " ",
  diff = "╱",
  eob = " ",
}
opt.foldlevel = 99
opt.foldmethod = "indent"
opt.foldtext = ""
opt.formatoptions = "jcroqlnt"
opt.grepformat = "%f:%l:%c:%m"
opt.grepprg = "rg --vimgrep"
opt.ignorecase = true
opt.inccommand = "nosplit"
opt.jumpoptions = "view"
opt.laststatus = 3
opt.linebreak = true
opt.list = true
opt.mouse = "a"
opt.number = true
opt.pumblend = 10
opt.pumheight = 10
opt.relativenumber = true
opt.ruler = false
opt.scrolloff = 4
opt.shiftround = true
opt.shiftwidth = 2
opt.shortmess:append({ W = true, I = true, c = true, C = true })
opt.showmode = false
opt.sidescrolloff = 8
opt.signcolumn = "yes"
opt.smartcase = true
opt.smartindent = true
opt.smoothscroll = true
opt.spelllang = { "en" }
opt.splitbelow = true
opt.splitkeep = "screen"
opt.splitright = true
opt.tabstop = 2
opt.termguicolors = true
opt.timeoutlen = 300
opt.undofile = true
opt.undolevels = 10000
opt.updatetime = 200
opt.virtualedit = "block"
opt.wildmode = "longest:full,full"
opt.winminwidth = 5
opt.wrap = false

vim.g.markdown_recommended_style = 0

require("config.theme").apply_system()

vim.api.nvim_create_autocmd("VimResized", {
  pattern = "*",
  command = "redraw!",
  desc = "Force redraw on resize to prevent text loss",
})

vim.filetype.add({
  extension = {
    nf = "nextflow",
  },
})
