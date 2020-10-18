local M = {}

local has_lua = false

function M.has_lua()
    return has_lua
end

function M.init()
    if vim.fn.has('nvim-0.5.0') or (vim.fn.has('lua') and vim.fn.has('patch-8.2.1066')) == 0 then
        has_lua = true
    else
        has_lua = false
    end
end

return M
