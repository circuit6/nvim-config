local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", -- latest stable release
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- This is where lazy.nvim's setup begins. All your plugins will go inside the 'plugins' table.
require("lazy").setup({
  -- LSP Configuration for Go
  {
    "neovim/nvim-lspconfig",
    dependencies = {
      -- Automatically install LSP servers
      { "williamboman/mason.nvim", version = "1.11.0" },
      { "williamboman/mason-lspconfig.nvim", version = "1.32.0" },
      -- Autocompletion plugin
      "hrsh7th/nvim-cmp",
      "hrsh7th/cmp-nvim-lsp",
      "saadparwaiz1/cmp_luasnip", -- For snippets
      "L3MON4D3/LuaSnip", -- Snippet engine
      "hrsh7th/cmp-buffer", -- Source for buffer words
      "hrsh7th/cmp-path",   -- Source for file paths
    },
    config = function()
      -- Configure Mason to install LSP servers
      require("mason").setup()
      require("mason-lspconfig").setup({
        -- list of servers to ensure are installed
        ensure_installed = {
          "gopls",  -- Go Language Server
        },
      })

      -- Configure nvim-cmp (autocompletion)
      local cmp = require("cmp")
      local luasnip = require("luasnip")

      cmp.setup({
        snippet = {
          expand = function(args)
            luasnip.lsp_expand(args.body)
          end,
        },
        mapping = cmp.mapping.preset.insert({
          ['<C-b>'] = cmp.mapping.scroll_docs(-4),
          ['<C-f>'] = cmp.mapping.scroll_docs(4),
          ['<C-Space>'] = cmp.mapping.complete(),
          ['<C-e>'] = cmp.mapping.abort(),
          ['<CR>'] = cmp.mapping.confirm({ select = true }), -- Accept currently selected item. Set `select` to `false` to only confirm explicitly selected items.
        }),
        sources = cmp.config.sources({
          { name = 'nvim_lsp' }, -- LSP completion (from gopls)
          { name = 'luasnip' },  -- Snippets
          { name = 'buffer' },   -- Current buffer words
          { name = 'path' },     -- File system paths
        })
      })

      -- Configure LSP servers using nvim-lspconfig
      local lspconfig = require("lspconfig")

      -- Common LSP capabilities
      local capabilities = vim.lsp.protocol.make_client_capabilities()
      capabilities = require('cmp_nvim_lsp').default_capabilities(capabilities)

      -- Corrected on_attach function using vim.keymap.set
      local on_attach = function(client, bufnr)
          -- Enable completion (default, but good to ensure)
          if client.server_capabilities.completionProvider then
              vim.api.nvim_buf_set_option(bufnr, 'omnifunc', 'v:lua.vim.lsp.omnifunc')
          end

          -- Mappings for LSP features (common ones)
          -- The 'buffer = bufnr' option makes it buffer-local automatically
          local opts = { noremap = true, silent = true, buffer = bufnr }

          -- Go to definition
          vim.keymap.set('n', 'gd', vim.lsp.buf.definition, opts)
          -- Go to type definition
          vim.keymap.set('n', 'gt', vim.lsp.buf.type_definition, opts)
          -- Go to declarations
          vim.keymap.set('n', 'gD', vim.lsp.buf.declaration, opts)
          -- Go to references
          vim.keymap.set('n', 'gr', vim.lsp.buf.references, opts)
          -- Hover documentation
          vim.keymap.set('n', 'K', vim.lsp.buf.hover, opts)
          -- Code actions
          vim.keymap.set('n', '<leader>ca', vim.lsp.buf.code_action, opts)
          -- Rename symbol
          vim.keymap.set('n', '<leader>rn', vim.lsp.buf.rename, opts)
          -- Format (on save or manually)
          vim.keymap.set('n', '<leader>f', function() vim.lsp.buf.format({ async = true }) end, opts)
          -- Diagnostic functions
          vim.keymap.set('n', '[d', vim.diagnostic.goto_prev, opts)
          vim.keymap.set('n', ']d', vim.diagnostic.goto_next, opts)
          vim.keymap.set('n', '<leader>q', vim.diagnostic.setloclist, opts)
          vim.keymap.set('n', '<leader>do', vim.diagnostic.open_float, opts)
      end

      -- Setup gopls (Go Language Server)
      lspconfig.gopls.setup({
        on_attach = on_attach,
        capabilities = capabilities,
        settings = {
          gopls = {
            analyses = {
              unusedparams = true,
              unusedwrite = true,
            },
            staticcheck = true,
            gofumpt = true,
          },
        },
      })

      -- Removed Python LSP (pyright) setup for now
      -- lspconfig.pyright.setup({
      --   on_attach = on_attach,
      --   capabilities = capabilities,
      -- })
    end,
  },

  -- Add nvim-autopairs for auto-closing brackets and quotes
  {
    "windwp/nvim-autopairs",
    event = "InsertCharPre", -- Only load when about to insert a char (efficient)
    opts = {
      check_ts = true, -- Check Treesitter context for better pairing logic (if you install Treesitter later)
      ts_config = {
        lua = {'string', 'source'},
        javascript = {'string','template_string'},
        typescript = {'string','template_string'},
        html = {'template_string'},
      }
    },
    config = function()
      require("nvim-autopairs").setup()
      -- Integrate with nvim-cmp for smoother completion confirmation
      -- local cmp_autopairs = require('nvim-autopairs.cmp')
      -- local cmp = require('cmp')
      -- cmp.event:on(
      --   'confirm_done',
      --   cmp_autopairs.on_confirm_done()
      -- )
    end
  },
}, {
  -- Options for lazy.nvim itself (optional, but good to have)
  install = { colorscheme = { "habamax" } }, -- set a basic colorscheme during installation
  checker = { enabled = true },             -- automatically check for plugin updates
  performance = {
    rtp = {
      -- disable some vim plugins
      disabled_plugins = {
        "gzip",
        "netrwPlugin",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
})
-- ~/.config/nvim/init.lua

-- =========================================================================
--  Todo Workflow Module Integration
-- =========================================================================

-- Define an augroup for your todo autocommands
-- This helps clear and manage related autocommands cleanly.
vim.api.nvim_create_augroup("TodoWorkflowCleanup", { clear = true })

-- Autocommand to run cleanup before saving specific todo files
-- This ensures your todo file is formatted correctly on save.
-- IMPORTANT: Adjust the 'pattern' to match your actual todo file names/types.
vim.api.nvim_create_autocmd("BufWritePre", {
    group = "TodoWorkflowCleanup",
    pattern = { "*.md", "todo.txt", "tasks.txt" }, -- Example patterns. Modify as needed!
    callback = function()
        -- Safely attempt to load the module and call the cleanup function
        if pcall(require, 'todo_workflow') then
            local M = require('todo_workflow')
            if type(M.clean_up_structure) == 'function' then
                M.clean_up_structure()
            end
        end
    end,
    desc = "Clean up todo file structure before saving",
})

-- =========================================================================
--  Define Custom Commands and Keymaps (on VimEnter)
-- =========================================================================
-- This autocommand ensures that your custom commands and keymaps are
-- defined AFTER Neovim has fully initialized and all plugins are loaded.
-- This prevents issues where 'todo_workflow' might not be fully available yet.
vim.api.nvim_create_autocmd("VimEnter", {
    group = "TodoWorkflowCleanup", -- Re-use the same augroup
    callback = function()
        -- Re-require the module inside the callback to ensure it's loaded
        -- at the time the commands are being defined.
        if pcall(require, 'todo_workflow') then
            local M = require('todo_workflow')

            -- Define Neovim user commands for your functions
            -- You can now use :Ni and :Xx in command mode
            vim.cmd('command! Ni lua require("todo_workflow").new_todo_item()')
            vim.cmd('command! Xx lua require("todo_workflow").finish_todo_item()')

            -- Optionally, define keymaps for convenience
            -- Example: `<leader>ni` and `<leader>xx` in normal mode
            vim.keymap.set('n', '<leader>ni', '<cmd>Ni<CR>', { desc = 'New Todo Item' })
            vim.keymap.set('n', '<leader>xx', '<cmd>Xx<CR>', { desc = 'Finish Todo Item' })
        else
            -- Optional: notify if the module failed to load even on VimEnter
            vim.notify("Error: 'todo_workflow' module could not be loaded for commands.", vim.log.levels.ERROR, { title = "Todo Workflow" })
        end
    end,
    desc = "Define custom todo commands and keymaps after Vim initializes",
})

-- Other general Neovim configuration can go here, e.g., options, other plugins, etc.
-- vim.opt.tabstop = 4
-- vim.opt.shiftwidth = 4
-- etc.
-- Basic Neovim Configuration (Runs after Plugins)
-- Your colorscheme and options (these are working, keep them)
vim.cmd('colorscheme industry')
vim.opt.termguicolors = true
-- Add these two lines for line numbering
vim.opt.number = true         -- Turn on absolute line numbers for the current line
vim.opt.relativenumber = true -- Turn on relative line numbers for other lines

-- Remap movement keys to jklö (right hand) for Normal, Visual, and Operator-pending modes

-- Configure how diagnostics are displayed
vim.diagnostic.config({
    virtual_text = true, -- Display diagnostic messages as virtual text (next to the line)
    signs = true,        -- Display symbols in the sign column
    update_in_insert = false, -- Do not update diagnostics in Insert mode
    float = {
        focusable = false,
        style = "minimal",
        border = "single",
        source = "always",
        header = "",
        prefix = "",
    },
})

-- Optional: Autocmd to open diagnostic float on cursor hold (alternative to mouse hover)
-- This means if you stop moving your cursor over a diagnostic, the float pops up.
vim.cmd([[
  augroup lsp_diagnostics_autocmds
    autocmd!
    autocmd CursorHold * lua vim.diagnostic.open_float(nil, {focus=false})
  augroup END
]])


-- Auto-formatting on save for Go files (keep this for formatting)
vim.cmd('autocmd BufWritePre *.go lua vim.lsp.buf.format({ async = true })')

-- Normal mode mappings
-- Use 'noremap = true' to prevent recursive remapping
-- Use 'silent = true' to prevent Neovim from echoing the command
-- Add 'desc' for better readability with :map (Neovim 0.7+)

-- Remap 'j' (your desired 'h' - left)
vim.api.nvim_set_keymap('n', 'j', 'h', { noremap = true, silent = true, desc = "Move Left" })

-- Remap 'k' (your desired 'j' - down)
vim.api.nvim_set_keymap('n', 'k', 'j', { noremap = true, silent = true, desc = "Move Down" })

-- Remap 'l' (your desired 'k' - up)
vim.api.nvim_set_keymap('n', 'l', 'k', { noremap = true, silent = true, desc = "Move Up" })

-- Remap 'ö' (your desired 'l' - right)
-- IMPORTANT: This uses the lowercase 'ö' character.
vim.api.nvim_set_keymap('n', 'ö', 'l', { noremap = true, silent = true, desc = "Move Right" })


-- Visual mode mappings (for consistency when selecting text)
vim.api.nvim_set_keymap('v', 'j', 'h', { noremap = true, silent = true, desc = "Move Left (Visual)" })
vim.api.nvim_set_keymap('v', 'k', 'j', { noremap = true, silent = true, desc = "Move Down (Visual)" })
vim.api.nvim_set_keymap('v', 'l', 'k', { noremap = true, silent = true, desc = "Move Up (Visual)" })
vim.api.nvim_set_keymap('v', 'ö', 'l', { noremap = true, silent = true, desc = "Move Right (Visual)" })

-- Operator-pending mode mappings (for consistency with commands like 'dw', 'yj', etc.)
vim.api.nvim_set_keymap('o', 'j', 'h', { noremap = true, silent = true, desc = "Move Left (Operator)" })
vim.api.nvim_set_keymap('o', 'k', 'j', { noremap = true, silent = true, desc = "Move Down (Operator)" })
vim.api.nvim_set_keymap('o', 'l', 'k', { noremap = true, silent = true, desc = "Move Up (Operator)" })
vim.api.nvim_set_keymap('o', 'ö', 'l', { noremap = true, silent = true, desc = "Move Right (Operator)" })

-- Insert mode Mappings
vim.api.nvim_set_keymap('i', 'jj', '<Esc>', { noremap = true, silent = true, desc = "Exit Insert Mode with jj" })

-- You might also want to map the original h, j, k, l to something else if you don't want
-- them to perform their default actions (e.g., if you plan to use them for other commands).
-- If you leave them unmapped, they will still perform their original actions.
-- For example, to disable them (make them do nothing):
-- vim.api.nvim_set_keymap('n', 'h', '<nop>', { noremap = true, silent = true, desc = "No operation (h)" })
-- vim.api.nvim_set_keymap('n', 'j', '<nop>', { noremap = true, silent = true, desc = "No operation (j)" })
-- vim.api.nvim_set_keymap('n', 'k', '<nop>', { noremap = true, silent = true, desc = "No operation (k)" })
-- vim.api.nvim_set_keymap('n', 'l', '<nop>', { noremap = true, silent = true, desc = "No operation (l)" })
