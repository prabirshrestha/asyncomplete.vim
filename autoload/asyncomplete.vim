function! asyncomplete#log(...) abort
    if !empty(g:asyncomplete_log_file)
        call writefile([json_encode(a:000)], g:asyncomplete_log_file, 'a')
    endif
endfunction

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

let s:already_setup = 0
let s:sources = {}
let s:matches = {} " { server_name: { incomplete: 1, startcol: 0, items: [], refresh: 0, status: 'idle|pending|success|failure', ctx: ctx } }

function! s:setup_if_required() abort
    if !s:already_setup
        " register asyncomplete manager
        call asyncomplete#log('core', 'initializing asyncomplete manager', g:asyncomplete_manager)
        execute 'let s:manager = function("'. g:asyncomplete_manager  .'")()'
        call asyncomplete#log('core', 'initializing asyncomplete manager complete', s:manager['name'])

        " register asyncomplete change manager
        for l:change_manager in g:asyncomplete_change_manager
            call asyncomplete#log('core', 'initializing asyncomplete change manager', l:change_manager)
            if type(l:change_manager) == type('')
                execute 'let s:on_change_manager = function("'. l:change_manager  .'")()'
            else
                let s:on_change_manager = l:change_manager()
            endif
            if has_key(s:on_change_manager, 'error')
                call asyncomplete#log('core', 'initializing asyncomplete change manager failed', s:on_change_manager['name'], s:on_change_manager['error'])
            else
                call s:on_change_manager.register(function('s:on_change'))
                call asyncomplete#log('core', 'initializing asyncomplete change manager complete', s:on_change_manager['name'])
                break
            endif
        endfor

        augroup asyncomplete
            autocmd!
            autocmd InsertEnter * call s:on_insert_enter()
            autocmd InsertLeave * call s:on_insert_leave()
        augroup END

        doautocmd User asyncomplete_setup
        let s:already_setup = 1
    endif
endfunction

function! asyncomplete#enable_for_buffer() abort
    call s:setup_if_required()
    let b:asyncomplete_enable = 1
endfunction

function! asyncomplete#disable_for_buffer() abort
    let b:asyncomplete_enable = 0
endfunction

function! asyncomplete#register_source(info) abort
    if has_key(s:sources, a:info['name'])
        call asyncomplete#log('core', 'duplicate asyncomplete#register_source', a:info['name'])
        return -1
    else
        let s:sources[a:info['name']] = a:info
        if has_key(a:info, 'events') && has_key(a:info, 'on_event')
            execute 'augroup asyncomplete_source_event_' . a:info['name']
            for l:event in a:info['events']
                let l:exec =  'if get(b:,"asyncomplete_enable",0) | call s:notify_event_to_source("' . a:info['name'] . '", "'.l:event.'",asyncomplete#context()) | endif'
                if type(l:event) == type('')
                    execute 'au ' . l:event . ' * ' . l:exec
                elseif type(l:event) == type([])
                    execute 'au ' . join(l:event,' ') .' ' .  l:exec
                endif
            endfor
            execute 'augroup end'
        endif
        return 1
    endif
endfunction

function! asyncomplete#unregister_source(info_or_server_name) abort
    if type(a:info) == type({})
        let l:server_name = a:info['name']
    else
        let l:server_name = a:info
    endif
    if has_key(s:sources, l:server_name)
        let l:server = s:sources[l:servier_name]
        if has_key(l:server, 'unregister')
            call l:server.unregister()
        endif
        unlet s:sources[l:server_name]
        return 1
    else
        return -1
    endif
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

function! s:on_insert_enter() abort
    call s:get_active_sources_for_buffer() " call to cache
    call s:update_trigger_characters()
endfunction

function! s:on_insert_leave() abort
    let s:matches = {}
endfunction

function! s:get_active_sources_for_buffer() abort
    if exists('b:asyncomplete_active_sources')
        " active sources were cached for buffer
        return b:asyncomplete_active_sources
    endif

    call asyncomplete#log('core', 'computing active sources for buffer', bufnr('%'))
    let b:asyncomplete_active_sources = []
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
                    let b:asyncomplete_active_sources += [l:name]
                    break
                endif
            endfor
        endif
    endfor

    call asyncomplete#log('core', 'active source for buffer', bufnr('%'), b:asyncomplete_active_sources)

    return b:asyncomplete_active_sources
endfunction

