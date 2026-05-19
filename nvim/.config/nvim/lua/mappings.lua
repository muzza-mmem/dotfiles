require "nvchad.mappings"

-- add yours here

local map = vim.keymap.set

map("n", ";", ":", { desc = "CMD enter command mode" })
map("i", "jk", "<ESC>")

map("n", "E", "<cmd>NvimTreeFindFileToggle<cr>", { desc = "nvimtree toggle (find current file)" })

-- map({ "n", "i", "v" }, "<C-s>", "<cmd> w <cr>")
