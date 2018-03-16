if !has('timers')
    echohl ErrorMsg
    echomsg 'Vim/Neovim compiled with timers required for asyncomplete.vim.'
    echohl NONE
    if has('nvim')
        call asyncomplete#log('neovim compiled with timers required.')
    else
        call asyncomplete#log('vim compiled with timers required.')
    endif
    finish
endif

let s:sources = {}
let s:change_timer = -1
let s:last_tick = []
let s:has_popped_up = 0
let s:complete_timer_ctx = {}
let s:already_setup = 0

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
            autocmd InsertEnter <buffer> call s:remote_insert_enter()
            autocmd InsertLeave <buffer> call s:remote_insert_leave()
            autocmd TextChangedI <buffer> call s:on_changed()
            autocmd TextChangedP <buffer> call s:on_changed()
        augroup END
    else
        augroup ayncomplete
            autocmd! * <buffer>
            autocmd InsertEnter <buffer> call s:remote_insert_enter()
            autocmd InsertLeave <buffer> call s:remote_insert_leave()
            autocmd InsertEnter <buffer> call s:change_tick_start()
            autocmd InsertLeave <buffer> call s:change_tick_stop()
            " working together with timer, the timer is for detecting changes
            " popup menu is visible. TextChangedI will not be triggered when popup
            " menu is visible, but TextChangedI is more efficient and faster than
            " timer when popup menu is not visible.
            autocmd TextChangedI <buffer> call s:check_changes()
        augroup END
    endif
endfunction

function! asyncomplete#register_source(info) abort
    if has_key(s:sources, a:info['name'])
        return
    endif

    if has_key(a:info, 'events') && has_key(a:info, 'on_event')
        execute 'augroup asyncomplete_source_event_' . a:info['name']
        for l:event in a:info['events']
            let l:exec =  'if get(b:,"asyncomplete_enable",0) | call s:python_cm_event("' . a:info['name'] . '", "'.l:event.'",asyncomplete#context()) | endif'
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

function! asyncomplete#complete(name, ctx, startcol, matches, ...) abort
    let l:refresh = a:0 > 0 ? a:1 : 0

    " ignore the request if context has changed
    if asyncomplete#context_changed(a:ctx)
        if g:asyncomplete_force_refresh_on_context_changed
            call s:python_cm_complete(a:name, a:ctx, a:startcol, a:matches, l:refresh, 1)
        endif
        return 1
    endif

    call s:python_cm_complete(a:name, a:ctx, a:startcol, a:matches, l:refresh, 0)
endfunction

function! asyncomplete#force_refresh() abort
    return asyncomplete#menu_selected() ? "\<c-y>\<c-r>=asyncomplete#_force_refresh()\<CR>" : "\<c-r>=asyncomplete#_force_refresh()\<CR>"
endfunction

