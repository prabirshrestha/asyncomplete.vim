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
let s:previous_position = []

function! asyncomplete#log(...) abort
    if !empty(g:asyncomplete_log_file)
        call writefile([json_encode(a:000)], g:asyncomplete_log_file, 'a')
    endif
endfunction

function! s:setup_if_required() abort
    if !s:already_setup
        " register asyncomplete manager
        call asyncomplete#log('initializing asyncomplete manager', g:asyncomplete_manager)
        execute 'let s:manager = function("'. g:asyncomplete_manager  .'")()'
        call asyncomplete#log('initializing asyncomplete manager complete', s:manager['name'])

        " register asyncomplete change manager
        call asyncomplete#log('initializing asyncomplete change manager', g:asyncomplete_change_manager)
        execute 'let s:on_change_manager = function("'. g:asyncomplete_change_manager  .'")()'
        call s:on_change_manager.register(function('s:on_change'))
        call asyncomplete#log('initializing asyncomplete change manager complete', s:on_change_manager['name'])

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

function! s:on_change() abort
    call asyncomplete#log('on_change', getline('.'), getcurpos())
endfunction
