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
let s:matches = {} " { server_name: { incomplete: 1, startcol: 0, items: []  } }

function! asyncomplete#log(...) abort
    if !empty(g:asyncomplete_log_file)
        call writefile([json_encode(a:000)], g:asyncomplete_log_file, 'a')
    endif
endfunction

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

    let l:line = getline('.')

    let l:ctx = asyncomplete#context()
    let l:startcol = l:ctx['col']
    let l:last_char = l:ctx['typed'][l:startcol - 2]

    let l:sources_to_notify = {}
    if has_key(b:asyncomplete_triggers, l:last_char)
        " TODO: also check for multiple chars instead of just last chars for
        " languages such as cpp which uses -> and ::
        for l:source_name in keys(b:asyncomplete_triggers[l:last_char])
            if !has_key(s:matches, l:source_name) || s:matches[l:source_name]['startcol'] != l:startcol
                let l:sources_to_notify[l:source_name] = 1
                let s:matches[l:source_name] = { 'startcol': l:startcol, 'status': 'notstarted', 'items': [] }
            endif
        endfor
    endif

    for l:source_name in b:asyncomplete_active_sources
        if !has_key(l:sources_to_notify, l:source_name)
            " loop left and find the start of the word and set it as the startcol for the source
            " let l:sources_to_notify[l:source_name] = 1
            " let s:matches[l:source_name] = { 'startcol': l:startcol, 'status': 'notstarted', 'items': [] }
        endif
    endfor

    if !empty(l:sources_to_notify)
        call s:trigger(keys(l:sources_to_notify), l:ctx)
    endif
endfunction

function! s:trigger(sources_to_notify, ctx) abort
    " send cancellation request if supported
    call asyncomplete#log('s:trigger', a:sources_to_notify, s:matches, a:ctx)
endfunction

function! asyncomplete#complete(name, ctx, startcol, matches, ...) abort
    let l:incomplete = a:0 > 0 ? a:1 : 0
endfunction
