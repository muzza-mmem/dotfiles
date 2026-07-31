return {
  {
    "stevearc/conform.nvim",
    -- event = 'BufWritePre', -- uncomment for format on save
    opts = require "configs.conform",
  },

  -- These are some examples, uncomment them if you want to see them work!
  {
    "neovim/nvim-lspconfig",
    config = function()
      require "configs.lspconfig"
    end,
  },

  -- test new blink
  -- { import = "nvchad.blink.lazyspec" },

  {
    "nvim-tree/nvim-tree.lua",
    cmd = { "NvimTreeToggle", "NvimTreeFocus", "NvimTreeOpen", "NvimTreeFindFile", "NvimTreeFindFileToggle" },
    init = function()
      -- opening a directory -> tree focused on it; opening a file -> tree as a
      -- sidebar rooted at the containing dir, cursor left in the file
      vim.api.nvim_create_autocmd("VimEnter", {
        once = true,
        callback = function()
          local arg = vim.fn.argv(0)
          if arg == "" or vim.bo.filetype == "gitcommit" or vim.bo.filetype == "gitrebase" then
            return
          end

          local is_dir = vim.fn.isdirectory(arg) == 1
          local dir = is_dir and arg or vim.fn.fnamemodify(arg, ":p:h")
          if vim.fn.isdirectory(dir) == 0 then
            return
          end

          -- sync_root_with_cwd is on, so cwd decides the tree root
          vim.cmd.cd(vim.fn.fnameescape(dir))
          require("lazy").load { plugins = { "nvim-tree.lua" } }

          if is_dir then
            require("nvim-tree.api").tree.open { focus = true }
          else
            require("nvim-tree.api").tree.find_file { open = true, focus = false }
          end
        end,
      })
    end,
    opts = function()
      local opts = require "nvchad.configs.nvimtree"
      opts.hijack_directories = { enable = true, auto_open = true }
      return opts
    end,
  },

  {
    "lewis6991/gitsigns.nvim",
    opts = {
      current_line_blame = true,
      current_line_blame_opts = {
        virt_text = true,
        virt_text_pos = "eol",
        delay = 300,
      },
    },
  },

  -- {
  -- 	"nvim-treesitter/nvim-treesitter",
  -- 	opts = {
  -- 		ensure_installed = {
  -- 			"vim", "lua", "vimdoc",
  --      "html", "css"
  -- 		},
  -- 	},
  -- },
}
