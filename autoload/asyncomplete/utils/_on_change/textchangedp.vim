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
    call timer_start(100, { -> s:maybe_notify_on_change() })
endfunction

function! s:on_text_changed_i() abort
    call s:maybe_notify_on_change()
endfunction

function! s:on_text_changed_p() abort
    call s:maybe_notify_on_change()
endfunction

function! s:maybe_notify_on_change() abort
    for l:Cb in s:callbacks
        call l:Cb()
    endfor
endfunction

