if !has('timers')
    echohl ErrorMsg
    echomsg 'Vim/Neovim compiled with timers required for asyncomplete.vim.'
    echohl NONE
    call asyncomplete#log('vim/neovim compiled with timers required.')
    finish
endif

if !exists('##TextChangedP')
    echohl ErrorMsg
    echomsg 'Vim/Neovim compiled with TextChangedP (vim-patch:8.0.1494) required for asyncomplete.vim.'
    echohl NONE
    call asyncomplete#log('vim/neovim compiled with TextChangedP (vim-patch:8.0.1494) required.')
    finish
endif

let s:sources = {}
let s:matches = {}
let s:already_setup = 0
let s:startcol = -1
let s:candidates = []
let s:script_path = expand('<sfile>:p:h')
let s:supports_smart_completion = has('lua') && exists('##TextChangedP')

function! asyncomplete#log(...) abort
    if !empty(g:asyncomplete_log_file)
        call writefile([json_encode(a:000)], g:asyncomplete_log_file, 'a')
    endif
endfunction

" do nothing, place it here only to avoid the message
augroup asyncomplete_silence_messages
    au!
    autocmd User asyncomplete_setup silent
augroup END

function! asyncomplete#enable_for_buffer() abort
    if !s:already_setup
        doautocmd User asyncomplete_setup
        let s:already_setup = 1
    endif

    let b:asyncomplete_enable = 1
    if exists('##TextChangedP')
        augroup ayncomplete
            autocmd! * <buffer>
            autocmd InsertEnter <buffer> call s:on_insert_enter()
            autocmd InsertLeave <buffer> call s:on_insert_leave()
            autocmd TextChangedI <buffer> call s:on_text_changed()
            autocmd TextChangedP <buffer> call s:on_text_changed()
        augroup END
    endif
endfunction

function! s:on_insert_enter() abort
    call s:reset()
endfunction

function! s:on_insert_leave() abort
    call s:reset()
endfunction

function! s:reset() abort
    let s:matches = {}
    let s:startcol = -1
    let s:candidates = []
endfunction

function! s:on_text_changed() abort
    let l:ctx = asyncomplete#context()
    call s:notify_sources_to_refresh(l:ctx, 0)
    if s:supports_smart_completion() && pumvisible() && !empty(s:candidates)
        " TODO: delay s:update_pum() since it is expensive due to filtering candidates
        call s:update_pum(l:ctx, s:startcol, s:candidates)
    endif
endfunction

function! asyncomplete#register_source(info) abort
    if has_key(s:sources, a:info['name'])
        return
    endif

    if has_key(a:info, 'events') && has_key(a:info, 'on_event')
        execute 'augroup asyncomplete_source_event_' . a:info['name']
        for l:event in a:info['events']
            let l:exec =  'if get(b:,"asyncomplete_enable",0) | call s:notify_source_event("' . a:info['name'] . '", "'.l:event.'",asyncomplete#context()) | endif'
            if type(l:event) == type('')
                execute 'au ' . l:event . ' * ' . l:exec
            elseif type(l:event) == type([])
                execute 'au ' . join(l:event,' ') .' ' .  l:exec
            endif
        endfor
        execute 'augroup end'
    endif

    let s:sources[a:info['name']] = a:info
endfunction

function! asyncomplete#unregister_source(name) abort
    try
        let l:info = s:sources[a:name]
        unlet l:info
        unlet s:sources[a:name]
    catch
        return
    endtry
endfunction

function! s:is_enabled() abort
    if !get(b:, 'asyncomplete_enable') || mode() isnot# 'i' || &paste
        return 0
    else
        return 1
    endif
endfunction

