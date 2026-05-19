require "nvchad.autocmds"

vim.api.nvim_create_autocmd("FileType", {
  pattern = "NvimTree",
  callback = function(args)
    vim.keymap.set("n", "E", "<nop>", { buffer = args.buf, nowait = true })
  end,
})