function! s:update_trigger_characters() abort
    if exists('b:asyncomplete_triggers')
        " triggers were cached for buffer
        return b:asyncomplete_triggers
    endif
    let b:asyncomplete_triggers = {} " { char: { 'sourcea': 1, 'sourceb': 2 } }

    for l:source_name in s:get_active_sources_for_buffer()
        let l:source_info = s:sources[l:source_name]
        if has_key(l:source_info, 'triggers') && has_key(l:source_info['triggers'], &filetype)
            let l:triggers = l:source_info['triggers'][&filetype]
        elseif has_key(l:source_info, 'triggers') && has_key(l:source_info['triggers'], '*')
            let l:triggers = l:source_info['triggers']['*']
        elseif has_key(g:asyncomplete_triggers, &filetype)
            let l:triggers = g:asyncomplete_triggers[&filetype]
        elseif has_key(g:asyncomplete_triggers, '*')
            let l:triggers = g:asyncomplete_triggers['*']
        else
            let l:triggers = []
        endif

        for l:trigger in l:triggers
            let l:last_char = l:trigger[len(l:trigger) -1]
            if !has_key(b:asyncomplete_triggers, l:last_char)
                let b:asyncomplete_triggers[l:last_char] = {}
            endif
            if !has_key(b:asyncomplete_triggers[l:last_char], l:source_name)
                let b:asyncomplete_triggers[l:last_char][l:source_name] = []
            endif
            call add(b:asyncomplete_triggers[l:last_char][l:source_name], l:trigger)
        endfor
    endfor
    call asyncomplete#log('core', 'trigger characters for buffer', bufnr('%'), b:asyncomplete_triggers)
endfunction

function! s:should_skip() abort
    if mode() isnot# 'i' || !b:asyncomplete_enable
        return 1
    else
        return 0
    endif
endfunction

function! s:on_change() abort
    if s:should_skip() | return | endif

    if !g:asyncomplete_auto_popup
        return
    endif

    let l:ctx = asyncomplete#context()
    let l:startcol = l:ctx['col']
    let l:last_char = l:ctx['typed'][l:startcol - 2]

    let l:sources_to_notify = {}
    if has_key(b:asyncomplete_triggers, l:last_char)
        " TODO: also check for multiple chars instead of just last chars for
        " languages such as cpp which uses -> and ::
        for l:source_name in keys(b:asyncomplete_triggers[l:last_char])
            if !has_key(s:matches, l:source_name) || s:matches[l:source_name]['startcol'] != l:startcol " todo: different line check
                let l:sources_to_notify[l:source_name] = 1
                let s:matches[l:source_name] = { 'startcol': l:startcol, 'status': 'idle', 'items': [], 'refresh': 0, 'ctx': l:ctx }
            endif
        endfor
    endif

    " loop left and find the start of the word and set it as the startcol for the source instead of refresh_pattern
    let l:refresh_pattern = '\(\k\+$\|\.$\|>$\|:$\)'
    let [l:_, l:startpos, l:endpos] = asyncomplete#utils#matchstrpos(l:ctx['typed'], l:refresh_pattern)
    let l:startcol = l:startpos

    if l:startpos > -1
        for l:source_name in b:asyncomplete_active_sources
            if !has_key(l:sources_to_notify, l:source_name)
                if has_key(s:matches, l:source_name) && s:matches[l:source_name]['startcol'] ==# l:startcol " todo different line check
                    continue
                endif
                let l:sources_to_notify[l:source_name] = 1
                let s:matches[l:source_name] = { 'startcol': l:startcol, 'status': 'idle', 'items': [], 'refresh': 0, 'ctx': l:ctx }
            endif
        endfor
    endif

    call s:trigger(l:ctx)
    call s:update_pum()
endfunction

function! s:trigger(ctx) abort
    " send cancellation request if supported
    for [l:source_name, l:matches] in items(s:matches)
        call asyncomplete#log('core', 's:trigger', l:matches)
        if l:matches['refresh'] || l:matches['status'] == 'idle' || l:matches['status'] == 'failure'
            let l:matches['status'] = 'pending'
            try
                " TODO: check for min chars
                call asyncomplete#log('core', 's:trigger.completor()', l:source_name, s:matches[l:source_name], a:ctx)
                call s:sources[l:source_name].completor(s:sources[l:source_name], a:ctx)
            catch
                let l:matches['status'] = 'failure'
                call asyncomplete#log('core', 's:trigger', 'error', v:exception)
                continue
            endtry
        endif
    endfor
endfunction

function! asyncomplete#complete(name, ctx, startcol, items, ...) abort
    let l:refresh = a:0 > 0 ? a:1 : 0
    call asyncomplete#log('asyncomplete#complete', a:name, a:ctx, a:startcol, l:refresh, a:items)
    let l:ctx = asyncomplete#context()
    if !has_key(s:matches, a:name) || l:ctx['lnum'] != a:ctx['lnum'] " TODO: handle more context changes
        call asyncomplete#log('context changed ... ignoring')
        call s:update_pum()
        return
    endif

    let l:matches = s:matches[a:name]
    let l:matches['items'] = s:normalize_items(a:items)
    let l:matches['refresh'] = l:refresh
    let l:matches['startcol'] = a:startcol - 1
    let l:matches['status'] = 'success'

    call s:update_pum()