function! s:notify_sources_to_refresh(ctx, force) abort
    if !s:is_enabled()
        return
    endif

    let l:typed = a:ctx['typed']

    for l:source_name in s:get_active_sources_for_buffer()
        let l:refresh = a:force
        if !a:force
            if has_key(s:matches, l:source_name) && s:matches[l:source_name]['incomplete']
                " force refresh since the results are incomplete
                let l:refresh = 1
            else
                " refresh only if the prefix changed
                let l:source = s:sources[l:source_name]
                if has_key(l:source, 'refresh_pattern')
                    let l:refresh_pattern = l:source['refresh_pattern']
                    if (type(l:refresh_pattern) != type(''))
                        let l:refresh_pattern = l:refresh_pattern()
                    endif
                else
                    let l:refresh_pattern = g:asyncomplete_default_refresh_pattern
                endif

                let l:matchpos = s:matchstrpos(l:typed, l:refresh_pattern)
                let l:startpos = l:matchpos[1]
                let l:endpos = l:matchpos[2]

                let l:typed_len = l:endpos - l:startpos
                let l:min_chars = get(l:source, 'min_chars', g:asyncomplete_min_chars)
                if l:typed_len == l:min_chars || (!pumvisible() && l:typed_len >= l:min_chars)
                    let l:refresh = 1
                endif
            endif
        endif
        if l:refresh
            try
                call asyncomplete#log('core.s:notify_sources_to_refresh()', 'completor', l:source_name, a:ctx)
                call s:sources[l:source_name].completor(s:sources[l:source_name], a:ctx)
            catch
                call asyncomplete#log('core.s:notify_sources_to_refresh()', 'completor', 'error', v:exception)
                continue
            endtry
        endif
    endfor
endfunction

function! asyncomplete#complete(name, ctx, startcol, candidates, ...) abort
    let l:incomplete = a:0 > 0 ? a:1 : 0
    call asyncomplete#log('core#complete', a:name, a:startcol, len(a:candidates), l:incomplete)
    
    " handle context_changed scenarios

    let s:matches[a:name] = {
        \ 'startcol': a:startcol,
        \ 'incomplete': l:incomplete,
        \ 'candidates': a:candidates,
        \ 'ctx': a:ctx,
        \ }

    " call s:compute_candidates() at the end of the event loop to avoid calling expensive compute multiple times
    if exists('s:compute_timer_candidate')
        call timer_stop(s:compute_timer_candidate)
        unlet s:compute_timer_candidate
    endif
    let s:compute_timer_candidate = timer_start(0, function('s:compute_candidates'))
endfunction

function! s:compute_candidates(...) abort
    if !s:is_enabled()
        return
    endif

    call asyncomplete#log('core.s:compute_candidates()')

    " find mimnimal startcol from all matches
    let l:startcols = []
    for l:item in values(s:matches)
        let l:startcols += [l:item['startcol']]
    endfor
    let l:startcol = min(l:startcols)

    let l:ctx = asyncomplete#context()
    let l:base = l:ctx['typed'][l:startcol-1:]

    " sort sources by priority
    let l:sources = sort(keys(s:matches), function('s:sort_sources_by_priority'))

    " remove duplicates if enabled
    if g:asyncomplete_remove_duplicates
        let l:sources = filter(copy(l:sources), 'index(l:sources, v:val, v:key+1) == -1')
    endif

    let l:candidates = []

    " normalize
    for l:name in l:sources
        let l:info = s:matches[l:name]
        let l:curstartcol = l:info['startcol']
        let l:curcandidates = l:info['candidates']

        if l:curstartcol > l:ctx['col']
            " wrong start col
            continue
        endif

        let l:normalizedcurcandidates = []
        for l:item in l:curcandidates
            let l:e = {}
            if type(l:item) == type('')
                let l:e['word'] = l:item
            else
                let l:e = copy(l:item)
                let l:e['word'] = l:e['word']
            endif
            let l:normalizedcurcandidates += [l:e]
        endfor

        let l:candidates += l:normalizedcurcandidates
    endfor

    let s:startcol = l:startcol
    let s:candidates = l:candidates
    call s:update_pum(ctx, l:startcol, l:candidates)
endfunction

function! s:update_pum(ctx, startcol, candidates) abort
    if !s:is_enabled()
        return
    endif

    if asyncomplete#menu_selected()
        return 0
    endif

    setlocal completeopt-=longest
    setlocal completeopt+=menuone
    setlocal completeopt-=menu
    if &completeopt !~# 'noinsert\|noselect'
        setlocal completeopt+=noselect
    endif

    let l:prefix = a:ctx['typed'][a:startcol-1 : col('.') - 1]

    call asyncomplete#log('update pum', a:ctx['typed'], a:startcol, col('.'), l:prefix)

    " filter candidates
    let l:candidates = s:supports_smart_completion() ? s:filter_completion_items_lua(l:prefix, a:candidates) : a:candidates

    call complete(a:startcol, l:candidates)
endfunction

function! s:supports_smart_completion() abort
    return s:supports_smart_completion && g:asyncomplete_smart_completion
endfunction

