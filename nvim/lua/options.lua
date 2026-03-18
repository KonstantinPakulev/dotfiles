require "nvchad.options"

-- add yours here!

vim.o.autoread = true
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold" }, {
  command = "checktime",
})
-- local o = vim.o
-- o.cursorlineopt ='both' -- to enable cursorline!
