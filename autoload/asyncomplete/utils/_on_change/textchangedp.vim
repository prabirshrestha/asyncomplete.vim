let s:callbacks = []

function! asyncomplete#utils#_on_change#textchangedp#init() abort
    return {
        \ 'name': 'TextChangedP',
        \ 'register': function('s:register'),
        \ 'unregister': function('s:unregister'),
    \ }
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

function! s:on_text_changed_i() abort
    call asyncomplete#log('i', s:previous_position, getcurpos())
    call s:maybe_notify_on_change()
endfunction

function! s:on_text_changed_p() abort
    call asyncomplete#log('p', s:previous_position, getcurpos())
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

