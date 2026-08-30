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
opt.swapfile = false
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
  { src = "https://github.com/catppuccin/nvim", name = "catppuccin" },
})

-- Meme theme que wezterm (~/.wezterm.lua).
vim.cmd.colorscheme("catppuccin-macchiato")

-- ---------------------------------------------------------------- lsp
--
-- brew install pyright gopls typescript
--   pyright -> pyright-langserver --stdio
--   gopls   -> gopls
--   tsc     -> tsc --lsp --stdio  (TypeScript 7+, compilateur Go, mode --lsp natif —
--              c'est ce que "tsgo" est devenu ; nvim-lspconfig déprécie tsgo au profit de tsc)

--   templ   -> templ lsp  (deja installe via go install github.com/a-h/templ/cmd/templ@latest ;
--              nvim 0.12 detecte *.templ nativement, rien a ajouter cote filetype)
--   tailwindcss -> tailwindcss-language-server  (npm i -g @tailwindcss/language-server ;
--              nvim-lspconfig couvre deja le ft templ et mappe templ -> html.
--              Ne demarre QUE si la racine a un package.json avec la dep tailwindcss,
--              un tailwind.config.* ou un .git — sinon silence total, c'est normal)
--   sqls    -> sqls  (go install github.com/sqls-server/sqls@latest ;
--              ne demarre qu'avec un config.yml a la racine du projet decrivant
--              la connexion DB — sans ca, seul le formatage pg_format s'applique)

vim.lsp.enable({ "pyright", "gopls", "templ", "tailwindcss", "tsc", "sqls" })

vim.diagnostic.config({
  severity_sort = true,
  signs = {
    text = {
      [vim.diagnostic.severity.ERROR] = "●",
      [vim.diagnostic.severity.WARN] = "●",
      [vim.diagnostic.severity.INFO] = "●",
      [vim.diagnostic.severity.HINT] = "●",
    },
  },
  underline = true,
  virtual_text = false,
  virtual_lines = false,
  float = {
    border = "rounded",
    max_width = 80,
    source = "if_many",
    header = "",
    title = { { " Diagnostics ", "FloatTitle" } },
    title_pos = "left",
  },
})

-- Affiche automatiquement les diagnostics de la ligne courante dans une
-- fenetre flottante. Elle ne prend jamais le focus et disparait des que le
-- curseur quitte la ligne, afin de rester lisible sans interrompre l'edition.
local diagnostic_float_win

local function close_diagnostic_float()
  if diagnostic_float_win and vim.api.nvim_win_is_valid(diagnostic_float_win) then
    vim.api.nvim_win_close(diagnostic_float_win, true)
  end
  diagnostic_float_win = nil
end

local function show_diagnostic_float()
  close_diagnostic_float()

  -- Ne pas recouvrir la completion ni ouvrir un float depuis un autre float.
  if vim.fn.pumvisible() == 1 or vim.api.nvim_win_get_config(0).relative ~= "" then
    return
  end

  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  if vim.tbl_isempty(vim.diagnostic.get(0, { lnum = line })) then
    return
  end

  local _, winid = vim.diagnostic.open_float({
    scope = "line",
    focus = false,
    focusable = false,
    close_events = { "BufLeave", "CursorMoved", "InsertEnter", "FocusLost" },
  })
  diagnostic_float_win = winid
end

local diagnostic_float_group = vim.api.nvim_create_augroup("diagnostic_float", { clear = true })
vim.api.nvim_create_autocmd({ "BufEnter", "CursorHold", "CursorMoved", "DiagnosticChanged", "InsertLeave" }, {
  group = diagnostic_float_group,
  callback = function()
    vim.schedule(show_diagnostic_float)
  end,
})

-- Copie directement dans le presse-papiers systeme les diagnostics de la ligne.
local function copy_diagnostic()
  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  local diagnostics = vim.diagnostic.get(0, { lnum = line })
  if vim.tbl_isempty(diagnostics) then
    vim.notify("Aucun diagnostic sur cette ligne", vim.log.levels.INFO)
    return
  end

  table.sort(diagnostics, function(a, b)
    return a.severity < b.severity
  end)
  local messages = vim.tbl_map(function(diagnostic)
    return diagnostic.message
  end, diagnostics)
  vim.fn.setreg("+", table.concat(messages, "\n"))
  vim.notify(#messages == 1 and "Diagnostic copie" or (#messages .. " diagnostics copies"))
end

vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    local bufnr = args.buf
    local client = vim.lsp.get_client_by_id(args.data.client_id)

    -- autotrigger = false : le menu ne s'ouvre jamais tout seul (pas sur le
    -- point apres `fmt.`), uniquement sur <C-l>. Voir le mapping plus bas.
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
    map("n", "gh", copy_diagnostic)
    map("n", "<leader>rn", vim.lsp.buf.rename)
    map({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action)
    map("n", "<leader>d", vim.diagnostic.open_float)
    map("n", "[d", function() vim.diagnostic.jump({ count = -1, float = true }) end)
    map("n", "]d", function() vim.diagnostic.jump({ count = 1, float = true }) end)
  end,
})

-- ---------------------------------------------------------------- fzf-lua

local fzf = require("fzf-lua")
vim.keymap.set("n", "<leader><Space>", fzf.files, { desc = "Fichiers" })
vim.keymap.set("n", "<leader>/", fzf.live_grep, { desc = "Grep" })
vim.keymap.set("n", "<leader>fb", fzf.buffers, { desc = "Buffers" })
vim.keymap.set("n", "<leader>fd", fzf.diagnostics_document, { desc = "Diagnostics" })
vim.keymap.set("n", "<leader>fs", fzf.lsp_document_symbols, { desc = "Symboles" })

-- ---------------------------------------------------------------- format
--
-- brew install ruff goimports prettier pgformatter

require("conform").setup({
  formatters_by_ft = {
    python = { "ruff_format" },
    go = { "goimports" },
    templ = { "templ" },  -- templ fmt -stdin-filepath
    typescript = { "prettier" },
    typescriptreact = { "prettier" },
    javascript = { "prettier" },
    javascriptreact = { "prettier" },
    json = { "prettier" },
    sql = { "pg_format" },
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
  filters = {
    custom = { ".*_templ\\.go$" },
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
-- <C-l> ouvre le menu LSP a la demande. <C-x><C-o> (omnifunc) marche aussi,
-- nativement. Dans le menu : <Tab>/<S-Tab> naviguent, <C-y> valide, <C-e> ferme.

vim.keymap.set("i", "<C-l>", function()
  vim.lsp.completion.get()
end, { desc = "Completion LSP" })
