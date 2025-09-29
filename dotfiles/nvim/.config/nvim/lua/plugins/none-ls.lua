return {
    "nvimtools/none-ls.nvim",
    dependencies = {
      "nvimtools/none-ls-extras.nvim",
    },
    config = function()
        local null_ls = require("null-ls")
        null_ls.setup({
            sources = { 
                -- PHP: Linting and formatting
                null_ls.builtins.diagnostics.phpcs.with({
                    extra_args = {"--standard=PSR12"}
                }),
                null_ls.builtins.formatting.phpcbf.with({
                    extra_args = {"--standard=PSR12"}
                }),

                -- JS/TS/HTML/CSS/JSON/SCSS: Prettier
                null_ls.builtins.formatting.prettier,

                -- Python: Black for formatting, flake8 for linting
                null_ls.builtins.formatting.black,
                -- null_ls.builtins.diagnostics.flake8, -- Use extras!

                -- Go: gofumpt for formatting, golangci-lint for linting
                null_ls.builtins.formatting.gofumpt,
                null_ls.builtins.diagnostics.golangci_lint,

                -- Shell: shellcheck for linting, shfmt for formatting
                -- null_ls.builtins.diagnostics.shellcheck, -- Use extras!
                null_ls.builtins.formatting.shfmt,
            }
        })
    end
}



-- return {
--   "nvimtools/none-ls.nvim",
--   config = function()
--     local null_ls = require("null-ls")
--     null_ls.setup({
--       sources = {
--         null_ls.builtins.formatting.stylua,
--         null_ls.builtins.formatting.prettier,
--         null_ls.builtins.formatting.shellharden,
--         null_ls.builtins.diagnostics.erb_lint,
--       },
--     })
--
--     vim.keymap.set("n", "<leader>gf", vim.lsp.buf.format, {})
--   end,
-- }
