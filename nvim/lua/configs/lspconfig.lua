require("nvchad.configs.lspconfig").defaults()

local lspconfig = require "lspconfig"

local python = os.getenv("PROJECT_PYTHON")
if python then
  lspconfig.basedpyright.setup {
    cmd = { "basedpyright-langserver", "--stdio" },
    settings = {
      python = {
        pythonPath = python,
      },
    },
  }
end

local servers = { "bashls", "lua_ls" }
vim.lsp.enable(servers)

-- read :h vim.lsp.config for changing options of lsp servers 
