local group = vim.api.nvim_create_augroup("local_config", { clear = true })

vim.api.nvim_create_autocmd("TextYankPost", {
  group = group,
  callback = function()
    vim.highlight.on_yank()
  end,
  desc = "Highlight yanked text",
})

vim.api.nvim_create_autocmd("BufReadPost", {
  group = group,
  callback = function(event)
    local exclude = { "gitcommit" }
    local buf = event.buf
    if vim.tbl_contains(exclude, vim.bo[buf].filetype) or vim.b[buf].last_loc_applied then
      return
    end

    vim.b[buf].last_loc_applied = true
    local mark = vim.api.nvim_buf_get_mark(buf, '"')
    local line_count = vim.api.nvim_buf_line_count(buf)
    if mark[1] > 0 and mark[1] <= line_count then
      pcall(vim.api.nvim_win_set_cursor, 0, mark)
    end
  end,
  desc = "Go to last edit location",
})

vim.api.nvim_create_autocmd("FileType", {
  group = group,
  pattern = { "typst", "markdown", "text", "gitcommit" },
  callback = function()
    vim.opt_local.spell = true
  end,
  desc = "Enable spelling in writing buffers",
})
