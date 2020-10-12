let s:callbacks = []

function! asyncomplete#utils#_on_change#textchangedp#init() abort
    if exists('##TextChangedP')
        call s:setup_if_required()
        return {
            \ 'name': 'TextChangedP',
            \ 'register': function('s:register'),
            \ 'unregister': function('s:unregister'),
        \ }
    else
        return { 'name': 'TextChangedP', 'error': 'Requires vim with TextChangedP support' }
    endif
endfunction

function! s:setup_if_required() abort
    augroup asyncomplete_utils_on_change_text_changed_p
        autocmd!
        autocmd InsertEnter * call s:on_insert_enter()
        autocmd InsertLeave * call s:on_insert_leave()
        autocmd TextChangedI * call s:on_text_changed_i()
        autocmd TextChangedP * call s:on_text_changed_p()
    augroup END
endfunction

function! s:register(cb) abort
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

function! s:on_text_changed_i() abort
    let l:ctx = asyncomplete#context()
    let l:startcol = l:ctx['col']
    let l:last_char = l:ctx['typed'][l:startcol - 2] " col is 1-indexed, but str 0-indexed
    if exists('b:asyncomplete_triggers') && has_key(b:asyncomplete_triggers, l:last_char)
        let s:previous_position = getcurpos()
    endif
    call s:maybe_notify_on_change()
endfunction

function! s:on_text_changed_p() abort
    call s:maybe_notify_on_change()
endfunction

function! s:maybe_notify_on_change() abort
    " enter to new line or backspace to previous line shouldn't cause change trigger
    let l:previous_position = s:previous_position
    let s:previous_position = getcurpos()
    if l:previous_position[1] ==# getcurpos()[1]
        for l:Cb in s:callbacks
            call l:Cb()
        endfor
    endif
endfunction
