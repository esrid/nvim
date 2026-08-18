-- Config minimale Neovim 0.12+
-- Gestionnaire de paquets natif (vim.pack) + API LSP native (vim.lsp.config /
-- vim.lsp.enable / vim.lsp.completion). Aucun plugin de complétion externe.

vim.g.mapleader = " "

-- ---------------------------------------------------------------- options

local opt = vim.opt
opt.number = true
opt.relativenumber = true
opt.expandtab = true
opt.shiftwidth = 2
opt.tabstop = 2
opt.smartindent = true
opt.ignorecase = true
opt.smartcase = true
opt.signcolumn = "yes"
opt.termguicolors = true
opt.updatetime = 250
opt.splitbelow = true
opt.splitright = true

-- ---------------------------------------------------------------- path
--
-- Les binaires Go (gopls, goimports) vivent dans $GOPATH/bin, qui n'est pas
-- forcement dans le PATH herite quand nvim est lance depuis un lanceur
-- graphique. On l'ajoute ici pour que LSP et conform les trouvent toujours.

for _, dir in ipairs({ vim.env.HOME .. "/go/bin", vim.env.HOME .. "/.local/bin" }) do
  if vim.fn.isdirectory(dir) == 1 and not string.find(vim.env.PATH, dir, 1, true) then
    vim.env.PATH = dir .. ":" .. vim.env.PATH
  end
end

-- ---------------------------------------------------------------- paquets

vim.pack.add({
  { src = "https://github.com/neovim/nvim-lspconfig" },
  { src = "https://github.com/ibhagwan/fzf-lua" },
  { src = "https://github.com/nvim-tree/nvim-tree.lua" },
  { src = "https://github.com/nvim-tree/nvim-web-devicons" },
  { src = "https://github.com/stevearc/conform.nvim" },
  { src = "https://github.com/windwp/nvim-autopairs" },
})

-- ---------------------------------------------------------------- lsp
--
-- pyright  : npm i -g pyright
-- gopls    : go install golang.org/x/tools/gopls@latest
-- tsc      : npm i -g typescript   (TypeScript 7+, compilateur Go, mode --lsp natif —
--            c'est ce que "tsgo" est devenu ; nvim-lspconfig déprécie tsgo au profit de tsc)

vim.lsp.enable({ "pyright", "gopls", "tsc" })

vim.diagnostic.config({
  virtual_text = true,
  severity_sort = true,
})

vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    local bufnr = args.buf
    local client = vim.lsp.get_client_by_id(args.data.client_id)

    -- autotrigger = false : le menu ne s'ouvre jamais tout seul (pas sur le
    -- point apres `fmt.`), uniquement sur <C-Space>. Voir le mapping plus bas.
    if client and client:supports_method("textDocument/completion") then
      vim.lsp.completion.enable(true, client.id, bufnr, { autotrigger = false })
    end

    local map = function(mode, lhs, rhs)
      vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, silent = true })
    end
    map("n", "gd", vim.lsp.buf.definition)
    map("n", "gD", vim.lsp.buf.declaration)
    map("n", "gr", vim.lsp.buf.references)
    map("n", "gi", vim.lsp.buf.implementation)
    map("n", "K", vim.lsp.buf.hover)
    map("n", "<leader>rn", vim.lsp.buf.rename)
    map({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action)
    map("n", "<leader>d", vim.diagnostic.open_float)
    map("n", "[d", function() vim.diagnostic.jump({ count = -1, float = true }) end)
    map("n", "]d", function() vim.diagnostic.jump({ count = 1, float = true }) end)
  end,
})

-- ---------------------------------------------------------------- fzf-lua

local fzf = require("fzf-lua")
vim.keymap.set("n", "<leader>ff", fzf.files, { desc = "Fichiers" })
vim.keymap.set("n", "<leader>fg", fzf.live_grep, { desc = "Grep" })
vim.keymap.set("n", "<leader>fb", fzf.buffers, { desc = "Buffers" })
vim.keymap.set("n", "<leader>fd", fzf.diagnostics_document, { desc = "Diagnostics" })
vim.keymap.set("n", "<leader>fs", fzf.lsp_document_symbols, { desc = "Symboles" })