function! s:filter_completion_items_lua(prefix, matches) abort
    let l:tmpmatches = []
    lua << EOF
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

    local prefix = vim.eval('a:prefix')
    local matches = vim.eval('a:matches')
    local tmpmatches = vim.eval('l:tmpmatches')
    if asyncomplete.fts == nil then
        local fts_fuzzy_match_script_path = vim.eval('s:script_path') .. '/fts_fuzzy_match.lua'
        asyncomplete.fts = dofile(fts_fuzzy_match_script_path)
        vim.eval("asyncomplete#log('fts_fuzzy_match loaded')")
    end
    local index = 0
    local unsorted_matches = {}
    for i = 0, #matches - 1 do
        local word = matches[i].word
        local matched, score, matchedIndices = asyncomplete.fts.fuzzy_match(prefix, word)
        if matched == true then
            table.insert(unsorted_matches, { score = score, match = matches[i] })
        end
        -- local matched = asyncomplete.fts.fuzzy_match_simple(prefix, word)
        -- if matched == true then
        --      tmpmatches:add(matches[i])
        -- end
    end
    for k,v in spairs(unsorted_matches, function(t,a,b) return t[b].score < t[a].score end) do
        tmpmatches:add(v.match)
    end
EOF
    return l:tmpmatches
endfunction

function! asyncomplete#force_refresh() abort
    return asyncomplete#menu_selected() ? "\<c-y>\<c-r>=asyncomplete#_force_refresh()\<CR>" : "\<c-r>=asyncomplete#_force_refresh()\<CR>"
endfunction

function! asyncomplete#_force_refresh() abort
    call s:notify_sources_to_refresh(asyncomplete#context(), 1)
    return ''
endfunction

function! asyncomplete#context() abort
    let l:ret = {'bufnr':bufnr('%'), 'curpos':getcurpos(), 'changedtick':b:changedtick}
    let l:ret['lnum'] = l:ret['curpos'][1]
    let l:ret['col'] = l:ret['curpos'][2]
    let l:ret['filetype'] = &filetype
    let l:ret['filepath'] = expand('%:p')
    let l:ret['typed'] = strpart(getline(l:ret['lnum']),0,l:ret['col']-1)
    return l:ret
endfunction

function! asyncomplete#context_changed(ctx) abort
    " return (b:changedtick!=a:ctx['changedtick']) || (getcurpos()!=a:ctx['curpos'])
    " Note: changedtick is triggered when `<c-x><c-u>` is pressed due to vim's
    " bug, use curpos as workaround
    return getcurpos() != a:ctx['curpos']
endfunction

function! s:get_active_sources_for_buffer() abort
    " TODO: cache active sources per buffer
    let l:active_sources = []
    for [l:name, l:info] in items(s:sources)
        let l:blacklisted = 0

        if has_key(l:info, 'blacklist')
            for l:filetype in l:info['blacklist']
                if l:filetype == &filetype || l:filetype is# '*'
                    let l:blacklisted = 1
                    break
                endif
            endfor
        endif

        if l:blacklisted
            continue
        endif

        if has_key(l:info, 'whitelist')
            for l:filetype in l:info['whitelist']
                if l:filetype == &filetype || l:filetype is# '*'
                    let l:active_sources += [l:name]
                    break
                endif
            endfor
        endif
    endfor

    return l:active_sources
endfunction

if exists('*matchstrpos')
    function! s:matchstrpos(expr, pattern) abort
        return matchstrpos(a:expr, a:pattern)
    endfunction
else
    function! s:matchstrpos(expr, pattern) abort
        return [matchstr(a:expr, a:pattern), match(a:expr, a:pattern), matchend(a:expr, a:pattern)]
    endfunction
endif

function! s:sort_sources_by_priority(source1, source2) abort
    let l:priority1 = get(get(s:sources, a:source1, {}), 'priority', 0)
    let l:priority2 = get(get(s:sources, a:source2, {}), 'priority', 0)
    return l:priority1 > l:priority2 ? -1 : (l:priority1 != l:priority2)
endfunction

function! s:filter_completion_items(prefix, matches) abort
    let l:tmpmatches = []
    for l:item in a:matches
        if l:item['word'] =~ '^' . a:prefix
            let l:tmpmatches += [l:item]
        endif
    endfor
    return l:tmpmatches
endfunction

function! s:notify_source_event(name, event, ctx) abort
    try
        call s:sources[a:name].on_event(s:sources[a:name], a:ctx, a:event)
    catch
        return
    endtry
endfunction

function! asyncomplete#menu_selected() abort
    " when the popup menu is visible, v:completed_item will be the
    " current_selected item
    " if v:completed_item is empty, no item is selected
    return pumvisible() && !empty(v:completed_item)
endfunction
