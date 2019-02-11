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

function! s:on_insert_enter() abort
    call s:get_active_sources_for_buffer() " call to cache
endfunction

function! s:on_insert_leave() abort
    let s:active_source_names = []
endfunction

function! s:on_change() abort
    if mode() isnot# 'i'
        return
    endif

    call asyncomplete#log('core', 'on_change', getline('.'), getcurpos())
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
