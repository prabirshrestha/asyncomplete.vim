let s:callbacks = []

function! asyncomplete#utils#_on_change#timer#init() abort
    return {
        \ 'name': 'timer',
        \ 'register': function('s:register'),
        \ 'unregister': function('s:unregister'),
    \ }
endfunction

function! s:setup_if_required() abort
    augroup asyncomplete_utils_on_change_timer
        autocmd!
        autocmd InsertEnter * call s:on_insert_enter()
        autocmd InsertLeave * call s:on_insert_leave()
    augroup END
endfunction

function! s:register(cb) abort
    call s:setup_if_required()
    call add(s:callbacks , a:cb)
endfunction


function! s:unregister(obj, cb) abort
    " TODO: remove from s:callbacks
endfunction

function! s:on_insert_enter() abort
    let s:previous_position = getcurpos()
endfunction

function! s:on_insert_leave() abort
    unlet s:previous_position
endfunction
