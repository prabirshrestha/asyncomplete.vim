local module = {}
local fts = dofile(asyncomplete_folder .. '/lua/fts_fuzzy_match.lua')

local is_neovim = vim['api'] ~= nil and vim.api['nvim_eval'] ~= nil

if is_neovim then
    function to_vim_list(obj)
        return obj
    end
    function dump(o)
        if type(o) == 'table' then
            return vim.api.nvim_call_function('string', o)
        else
            return tostring(o)
        end
    end
else
    function dump(o)
       if type(o) == 'table' then
          local s = '{ '
          for k,v in pairs(o) do
             if type(k) ~= 'number' then k = '"'..k..'"' end
             s = s .. '['..k..'] = ' .. asyncomplete.dump(v) .. ','
          end
          return s .. '} '
       else
          return tostring(o)
       end
    end

    function to_vim_list(obj)
        return vim.list(obj)
    end
end

function module.filter_completion_items(prefix, matches)
    local result = {}
    local result = {}
    local index = 0
    local unsorted_matches = {}
    for i = 0, #matches - 1 do
        local match = matches[i]
        if match ~= nil then
            local word = match['word']
            local matched, score, matchedIndices = fts.fuzzy_match(prefix, word)
            if matched == true then
                table.insert(unsorted_matches, { score = score, match = match })
            end
        end
    end
    for k,v in spairs(unsorted_matches, function(t,a,b) return t[b].score < t[a].score end) do
        table.insert(result, v.match)
    end

    return to_vim_list(result)
end

function spairs(t, order)
    -- collect the keys
    local keys = {}
    for k in pairs(t) do keys[#keys+1] = k end

    -- if order function given, sort by it by passing the table and keys a, b,
    -- otherwise just sort the keys
    if order then
        table.sort(keys, function(a,b) return order(t, a, b) end)
    else
        table.sort(keys)
    end

    -- return the iterator function
    local i = 0
    return function()
        i = i + 1
        if keys[i] then
            return keys[i], t[keys[i]]
        end
    end
end

asyncomplete = module