function! asyncomplete#_force_refresh() abort
    if get(b:, 'asyncomplete_enable')
        call s:python_cm_refresh(asyncomplete#context(), 1)
    endif
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

function! s:remote_insert_enter() abort
    call asyncomplete#log('core', 'remote_insert_enter')
    let s:matches = {}
endfunction

function! s:remote_insert_leave() abort
    call asyncomplete#log('core', 'remote_insert_leave')
    let s:matches = {}
endfunction

function! s:change_tick_start() abort
    if s:change_timer != -1
        return
    endif
    let s:last_tick = s:change_tick()
    " changes every 30ms, which is 0.03s, it should be fast enough
    let s:change_timer = timer_start(30, function('s:check_changes'), { 'repeat': -1 })
    call s:on_changed()
endfunction

function! s:change_tick_stop() abort
    if s:change_timer == -1
        return
    endif
    call timer_stop(s:change_timer)
    let s:last_tick = []
    let s:change_timer = -1
endfunction

function! s:on_changed() abort
    if !get(b:, 'asyncomplete_enable') || mode() isnot# 'i' || &paste
        return
    endif

    if exists('s:complete_timer')
        call timer_stop(s:complete_timer)
        unlet s:complete_timer
    endif

    let l:ctx = asyncomplete#context()

    call s:python_cm_refresh(l:ctx, 0)
endfunction

function! s:check_changes(...) abort
    let l:tick = s:change_tick()
    if l:tick != s:last_tick
        let s:last_tick = l:tick
        call s:on_changed()
    endif
endfunction

function! s:change_tick() abort
    return [b:changedtick, getcurpos()]
endfunction

function! s:python_cm_complete(name, ctx, startcol, matches, refresh, outdated) abort
    call asyncomplete#log('core', 's:python_cm_complete', a:name, a:ctx, a:startcol, a:refresh, a:outdated)
    if a:outdated
        call s:notify_sources_to_refresh([a:name], asyncomplete#context())
        return
    endif

    if !has_key(s:matches, a:name)
        let s:matches[a:name] = {}
    endif
    if empty(a:matches)
        unlet s:matches[a:name]
    else
        let s:matches[a:name]['startcol'] = a:startcol
        let s:matches[a:name]['matches'] = a:matches
        let s:matches[a:name]['refresh'] = a:refresh
    endif

    if s:has_popped_up
        call s:python_refresh_completions(asyncomplete#context())
    endif
endfunction

function! s:python_cm_complete_timeout(srcs, ctx) abort
    if !s:has_popped_up
        call s:python_refresh_completions(a:ctx)
        let s:has_popped_up = 1
    endif
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

function! s:python_cm_refresh(ctx, force) abort
    let l:has_popped_up = 0
    if a:force
        call s:notify_sources_to_refresh(s:get_active_sources_for_buffer(), a:ctx)
        return
    endif

    if !pumvisible() && !g:asyncomplete_auto_popup
        return
    endif

    let l:typed = a:ctx['typed']
    let l:sources_to_notify = []

    for l:name in s:get_active_sources_for_buffer()
        let l:source = s:sources[l:name]
        if has_key(l:source, 'refresh_pattern')
            let l:refresh_pattern = l:source['refresh_pattern']
        else
            let l:refresh_pattern = '\k\+$'
        endif
        let l:matchpos = s:matchstrpos(l:typed, l:refresh_pattern)
        let l:startpos = l:matchpos[1]
        let l:endpos = l:matchpos[2]

        call asyncomplete#log('core', 's:python_cm_refresh', l:matchpos, a:ctx)

        let l:typed_len = l:endpos - l:startpos
        if l:typed_len == 1
            call add(l:sources_to_notify, l:name)
        elseif has_key(s:matches, l:name) && s:matches[l:name]['refresh']
            call add(l:sources_to_notify, l:name)
        endif
    endfor

    call s:notify_sources_to_refresh(l:sources_to_notify, a:ctx)
endfunction

function! s:notify_sources_to_refresh(sources, ctx) abort
    if exists('s:complete_timer')
        call timer_stop(s:complete_timer)
        unlet s:complete_timer
    endif

    let s:complete_timer = timer_start(g:asyncomplete_completion_delay, function('s:complete_timeout'))
    let s:complete_timer_ctx = a:ctx

    for l:name in a:sources
        try
            call asyncomplete#log('core', 'completor()', l:name, a:ctx)
            call s:sources[l:name].completor(s:sources[l:name], a:ctx)
        catch
            call asyncomplete#log('core', 'notify_sources_to_refresh', 'error', v:exception)
            continue
        endtry
    endfor
endfunction

function! s:sort_sources_by_priority(source1, source2) abort
    let l:priority1 = get(get(s:sources, a:source1, {}), 'priority', 0)
    let l:priority2 = get(get(s:sources, a:source2, {}), 'priority', 0)
    return l:priority1 > l:priority2 ? -1 : (l:priority1 != l:priority2)
endfunction

function! s:python_refresh_completions(ctx) abort
    let l:matches = []

    let l:names = keys(s:matches)

    if empty(l:names)
        call s:python_complete(a:ctx, a:ctx['col'], [])
        return
    endif

    let l:startcols = []
    for l:item in values(s:matches)
        let l:startcols += [l:item['startcol']]
    endfor

    let l:startcol = min(l:startcols)
    let l:base = a:ctx['typed'][l:startcol-1:]

    let l:filtered_matches = []

    let l:sources = sort(keys(s:matches), function('s:sort_sources_by_priority'))

    if g:asyncomplete_remove_duplicates
        let l:sources = filter(copy(l:sources), 'index(l:sources, v:val, v:key+1) == -1')
    endif

    for l:name in l:sources
        let l:info = s:matches[l:name]
        let l:curstartcol = l:info['startcol']
        let l:curmatches = l:info['matches']

        if l:curstartcol > a:ctx['col']
            " wrong start col
            continue
        endif

        let l:prefix = a:ctx['typed'][l:startcol-1 : col('.') -1]

        let l:normalizedcurmatches = []
        for l:item in l:curmatches
            let l:e = {}
            if type(l:item) == type('')
                let l:e['word'] = l:item
            else
                let l:e = copy(l:item)
                let l:e['word'] = l:e['word']
            endif
            let l:normalizedcurmatches += [l:e]
        endfor

        let l:filtered_matches += s:filter_completion_items(l:prefix, l:normalizedcurmatches)
    endfor

    call s:core_complete(a:ctx, l:startcol, l:filtered_matches, s:matches)
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

function! s:python_complete(ctx, startcol, matches) abort
    if empty(a:matches)
        " no need to fire complete message
        return
    endif
    call s:core_complete(a:ctx, a:startcol, a:matches, s:matches)
endfunction

function! s:python_cm_event(name, event, ctx) abort
    try
        call s:sources[a:name].on_event(s:sources[a:name], a:ctx, a:event)
    catch
        return
    endtry
endfunction

function! s:core_complete(ctx, startcol, matches, allmatches) abort
    if !get(b:, 'asyncomplete_enable', 0)
        return 2
    endif

    " ignore the request if context has changed
    if (a:ctx != asyncomplete#context()) || (mode() isnot# 'i')
        return 1
    endif

    " something selected by user, do not refresh the menu
    if asyncomplete#menu_selected()
        return 0
    endif

    setlocal completeopt-=longest
    setlocal completeopt+=menuone
    setlocal completeopt-=menu
    if &completeopt !~# 'noinsert\|noselect'
        setlocal completeopt+=noselect
    endif

    call complete(a:startcol, a:matches)
endfunction

function! s:complete_timeout(timer) abort
    " finished, clean variable
    unlet! s:complete_timer
    if s:complete_timer_ctx != asyncomplete#context()
        return
    endif
    call s:python_cm_complete_timeout(s:sources, s:complete_timer_ctx)
endfunction

function! asyncomplete#menu_selected() abort
    " when the popup menu is visible, v:completed_item will be the
    " current_selected item
    " if v:completed_item is empty, no item is selected
    return pumvisible() && !empty(v:completed_item)
endfunction