endfunction

function! s:normalize_items(items) abort
    if len(a:items) > 0 && type(a:items[0]) ==# type('')
        let l:items = []
        for l:item in a:items
            let l:items += [{'word': l:item }]
        endfor
        return l:items
    else
        return a:items
    endif
endfunction

function! asyncomplete#force_refresh() abort
    return asyncomplete#menu_selected() ? "\<c-y>\<c-r>=asyncomplete#_force_refresh()\<CR>" : "\<c-r>=asyncomplete#_force_refresh()\<CR>"
endfunction

function! asyncomplete#_force_refresh() abort
    if s:should_skip() | return | endif

    let l:ctx = asyncomplete#context()
    let l:startcol = l:ctx['col']
    let l:last_char = l:ctx['typed'][l:startcol - 2]

    " loop left and find the start of the word or trigger chars and set it as the startcol for the source instead of refresh_pattern
    let l:refresh_pattern = '\(\k\+$\|\.$\|>$\|:$\)'
    let [l:_, l:startpos, l:endpos] = asyncomplete#utils#matchstrpos(l:ctx['typed'], l:refresh_pattern)
    let l:startcol = l:startpos

    let s:matches = {}

    for l:source_name in b:asyncomplete_active_sources
        let s:matches[l:source_name] = { 'startcol': l:startcol, 'status': 'idle', 'items': [], 'refresh': 0, 'ctx': l:ctx }
    endfor

    call s:trigger(l:ctx)
    call s:update_pum()
    return ''
endfunction

function! s:update_pum() abort
    if exists('s:update_pum_timer')
        call timer_stop(s:update_pum_timer)
        unlet s:update_pum_timer
    endif
    call asyncomplete#log('s:update_pum')
    let s:update_pum_timer = timer_start(20, function('s:recompute_pum'))
endfunction

function! s:recompute_pum(...) abort
    if s:should_skip() | return | endif

    " TODO: add support for remote recomputation of complete items,
    " Ex: heavy computation such as fuzzy search can happen in a python thread

    call asyncomplete#log('s:recompute_pum')

    if asyncomplete#menu_selected()
        call asyncomplete#log('s:recomputed_pum', 'ignorning refresh pum due to menu selection')
        return
    endif

    let l:startcols = []
    for l:match in values(s:matches)
        let l:startcols += [l:match['startcol']]
    endfor

    let l:ctx = asyncomplete#context()

    let l:startcol = min(l:startcols)
    let l:base = l:ctx['typed'][l:startcol:]

    let l:matches_to_filter = {}
    for [l:source_name, l:match] in items(s:matches)
        let l:curstartcol = l:match['startcol']
        let l:curitems = l:match['items']

        if l:curstartcol > l:ctx['col']
            call asyncomplete#log('s:recompute_pum', 'ignoring due to wrong start col', l:curstartcol, l:ctx['col'])
            continue
        else
            let l:matches_to_filter[l:source_name] = l:match
        endif
    endfor

    " TODO: allow users to pass custom filter function. lock the api before making this public.
    " Everything in this function should be treated as immutable. filter function shouldn't mutate.
    call s:default_filter({ 'ctx': l:ctx, 'base': l:base, 'startcol': l:startcol, 'matches': l:matches_to_filter })
endfunction

function! s:default_filter(options) abort
    let l:items = []
    for [l:source_name, l:matches] in items(a:options['matches'])
        for l:item in l:matches['items']
            if l:item['word'] =~ '^' . a:options['base']
                call add(l:items, l:item)
            endif
        endfor
    endfor

    call s:set_pum(a:options['startcol'], l:items)
endfunction

function! s:set_pum(startcol, items) abort
    " TODO: handle cases where this is called asynchronsouly
    if s:should_skip() | return | endif

    call asyncomplete#log('s:set_pum')

    if asyncomplete#menu_selected()
        call asyncomplete#log('s:set_pum', 'ignorning set pum due to menu selection')
        return
    endif

    if (g:asyncomplete_auto_completeopt == 1)
        setl completeopt=menuone,noinsert,noselect
    endif

    call asyncomplete#log(a:startcol + 1, a:items)
    call complete(a:startcol + 1, a:items)
endfunction

function! asyncomplete#menu_selected() abort
    " when the popup menu is visible, v:completed_item will be the
    " current_selected item
    " if v:completed_item is empty, no item is selected
    return pumvisible() && !empty(v:completed_item)
endfunction

function! s:notify_event_to_source(name, event, ctx) abort
    try
        if has_key(s:sources, a:name)
            call s:sources[a:name].on_event(s:sources[a:name], a:ctx, a:event)
        endif
    catch
        call asyncomplete#log('core', 's:notify_event_to_source', 'error', v:exception)
        return
    endtry
endfunction
