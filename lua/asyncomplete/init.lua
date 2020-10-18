local M = {}
local C = require 'asyncomplete/callbag'
local disable = nil

local sources = {}

-- TODO: implement lazy()
local init = false
local has_lua = false
local has_nvim = false

function M.has_lua()
    return has_lua
end

function M.has_nvim()
    return has_nvim
end

local function vimlist_new()
    error('asyncomplete not initialized')
end

local function vimlist_insert(list, value)
    error('asyncomplete not initialized')
end

function M.init()
    if init then
        error('asyncomplete already inited')
        return
    end

    init = true

    if not (vim and vim.fn and vim.fn.has and (vim.fn.has('nvim-0.5.0') or (vim.fn.has('lua') and vim.fn.has('patch-8.2.1066')) == 0)) then
        has_lua = false
        return
    end

    has_lua = true
    has_nvim = vim.fn.has('nvim') == 1

    if M.has_nvim() then
        M.vimcmd = vim.api.nvim_command
        M.vimeval = vim.api.nvim_eval
        vimlist_new = function () return {} end
        vimlist_insert = function (list, value) table.insert(list, value) end
    else
        M.vimcmd = vim.command
        M.vimeval = vim.eval
        vimlist_new = function () return vim.list() end
        vimlist_insert = function (list, value) list:add(value) end
    end

    if M.is_enabled() then
        M.enable()
    end
end

function M.vimcmd(cmd)
    error('asyncomplete not initialized')
end

function M.vimeval(str)
    error('asyncomplete not initialized')
end

function M.enable()
    if not has_lua then return end
    if disable then return end

    disable = C.pipe(
        C.fromEvent('InsertEnter', 'asyncomplete__insertenter'),
        C.filter(function () return M.is_enabled() end),
        C.map(function () print('insert enter') end),
        C.map(function () M.get_active_sources_for_buffer() end), -- pre-cache active sources before the user starts typing
        C.switchMap(function ()
            return C.pipe(
                C.fromEvent({ 'TextChanged', 'TextChangedI', 'TextChangedP' }, 'asyncomplete__textchanged'),
                C.takeUntil(
                    C.pipe(
                        C.fromEvent('InsertLeave', 'asyncomplete__insertleave'),
                        C.map(function() print('insert leave') end)
                    )
                ),
                C.filter(function () return M.is_enabled_for_buffer() end),
                C.map(function () print('textchanged') end)
            )
        end),
        C.subscribe({ error = function () M.disable() end })
    )
end

function M.disable()
    if disable then
        disable()
        disable = nil
    end
end

function M.is_enabled()
    return M.has_lua() and M.vimeval('g:asyncomplete_use_lua') == 1 and M.vimeval('g:asyncomplete_enable') == 1
end

function M.is_enabled_for_buffer(bufnr)
    if not bufnr then bufnr = vim.fn.bufnr('%') end
    return M.has_lua() and M.vimeval('getbufvar(' .. bufnr ..', "asyncomplete_enable")')
end

function M.register(options)
    if sources[options['name']] then
        error('asyncomplete source with name = "' .. options['name'] .. '" already exists.')
    else
        sources[options['name']] = options
    end
    -- TODO refresh active sources
end

function M.unregister(name)
    -- TODO
end

function M.get_active_sources_for_buffer(bufnr)
    if not bufnr then bufnr = vim.fn.bufnr('%') end
    local result = vim.fn.getbufvar(bufnr, 'asyncomplete_active_sources')
    if type(result) == 'string' and result ~= '' then
        return result
    end

    result = vimlist_new()

    local filetype = vim.fn.getbufvar(bufnr, '&filetype')

    for k, v in pairs(sources) do
        local blocked = false
        local blocklist = v['blocklist']
        if blocklist then
            for _,v in pairs(blocklist) do
                if v == filetype or v == '*' then
                    blocked = true
                    break
                end
            end
        end

        if not blocked then
            local allowlist = v['allowlist']
            if allowlist then
                for _,v in pairs(allowlist) do
                    if v == filetype or v == '*' then
                        vimlist_insert(result, k)
                        break
                    end
                end
            end
        end
    end

    vim.fn.setbufvar(bufnr, 'asyncomplete_active_sources', result)

    return result
end

local function clear_active_sources_for_buffer(bufnr)
    if not bufnr then bufnr = vim.fn.bufnr('%') end
    vim.fn.setbufvar(bufnr, 'asyncomplete_active_sources', '')
end

return M
