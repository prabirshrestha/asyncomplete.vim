let s:sources = {}
let s:change_timer = -1
let s:last_tick = ''
let s:last_matches = []

function! asyncomplete#enable_for_buffer() abort
    let b:asyncomplete_enable = 1
    augroup ayncomplete
        autocmd! * <buffer>
        autocmd InsertEnter <buffer> call s:python_cm_insert_enter()
        autocmd InsertEnter <buffer> call s:python_cm_insert_leave()
        autocmd InsertEnter <buffer> call s:change_tick_start()
        autocmd InsertLeave <buffer> call s:change_tick_stop()
    augroup END
endfunction

function! asyncomplete#register_source(info) abort
    if has_key(s:sources, a:info['name'])
        return
    endif

    if has_key(a:info, 'events') && has_key(a:info, 'on_event')
        execute 'augroup asyncomplete_source_event_' . a:info['name']
        for l:event in a:info['events']
            let l:exec =  'if get(b:,"asyncomplete_enable",0) | call s:python_cm_event("' . a:info['name'] . '", "'.l:event.'",asyncomplete#context()) | endif'
            if type(l:event) == v:t_string
                execute 'au ' . l:event . ' * ' . l:exec
            elseif type(l:event) == v:t_list
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

function! asyncomplete#complete(src, ctx, startcol, matches) abort
    let l:name = a:src

    if get(b:, 'asyncomplete_enable', 0) == 0
        return 2
    endif

    " ignore the request if context has changed
    if  (a:ctx != asyncomplete#context()) || (mode() != 'i')
        return 1
    endif

    if !has_key(s:sources, l:name)
        return 3
    endif

    call s:python_cm_complete(s:sources, l:name, a:ctx, a:startcol, a:matches)
endfunction

function! asyncomplete#context() abort
    let l:ret = {'bufnr':bufnr('%'), 'filetype': &filetype, 'curpos':getcurpos(), 'changedtick':b:changedtick}
    let l:ret['lnum'] = l:ret['curpos'][1]
    let l:ret['col'] = l:ret['curpos'][2]
    let l:ret['typed'] = strpart(getline(l:ret['lnum']),0,l:ret['col']-1)
    return l:ret
endfunction

function! s:python_cm_insert_enter() abort
    let s:matches = {}
endfunction

function! s:python_cm_insert_leave() abort
endfunction

function! s:change_tick_start() abort
    if s:change_timer != -1
        return
    endif
    let s:last_tick = s:change_tick()
    let s:change_timer = timer_start(g:asyncomplete_completion_delay, function('s:check_changes'), { 'repeat': -1 })
    call s:on_changed()
endfunction

function! s:change_tick_stop() abort
    if s:change_timer == -1
        return
    endif
    call timer_stop(s:change_timer)
    let s:last_tick = ''
    let s:change_timer = -1
endfunction

function! s:on_changed() abort
    if get(b:, 'asyncomplete_enable', 0) == 0
        return
    endif

    let l:ctx = asyncomplete#context()

    call s:python_cm_refresh(s:sources, l:ctx)
endfunction

function! s:check_changes(timer) abort
    let l:tick = s:change_tick()
    if l:tick != s:last_tick
        let s:last_tick = l:tick
        if mode()=='i' && (&paste==0)
            " only in insert non paste mode
            call s:on_changed()
        endif
    endif
endfunction

function! s:change_tick() abort
    return [b:changedtick, getcurpos()]
endfunction

function! s:python_cm_complete(srcs, name, ctx, startcol, matches) abort
    let s:sources = a:srcs

    if !has_key(s:matches, a:name)
        let s:matches[a:name] = {}
    endif
    if empty(a:matches)
        unlet s:matches[a:name]
    else
        let s:matches[a:name]['startcol'] = a:startcol
        let s:matches[a:name]['matches'] = a:matches
    endif

    call s:python_refresh_completions(a:ctx)
endfunction

function! s:python_cm_refresh(srcs, ctx) abort
    let s:sources = a:srcs
    let l:typed = a:ctx['typed']

    " simple complete done
    if empty(l:typed)
        let s:matches = {}
    elseif !empty(matchstr(l:typed[len(l:typed)-1:], '[^0-9a-zA-Z_]'))
        let s:matches = {}
    endif

    " do notify sources to refresh
    let l:refreshes_calls = []
    for [l:name, l:info] in items(a:srcs)
        let l:refresh = 0
        if has_key(l:info, 'whitelist')
            for l:filetype in l:info['whitelist']
                if l:filetype == &filetype || l:filetype == '*'
                    let l:refresh = 1
                    break
                endif
            endfor
        else
            let l:refresh = 1
        endif

        if l:refresh == 1
            let l:refreshes_calls += [l:name]
        endif
    endfor

    call s:notify_sources_to_refresh(l:refreshes_calls, a:ctx)
    call s:python_refresh_completions(a:ctx)
endfunction

function! s:notify_sources_to_refresh(calls, ctx) abort
    for l:name in a:calls
        try
            call s:sources[l:name].completor(s:sources[l:name], a:ctx)
        catch
            continue
        endtry
    endfor
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

    let l:tmpmatches = []
    for [l:name, l:info] in items(s:matches)
        let l:curstartcol = s:matches[l:name]['startcol']
        let l:curmatches = s:matches[l:name]['matches']

        if l:curstartcol > a:ctx['col']
            " wrong start col
            continue
        endif

        let l:prefix = a:ctx['typed'][l:startcol-1 : col('.') -1]

        let l:normalizedcurmatches = []
        for l:item in l:curmatches
            let l:e = {}
            if type(l:item) == v:t_string
                let l:e['word'] = l:item
            else
                let l:e = copy(l:item)
                let l:e['word'] = l:e['word']
            endif
            let l:normalizedcurmatches += [l:e]
        endfor

        let l:curmatches = l:normalizedcurmatches

        for l:item in l:curmatches
            if l:item['word'] =~ '^' . l:prefix
                let l:tmpmatches += [l:item]
            endif
        endfor
    endfor

    call s:core_complete(a:ctx, l:startcol, l:tmpmatches, s:matches)
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

    if get(b:, 'asyncomplete_enable', 0) == 0
        return 2
    endif

    " ignore the request if context has changed
    if (a:ctx != asyncomplete#context()) || (mode() != 'i')
        return 1
    endif

    " something selected y the user, do not refresh the menu
    if s:menu_selected()
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

function! s:menu_selected()
    " when the popup menu is visible, v:completed_item will be the
    " current_selected item
    " if v:completed_item is empty, no item is selected
    return pumvisible() && !empty(v:completed_item)
endfunction
