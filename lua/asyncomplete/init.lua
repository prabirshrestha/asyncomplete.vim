local M = {}
local C = require 'asyncomplete/callbag'
local disable = nil

local has_lua = false

function M.has_lua()
    return has_lua
end

function M.init()
    if vim and vim.fn and vim.fn.has and (vim.fn.has('nvim-0.5.0') or (vim.fn.has('lua') and vim.fn.has('patch-8.2.1066')) == 0) then
        has_lua = true
    else
        has_lua = false
    end

    M.enable()
end

function M.enable()
    if not has_lua then return end
    if disable then return end

    disable = C.pipe(
        C.fromEvent('InsertEnter', 'asyncomplete__insertenter'),
        C.map(function() print('insert enter') end),
        C.switchMap(function ()
            return C.pipe(
                C.fromEvent({ 'TextChanged', 'TextChangedI', 'TextChangedP' }, 'asyncomplete__textchanged'),
                C.map(function () print('textchanged') end),
                C.takeUntil(
                    C.pipe(
                        C.fromEvent('InsertLeave', 'asyncomplete__insertleave'),
                        C.map(function() print('insert leave') end)
                    )
                )
            )
        end),
        C.subscribe({})
    )
end

function M.disable()
    if not disable then
        disable()
        disable = nil
    end
end

return M