-- ---------------------------------------------------------------- format
--
-- ruff (python)     : npm indépendant, installe via `pip install ruff` ou pacman
-- goimports (go)     : go install golang.org/x/tools/cmd/goimports@latest
-- prettier (ts/js)   : npm i -g prettier

require("conform").setup({
  formatters_by_ft = {
    python = { "ruff_format" },
    go = { "goimports" },
    typescript = { "prettier" },
    typescriptreact = { "prettier" },
    javascript = { "prettier" },
    javascriptreact = { "prettier" },
    json = { "prettier" },
  },
  format_on_save = { timeout_ms = 1000, lsp_format = "fallback" },
})

vim.keymap.set({ "n", "v" }, "<leader>f", function()
  require("conform").format({ async = true, lsp_format = "fallback" })
end, { desc = "Formater" })

-- ---------------------------------------------------------------- nvim-tree

local function nvim_tree_on_attach(bufnr)
  local api = require("nvim-tree.api")

  api.config.mappings.default_on_attach(bufnr)
  vim.keymap.set("n", "l", api.node.open.edit, {
    buffer = bufnr,
    desc = "NvimTree: Ouvrir le fichier ou entrer dans le dossier",
  })
  vim.keymap.set("n", "a", api.fs.create, {
    buffer = bufnr,
    desc = "NvimTree: Ajouter un fichier ou un dossier",
  })
end

require("nvim-tree").setup({
  on_attach = nvim_tree_on_attach,
  actions = {
    open_file = { quit_on_open = true },
  },
})
vim.keymap.set("n", "<leader>e", "<cmd>NvimTreeToggle<CR>", { desc = "File tree" })

-- ---------------------------------------------------------------- autopairs
--
-- Ferme automatiquement ( [ { " ' ` et supprime la paire au backspace.

require("nvim-autopairs").setup({
  check_ts = false,
  fast_wrap = {},
})

-- Sortir d'une paire en mode insertion : <Tab> saute par-dessus la prochaine
-- fermeture de la ligne. Appuis successifs pour sortir de plusieurs niveaux :
-- fmt.Println("hi|")  ->  fmt.Println("hi"|)  ->  fmt.Println("hi")|
--
-- Ordre de priorite, pour que <Tab> ne perde aucun de ses roles :
--   1. menu de completion ouvert -> item suivant (<S-Tab> = precedent)
--   2. une fermeture plus loin sur la ligne -> on saute par-dessus
--   3. sinon -> <Tab> normal (indentation, donc des espaces vu expandtab)

local closers = { [")"] = true, ["]"] = true, ["}"] = true, ['"'] = true, ["'"] = true, ["`"] = true }

local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "ni", false)
end

vim.keymap.set("i", "<Tab>", function()
  if vim.fn.pumvisible() == 1 then
    return feed("<C-n>")
  end
  local line = vim.api.nvim_get_current_line()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  for i = col + 1, #line do
    if closers[line:sub(i, i)] then
      return vim.api.nvim_win_set_cursor(0, { row, i })
    end
  end
  feed("<Tab>")
end, { desc = "Sortir de la paire / completion / indenter" })

vim.keymap.set("i", "<S-Tab>", function()
  if vim.fn.pumvisible() == 1 then
    return feed("<C-p>")
  end
  feed("<C-d>")
end, { desc = "Completion precedente / desindenter" })

-- ---------------------------------------------------------------- completion
--
-- <C-Space> ouvre le menu LSP a la demande. <C-x><C-o> (omnifunc) marche aussi,
-- nativement. Dans le menu : <Tab>/<S-Tab> naviguent, <C-y> valide, <C-e> ferme.

vim.keymap.set("i", "<C-Space>", function()
  vim.lsp.completion.get()
end, { desc = "Completion LSP" })
